// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";

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

contract Farming is Ownable {
    address public poolGeneral; // Address of the general pool contract
    address public poolQuest; // Address of the quest pool contract
    address public poolReward; // Address of the quest pool contract
    address public vrfConsumerAddress; // Address of the Chainlink VRF consumer
    uint256 public axePrice; // Price of an Axe
    uint256 public sellerPrice; // Price of PremiumSeller
    address public nodeWallet; // Address of the node wallet

    // Mapping to restrict access to certain functions
    mapping(address => bool) public allowedContracts;

    //--- EVENTS ---//
    event AxePurchased(
        address indexed buyer, // Address of the buyer
        uint256 price, // Price paid for the axe
        string colonyId, // Associated colony ID
        string uuid // Socket unique identifier for tracking
    );
    event FundsWithdrawn(address indexed owner, uint256 amount);
    event NewPendingPremiumSellerCall(
        address indexed buyer, // Address of the buyer
        string colonyId, // Associated colony ID
        string sellerId, // Seller's ID
        string uuid, // Socket unique identifier for tracking,
        uint256 indexed requestId // Chainlink id request
    );
    event PremiumDiscountGenerated(
        address indexed ogRequester, // Original requester address
        uint256 chainLinkReqId, // Chainlink request ID
        uint256 chainLinkRandomValue, // Random value returned by Chainlink
        uint256 genPremiumDiscountValue // Generated discount value
    );

    event HPPackPurchased(
        address indexed buyer, // Address of the buyer
        uint256 price, // Price of the HP Pack
        string colonyId, // ID of the colony
        uint256 packId, // ID of the HP Pack
        string uuid // Socket unique identifier for tracking
    );

    event LvlRoomPurchased(
        address indexed buyer, // Address of the buyer
        uint256 amountPaid, // Amount paid
        string colonyId, // ID of the associated colony
        uint256 roomId, // ID of the room to be upgraded
        uint256 lvlToUpgrade, // Level to which the room will be upgraded
        string uuid // Socket unique identifier for tracking
    );

    event MaterialBoxPurchased(
        address indexed buyer, // Address of the buyer
        uint256 amountPaid, // Amount paid
        string boxId, // ID of the material box
        string uuid // Socket unique identifier for tracking
    );

    event QuestCompleted(
        string questType,
        address indexed buyer, // Address of the buyer
        string colonyId, // ID of the associated colony
        string questId, // ID of the associated quest
        uint256 amountPaid, // Amount paid
        uint256 npcId, // ID of the associated NPC
        uint256 requestId, // Chainlink request id if needed
        string uuid // Socket unique identifier for tracking
    );

    event PowerTicketPurchased(
        address indexed buyer,
        uint256 paidAmount,
        string colonyId,
        string uuid,
        string expeRewardId
    );

    event UsePowerTicketRequest(
        address indexed buyer,
        string powerTicketId,
        string colonyId,
        uint256 antId,
        bool fromQuest,
        string uuid
    );
    //--- END EVENTS ---//

    // Modifier to restrict function calls to allowed contracts
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    IERC20 public immutable nectarToken; // The ERC-20 token this pool works with

    /**
     * @dev Constructor to initialize the contract with required parameters
     * @param _poolGeneral Address of the general pool contract
     * @param _axePrice Initial price of the Axe
     * @param _sellerPrice Initial price of the PremiumSeller
     * @param _nodeWallet Address of the node wallet
     * @param _vrfConsumerAddress Address of the Chainlink VRF consumer contract
     */
    constructor(
        address _poolGeneral,
        address _poolQuest,
        address _poolReward,
        uint256 _axePrice,
        uint256 _sellerPrice,
        address _nodeWallet,
        address _vrfConsumerAddress,
        address _nectarAddress
    ) {
        require(_poolGeneral != address(0), "Invalid poolGeneral address");
        require(_poolQuest != address(0), "Invalid poolQuest address");
        require(_axePrice > 0, "Axe price must be greater than zero");
        require(_sellerPrice > 0, "Axe price must be greater than zero");
        require(_nectarAddress != address(0), "Invalid Nectar address");

        poolGeneral = _poolGeneral;
        poolQuest = _poolQuest;
        poolReward = _poolReward;
        axePrice = _axePrice;
        sellerPrice = _sellerPrice;
        vrfConsumerAddress = _vrfConsumerAddress;
        nodeWallet = _nodeWallet;
        nectarToken = IERC20(_nectarAddress);

        // Set deployer and node wallet as allowed contracts
        allowedContracts[msg.sender] = true;
        allowedContracts[nodeWallet] = true;
    }

    // Structure for individual discount values and their probabilities
    struct SellerDiscountPercentage {
        uint256 value; // Discount value
        uint256 percentage; // Occurrence probability
    }

    // Wrapper struct to hold an array of SellerDiscountPercentages
    struct SellerDiscountPercentages {
        SellerDiscountPercentage[] discounts; // Array of possible discount percentages
    }

    //--- AXE USE CASE ---//

    /// @notice Buy an Axe using the ERC-20 token instead of ETH
    /// @param colonyId The ID of the colony
    /// @param uuid The unique identifier for the purchase
    function buyAxe(string calldata colonyId, string calldata uuid) external {
        // Check if the buyer has allowed this contract to spend their tokens
        require(
            nectarToken.allowance(msg.sender, address(this)) >= axePrice,
            "Token allowance too low"
        );

        // Transfer tokens from the buyer to the poolGeneral contract
        require(
            nectarToken.transferFrom(msg.sender, poolGeneral, axePrice),
            "Token transfer failed"
        );

        emit AxePurchased(msg.sender, axePrice, colonyId, uuid);
    }

    /**
     * @notice Allows the contract owner to update the price of the Axe
     * @param newPrice New price for the Axe
     */
    function updateAxePrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        axePrice = newPrice;
    }

    //---  ---//

    //--- PREMIUM SELLER USE CASE ---//

    /**
     * @notice Allows the contract owner to update the PremiumSeller price
     * @param newPrice New price for the PremiumSeller
     */
    function updatePremiumSellerPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        sellerPrice = newPrice;
    }

    /**
     * @notice Handles PremiumSeller purchase, splits funds between node wallet and pool
     * @param colonyId ID of the colony
     * @param sellerId ID of the seller
     * @param uuid Socket unique identifier for tracking
     */
    function genPendingPremiumSellerCall(
        string calldata colonyId,
        string calldata sellerId,
        string calldata uuid
    ) external {
        require(
            nectarToken.allowance(msg.sender, address(this)) >= sellerPrice,
            "Token allowance too low"
        );

        // Transfer tokens from the buyer to the poolGeneral contract
        require(
            nectarToken.transferFrom(msg.sender, poolGeneral, sellerPrice),
            "Token transfer failed"
        );

        // call chainlink
        (uint256 requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
            .requestRandomWordsCustom(msg.sender, 1);

        emit NewPendingPremiumSellerCall(
            msg.sender,
            colonyId,
            sellerId,
            uuid,
            requestId
        );
    }

    /**
     * @notice Processes randomness and determines the generated discount value
     * @param chainLinkReqId Request ID from Chainlink
     * @param ogRequester Original requester address
     * @param chainLinkRandomValue Random value returned from Chainlink
     * @param discountPercents Struct containing possible discounts
     */
    function processRandomnessAndGenPremiumDiscount(
        uint256 chainLinkReqId,
        address ogRequester,
        uint256 chainLinkRandomValue,
        SellerDiscountPercentages memory discountPercents
    ) external onlyAllowed {
        uint256 sum = 0;
        for (uint256 i = 0; i < discountPercents.discounts.length; i++) {
            sum += discountPercents.discounts[i].percentage;
        }

        // Ensure the total probabilities sum to 100
        require(sum == 100, "SellerDiscountPercentages must sum to 99 or 100");

        // Adjust the random value to a range between 0 and 100
        uint256 adjustedRandomValue = chainLinkRandomValue % 101; // 0 to 100

        // Cumulative threshold to determine which discount applies
        uint256 cumulativeThreshold = 0;
        uint256 genPremiumDiscountValue = 0;

        for (uint256 i = 0; i < discountPercents.discounts.length; i++) {
            cumulativeThreshold += discountPercents.discounts[i].percentage;

            if (adjustedRandomValue <= cumulativeThreshold) {
                genPremiumDiscountValue = discountPercents.discounts[i].value;
                break;
            }
        }

        emit PremiumDiscountGenerated(
            ogRequester,
            chainLinkReqId,
            chainLinkRandomValue,
            genPremiumDiscountValue
        );
    }

    //---  ---//

    //--- HP PACKS USE CASE ---//

    /**
     * @notice Allows users to purchase quest HP Pack
     * @param colonyId ID of the colony to which the purchase relates
     * @param uuid Socket unique identifier for tracking
     */
    function buyHPPack(
        string calldata colonyId,
        uint256 packId,
        string calldata uuid,
        uint256 packPrice
    ) external {
        require(packPrice > 0, "Payment must be greater than zero");
        require(bytes(colonyId).length > 0, "Colony ID cannot be empty");
        require(bytes(uuid).length > 0, "UUID cannot be empty");

        // Create the MultiSwapParams struct
        IPoolGeneral.MultiSwapParams memory params = IPoolGeneral
            .MultiSwapParams({
                amountIn: packPrice,
                pool: poolGeneral,
                ogRequester: msg.sender,
                deadline: block.timestamp + 3000 //TODO change before testnet, its to much
            });

        // Call multiswap and Send
        IPoolGeneral(poolGeneral).multiSwapAndSend(params);

        // Emit the purchase event with detailed information
        emit HPPackPurchased(msg.sender, packPrice, colonyId, packId, uuid);
    }

    //--- ROOM USE CASE ---//

    /**
     * @notice Allows users to purchase a room upgrade by sending the correct amount
     * @param roomId ID of the room to be upgraded
     * @param colonyId ID of the colony associated with the upgrade
     * @param lvlToUpgrade Level to which the room will be upgraded
     * @param uuid Socket unique identifier for tracking
     */
    function buyUpgradeRoom(
        uint256 roomId,
        string calldata colonyId,
        uint256 lvlToUpgrade,
        string calldata uuid,
        uint256 upgradePrice
    ) external {
        require(
            nectarToken.allowance(msg.sender, address(this)) >= upgradePrice,
            "Token allowance too low"
        );

        // Transfer tokens from the buyer to the poolGeneral contract
        require(
            nectarToken.transferFrom(msg.sender, poolGeneral, upgradePrice),
            "Token transfer failed"
        );

        emit LvlRoomPurchased(
            msg.sender,
            upgradePrice,
            colonyId,
            roomId,
            lvlToUpgrade,
            uuid
        );
    }

    //--- MATERIAL BOX USE CASE ---//

    /**
     * @notice Allows users to purchase a material box
     * @param boxId ID of the box
     * @param uuid Socket unique identifier for tracking
     */
    function buyMaterialBox(
        string calldata boxId,
        string calldata uuid,
        uint256 boxPrice
    ) external {
        require(boxPrice > 0, "Payment must be greater than zero");
        require(bytes(boxId).length > 0, "Box ID cannot be empty");
        require(bytes(uuid).length > 0, "UUID cannot be empty");

        // // Forward funds to the general pool contract
        // (bool success, ) = payable(poolGeneral).call{value: msg.value}("");
        // require(success, "Transfer to PoolGeneral failed");

        IPoolGeneral.MultiSwapParams memory params = IPoolGeneral
            .MultiSwapParams({
                amountIn: boxPrice,
                pool: poolGeneral,
                ogRequester: msg.sender,
                deadline: block.timestamp + 3000 //TODO change before testnet, its to much
            });

        // Call multiswap and Send
        IPoolGeneral(poolGeneral).multiSwapAndSend(params);

        // Emit the event for the material box purchase
        emit MaterialBoxPurchased(msg.sender, boxPrice, boxId, uuid);
    }

    //--- QUEST USE CASE ---//

    /**
     * @notice Allows users to complete quest Nectar/Material
     * @param colonyId ID of the colony to which the purchase relates
     * @param questId ID of the quest to which the purchase relates
     * @param questType Type of the quest to which the purchase relates
     * @param uuid Socket unique identifier for tracking
     */
    function completeQuestForNectar(
        string calldata colonyId,
        string calldata questId,
        string calldata questType,
        uint256 npcId,
        string calldata uuid,
        uint256 nectarAmountCost
    ) external {
        require(bytes(colonyId).length > 0, "Colony ID cannot be empty");
        require(bytes(questId).length > 0, "Quest ID cannot be empty");
        require(bytes(questType).length > 0, "Quest Type cannot be empty");
        require(bytes(uuid).length > 0, "UUID cannot be empty");

        require(
            nectarToken.allowance(msg.sender, address(this)) >=
                nectarAmountCost,
            "Token allowance too low"
        );

        // Calculate 50% of the nectarAmountCost
        uint256 halfAmount = nectarAmountCost / 2;

        // Ensure the total amount is even to avoid rounding issues
        require(nectarAmountCost == halfAmount * 2, "Amount must be even");

        // Transfer the first 50% to PoolQuest
        require(
            nectarToken.transferFrom(msg.sender, poolQuest, halfAmount),
            "First token transfer failed"
        );

        // Transfer the second 50% to PoolReward
        require(
            nectarToken.transferFrom(msg.sender, poolReward, halfAmount),
            "Second token transfer failed"
        );

        emit QuestCompleted(
            questType,
            msg.sender,
            colonyId,
            questId,
            nectarAmountCost,
            npcId,
            0, //bc no needed here
            uuid
        );
    }

    function completeFreeQuest(
        string calldata colonyId,
        string calldata questId,
        string calldata questType,
        uint256 npcId,
        string calldata uuid,
        bool needRandomWords,
        uint32 nWords
    ) external {
        require(bytes(colonyId).length > 0, "Colony ID cannot be empty");
        require(bytes(questId).length > 0, "Quest ID cannot be empty");
        require(bytes(questType).length > 0, "Quest Type cannot be empty");
        require(bytes(uuid).length > 0, "UUID cannot be empty");

        uint256 requestId;

        if (needRandomWords && nWords > 0) {
            (requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
                .requestRandomWordsCustom(msg.sender, nWords);
        }

        emit QuestCompleted(
            questType,
            msg.sender,
            colonyId,
            questId,
            0,
            npcId,
            requestId,
            uuid
        );
    }

    //--- POWER TICKET ---//

    /**
     * @notice Allows a user to purchase a power ticket for a specified colony.
     * @dev Transfers the payment to the general pool contract and emits a `PowerTicketPurchased` event.
     *
     * @param colonyId The ID of the colony associated with the power ticket purchase.
     * @param expeRewardId The ID of the expeReward associated with the power ticket purchase.
     * @param uuid A unique identifier for tracking the ticket purchase request.
     *
     * PowerTicketPurchased Emitted with details of the power ticket purchase, including
     * the buyer's address, payment amount, ticket ID, colony ID, and tracking UUID.
     *
     */
    function buyPowerTicket(
        string calldata colonyId,
        string calldata expeRewardId,
        string calldata uuid,
        uint256 ticketPrice
    ) external {
        require(
            nectarToken.allowance(msg.sender, address(this)) >= ticketPrice,
            "Token allowance too low"
        );

        // Transfer tokens from the buyer to the poolGeneral contract
        require(
            nectarToken.transferFrom(msg.sender, poolGeneral, ticketPrice),
            "Token transfer failed"
        );

        emit PowerTicketPurchased(
            msg.sender,
            ticketPrice,
            colonyId,
            uuid,
            expeRewardId
        );
    }

    /**
     * @notice Allows a user to use a power ticket in a specific colony for a specific ant.
     * @dev Emits a `UsePowerTicketRequest` event to log the details of the power ticket usage.
     *
     * @param powerTicketId The unique identifier of the power ticket being used.
     * @param colonyId The ID of the colony where the power ticket is being used.
     * @param antId The ID of the ant associated with the power ticket usage.
     * @param uuid A unique identifier for tracking the ticket usage request.
     *
     * emit UsePowerTicketRequest Emitted with details of the power ticket usage, including
     * the user, ticket ID, colony ID, ant ID, and tracking UUID.
     */
    function usePowerTicket(
        string calldata powerTicketId,
        string calldata colonyId,
        uint256 antId,
        bool fromQuest,
        string calldata uuid
    ) external {
        emit UsePowerTicketRequest(
            msg.sender,
            powerTicketId,
            colonyId,
            antId,
            fromQuest,
            uuid
        );
    }

    /**
     * @notice Allows the owner to update the nodeAddress.
     * @param _newNodeAddress Address of the new node.
     */
    function updateNodeAddress(address _newNodeAddress) external onlyOwner {
        require(_newNodeAddress != address(0), "Invalid node address");
        nodeWallet = _newNodeAddress;
    }

    /**
     * @notice Allows the owner to update the poolGeneral address.
     * @param _newPoolGeneral Address of the new general pool contract.
     */
    function updatePoolGeneral(address _newPoolGeneral) external onlyOwner {
        require(_newPoolGeneral != address(0), "Invalid general pool address");
        poolGeneral = _newPoolGeneral;
    }

    /**
     * @notice Allows the owner to update the poolQuest address.
     * @param _newPoolQuest Address of the new quest pool contract.
     */
    function updatePoolQuest(address _newPoolQuest) external onlyOwner {
        require(_newPoolQuest != address(0), "Invalid quest pool address");
        poolQuest = _newPoolQuest;
    }

    /**
     * @notice Allows the owner to update the poolReward address.
     * @param _newPoolReward Address of the new reward pool contract.
     */
    function updatePoolReward(address _newPoolReward) external onlyOwner {
        require(_newPoolReward != address(0), "Invalid reward pool address");
        poolReward = _newPoolReward;
    }
}
