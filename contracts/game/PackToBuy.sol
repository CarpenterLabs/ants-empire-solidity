// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";

interface ANTNFTSC {
    function mintBatch(
        address ofBuyer,
        string[] memory tokenURIs,
        bool toContract
    ) external;

    function transferToAddress(address to, uint256 tokenId) external;
}

// Interface to interact with Chainlink VRF (Verifiable Random Function) consumer
interface IChainlinkVRFAntConsumer {
    function requestRandomWordsCustom(address requester, uint32 nWords)
        external
        returns (
            uint256 requestId,
            uint32 words,
            address ogRequester,
            string memory kindOf
        );
}

interface IPoolGeneral {
    struct MultiSwapParams {
        uint256 amountIn;
        address pool;
        address ogRequester;
        uint256 deadline;
    }

    function multiSwapAndSend(MultiSwapParams calldata params) external;
}

contract PackToBuy is Ownable {
    using SafeERC20 for IERC20;
    // Owner for access control
    address vrfConsumerAddress;
    address nodeWallet;
    address poolGeneral;
    mapping(address => bool) public allowedContracts;
    address public antNFTSCAddress;

    // -------------------- Events --------------------

    event WelcomePackPurchased(
        address indexed playerAddress,
        string welcomePackId,
        string packFamily,
        string colonyId,
        uint256 pricePaid,
        uint256 requestId,
        string uuid
    );

    event PackBurned(address indexed playerAddress, string welcomePackId);
    event WelcomePackResolveRequest(
        address indexed playerAddress,
        string welcomePackId,
        string family,
        string uuid
    );

    event WelcomePackResolved(address indexed playerAddress);

    event PackToBuyPurchaseRequest(
        address indexed playerAddress,
        string colonyId,
        uint256 amountPaid,
        string packToBuyId,
        string packFamily,
        uint256 requestId,
        string uuid
    );

    // Modifier to restrict access
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    // Add more allowed contracts dynamically if needed
    function addAllowedContract(address _contract) external onlyOwner {
        allowedContracts[_contract] = true;
    }

    // Struct for editable WelcomePack entries
    struct WelcomePackEntry {
        string welcomePackId; // Unique identifier for the welcome pack
        uint256 price; // Base price of the welcome pack
    }

    // Struct for historical records
    struct PurchaseDetail {
        string welcomePackId;
        bool burned; // Tracks if the pack is burned
        uint256 pricePaid;
    }

    // Historical purchases: mapping from player to their total purchase count
    mapping(address => uint256) public playerPurchaseCount;

    // Detailed purchase history: player => purchase index => PurchaseDetail
    mapping(address => mapping(uint256 => PurchaseDetail))
        public playerPurchaseDetails;

    // Discount tiers based on purchase count
    uint256[] public discountTiers = [0, 420, 660, 820, 970]; // Discounts in basis points (4.2% = 420)

    // Editable welcome pack "database"
    mapping(string => WelcomePackEntry) public welcomePackDatabase;

    IERC20 public immutable nectarToken; // The ERC-20 token this pool works with
    IERC20 public immutable usdt; // The ERC-20 token this pool works with

    constructor(
        address _antNFTSCAddress,
        address _nodeWallet,
        address _vrfConsumerAddress,
        address _poolSC,
        address _nectarAddress,
        address _usdt
    ) {
        require(_poolSC != address(0), "Invalid poolSC address");
        require(_nectarAddress != address(0), "Invalid Nectar address");

        antNFTSCAddress = _antNFTSCAddress;
        vrfConsumerAddress = _vrfConsumerAddress;
        nodeWallet = _nodeWallet;
        poolGeneral = _poolSC;
        nectarToken = IERC20(_nectarAddress);
        usdt = IERC20(_usdt);

        // Initialize welcome pack entries
        welcomePackDatabase["WELCOME_PACK_1"] = WelcomePackEntry({
            welcomePackId: "WELCOME_PACK_1",
            price: (499 * 10**4)
        });

        welcomePackDatabase["WELCOME_PACK_2"] = WelcomePackEntry({
            welcomePackId: "WELCOME_PACK_2",
            price: (999 * 10**4)
        });

        welcomePackDatabase["WELCOME_PACK_3"] = WelcomePackEntry({
            welcomePackId: "WELCOME_PACK_3",
            price: (1499 * 10**4)
        });

        welcomePackDatabase["WELCOME_PACK_4"] = WelcomePackEntry({
            welcomePackId: "WELCOME_PACK_4",
            price: (2499 * 10**4)
        });

        // Set NODE and deployer as allowed contracts
        allowedContracts[msg.sender] = true;
        allowedContracts[_nodeWallet] = true;
    }

    // -------------------- CRUD Functions for Editable Database --------------------

    /**
     * @notice Adds a new welcome pack to the database.
     */
    function addWelcomePack(string calldata _id, uint256 _price)
        external
        onlyOwner
    {
        require(bytes(_id).length > 0, "ID cannot be empty");
        require(welcomePackDatabase[_id].price == 0, "Pack already exists");

        welcomePackDatabase[_id] = WelcomePackEntry({
            welcomePackId: _id,
            price: _price
        });
    }

    /**
     * @notice Updates an existing welcome pack in the database.
     */
    function updateWelcomePack(string calldata _id, uint256 _newPrice)
        external
        onlyOwner
    {
        require(welcomePackDatabase[_id].price > 0, "Pack does not exist");

        welcomePackDatabase[_id].price = _newPrice;
    }

    /**
     * @notice Deletes a welcome pack from the database.
     */
    function deleteWelcomePack(string calldata _id) external onlyOwner {
        require(welcomePackDatabase[_id].price > 0, "Pack does not exist");
        delete welcomePackDatabase[_id];
    }

    /**
     * @notice Retrieves a welcome pack from the database.
     */
    function getWelcomePack(string calldata _id)
        external
        view
        returns (WelcomePackEntry memory)
    {
        require(welcomePackDatabase[_id].price > 0, "Pack does not exist");
        return welcomePackDatabase[_id];
    }

    // -------------------- Purchase Function with Discount Logic --------------------

    /// @notice Function to buy a welcome pack with dynamic discount logic
    /// @param welcomePackId ID of the welcome pack to purchase
    function buyWelcomePack(
        string calldata welcomePackId,
        string memory packFamily,
        string memory colonyId,
        uint32 count,
        uint256 packPrice,
        string memory uuid
    ) external {
        //TODO ADD A FLAG HERE CHECKING IF SOME OTHER WPACK PROCESS GOING ON??

        // Check if the welcome pack exists
        WelcomePackEntry memory pack = welcomePackDatabase[welcomePackId];
        require(
            bytes(pack.welcomePackId).length > 0,
            "Welcome pack does not exist"
        );

        // Check if the player has already purchased this pack
        uint256 purchaseCount = playerPurchaseCount[msg.sender];

        for (uint256 i = 0; i < purchaseCount; i++) {
            PurchaseDetail memory purchase = playerPurchaseDetails[msg.sender][
                i
            ];

            // Check if the welcome pack ID matches
            require(
                keccak256(abi.encodePacked(purchase.welcomePackId)) !=
                    keccak256(abi.encodePacked(welcomePackId)),
                "Pack already purchased"
            );
        }

        // Determine discount based on player's purchase history count
        uint256 discount = getDiscountByPurchaseCount(purchaseCount);

        // Calculate the final price with discount
        uint256 finalPrice = pack.price;
        if (discount > 0) {
            finalPrice = pack.price - ((pack.price * discount) / 10000); // discount in basis points
        }

        // Check if the value sent matches the discounted price
        require(
            packPrice >= finalPrice,
            "Insufficient payment for this welcome pack"
        );

        // Allowance check TODO
        require(
            usdt.allowance(msg.sender, poolGeneral) >= finalPrice,
            "Token allowance too low"
        );

        require(finalPrice > 0, "finalPrice is zero!");

        // Create the MultiSwapParams struct
        IPoolGeneral.MultiSwapParams memory params = IPoolGeneral
            .MultiSwapParams({
                amountIn: finalPrice,
                pool: poolGeneral,
                ogRequester: msg.sender,
                deadline: block.timestamp + 3000 //TODO change before testnet, its to much
            });

        // Call multiswap and Send
        IPoolGeneral(poolGeneral).multiSwapAndSend(params);

        // Generate the randomRequest on chainlink and get the requestId
        (uint256 requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
            .requestRandomWordsCustom(msg.sender, count);

        // Record the purchase
        playerPurchaseDetails[msg.sender][purchaseCount] = PurchaseDetail({
            welcomePackId: welcomePackId,
            burned: false,
            pricePaid: finalPrice
        });
        playerPurchaseCount[msg.sender]++;

        // Emit an event for logging
        emit WelcomePackPurchased(
            msg.sender,
            welcomePackId,
            packFamily,
            colonyId,
            finalPrice,
            requestId,
            uuid
        );
    }

    // tipically called when buying a welcomepack
    function mintBatchAnts(
        address ogBuyer,
        string[] memory tokenUris,
        bool toContract
    ) external onlyAllowed {
        // require(pendingMint[ogBuyer], "Not pendingMint");
        ANTNFTSC(antNFTSCAddress).mintBatch(ogBuyer, tokenUris, toContract);
    }

    /// @notice Get the entire purchase history of a player
    /// @param playerAddress Address of the player
    /// @return purchases An array of PurchaseDetail structs representing the player's purchase history
    function getPlayerPurchaseHistory(address playerAddress)
        public
        view
        returns (PurchaseDetail[] memory purchases)
    {
        uint256 purchaseCount = playerPurchaseCount[playerAddress];
        purchases = new PurchaseDetail[](purchaseCount); // Initialize a dynamic array in memory

        // Loop through the purchase history and populate the array
        for (uint256 i = 0; i < purchaseCount; i++) {
            purchases[i] = playerPurchaseDetails[playerAddress][i];
        }

        return purchases;
    }

    /// @notice Get the discount percentage based on the purchase count
    /// @param purchaseCount Number of packs already purchased by the user
    function getDiscountByPurchaseCount(uint256 purchaseCount)
        public
        view
        returns (uint256)
    {
        if (purchaseCount >= discountTiers.length) {
            return discountTiers[discountTiers.length - 1]; // Max discount
        }
        return discountTiers[purchaseCount];
    }

    /// @notice Get the number of welcome packs a player has purchased
    /// @param playerAddress Address of the player
    /// @return The number of packs the player has purchased
    function getPlayerPurchaseCount(address playerAddress)
        external
        view
        returns (uint256)
    {
        return playerPurchaseCount[playerAddress];
    }

    /**
     * @notice Requests randomness from Chainlink VRF
     * @param ogBuyer Original buyer's address
     */
    function requestRandomnessForPackMint(address ogBuyer, uint32 count)
        internal
        returns (uint256 requestId)
    {
        (requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
            .requestRandomWordsCustom(ogBuyer, count);

        return requestId;
    }

    function withdraw() external onlyAllowed {
        payable(owner()).transfer(address(this).balance);
    }

    // Function to set the burned property to true
    function setBurned(address playerAddress, string calldata welcomePackId)
        external
        onlyAllowed
    {
        // Check if the welcome pack exists
        WelcomePackEntry memory pack = welcomePackDatabase[welcomePackId];
        require(
            bytes(pack.welcomePackId).length > 0,
            "Welcome pack does not exist"
        );

        // Check if the player purchased the specific pack previously
        PurchaseDetail[] memory purchases = getPlayerPurchaseHistory(
            playerAddress
        );
        bool found = false;

        for (uint256 i = 0; i < purchases.length; i++) {
            if (
                keccak256(abi.encodePacked(purchases[i].welcomePackId)) ==
                keccak256(abi.encodePacked(welcomePackId))
            ) {
                require(!purchases[i].burned, "Pack already burned");
                playerPurchaseDetails[playerAddress][i].burned = true;
                found = true;
                break;
            }
        }

        require(found, "Pack not found in purchase history");
        emit PackBurned(playerAddress, welcomePackId);
    }

    function requestResolveWelcomePack(
        address playerAddress,
        string memory welcomePackId,
        string memory family,
        string memory uuid
    ) external {
        // Check if the welcome pack exists
        WelcomePackEntry memory pack = welcomePackDatabase[welcomePackId];
        require(
            bytes(pack.welcomePackId).length > 0,
            "Welcome pack does not exist"
        );

        uint256 purchaseCount = playerPurchaseCount[playerAddress];
        bool found = false;

        for (uint256 i = 0; i < purchaseCount; i++) {
            PurchaseDetail storage purchase = playerPurchaseDetails[
                playerAddress
            ][i];

            // Check if the player owns the pack
            if (
                keccak256(abi.encodePacked(purchase.welcomePackId)) ==
                keccak256(abi.encodePacked(welcomePackId))
            ) {
                // Check if the pack is already burned
                require(!purchase.burned, "Pack already burned");

                found = true;
                break;
            }
        }

        require(found, "Pack not found in purchase history");

        emit WelcomePackResolveRequest(
            playerAddress,
            welcomePackId,
            family,
            uuid
        );
    }

    function batchNftTransferToAddress(
        address player,
        uint256[] calldata tokenIds
    ) external onlyAllowed {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ANTNFTSC(antNFTSCAddress).transferToAddress(player, tokenIds[i]);
        }
        emit WelcomePackResolved(player);
    }

    function buyPack(
        address player,
        string calldata colonyId,
        string calldata packToBuyId,
        string calldata packFamily,
        string calldata uuid,
        uint32 count,
        uint256 packPrice
    ) external {
        require(
            nectarToken.allowance(msg.sender, address(this)) >= packPrice,
            "Token allowance too low"
        );

        // Transfer tokens from the buyer to the poolGeneral contract
        require(
            nectarToken.transferFrom(msg.sender, poolGeneral, packPrice),
            "Token transfer failed"
        );

        uint256 requestId = requestRandomnessForPackMint(msg.sender, count);

        emit PackToBuyPurchaseRequest(
            player,
            colonyId,
            packPrice,
            packToBuyId,
            packFamily,
            requestId,
            uuid
        );
    }

    /**
     * @notice Allows the owner to update the VRF Consumer contract address.
     * @param _newVRFConsumer Address of the new VRF Consumer.
     */
    function updateVRFConsumerAddress(address _newVRFConsumer)
        external
        onlyOwner
    {
        require(_newVRFConsumer != address(0), "Invalid VRF address");
        vrfConsumerAddress = _newVRFConsumer;
    }

    /**
     * @notice Allows the owner to update the nodeWallet address and add it to allowedContracts.
     * @param _newNodeWallet Address of the new node wallet.
     */
    function updateNodeWallet(address _newNodeWallet) external onlyOwner {
        require(_newNodeWallet != address(0), "Invalid node wallet address");
        nodeWallet = _newNodeWallet;
        allowedContracts[_newNodeWallet] = true;
    }

    /**
     * @notice Allows the owner to update the poolGeneral address.
     * @param _newPoolGeneral Address of the new general pool.
     */
    function updatePoolGeneral(address _newPoolGeneral) external onlyOwner {
        require(_newPoolGeneral != address(0), "Invalid pool address");
        poolGeneral = _newPoolGeneral;
    }

    /**
     * @notice Allows the owner to update the ANT NFTs contract address.
     * @param _newAntNFTSC Address of the new ANT NFTs contract.
     */
    function updateAntNFTSCAddress(address _newAntNFTSC) external onlyOwner {
        require(_newAntNFTSC != address(0), "Invalid ANT NFT contract address");
        antNFTSCAddress = _newAntNFTSC;
    }
}
