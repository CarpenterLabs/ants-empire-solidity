// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.5.0/security/ReentrancyGuard.sol";

interface IChainlinkVRFAntConsumer {
    function requestRandomWordsByKind(address requester, string memory kind)
        external
        returns (
            uint256 requestId,
            uint32 words,
            address ogRequester,
            string memory kindOf
        );

    function requestRandomWordsCustom(address requester, uint32 nWords)
        external
        returns (
            uint256 requestId,
            uint32 words,
            address ogRequester,
            string memory kindOf
        );

    function getRequestStatus(uint256 requestId)
        external
        view
        returns (bool fulfilled, uint256[] memory randomWords);
}

contract ANT is ERC721URIStorage, IERC721Receiver, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    mapping(address => bool) public allowedContracts;

    address public vrfConsumerAddress;
    address public poolGeneral;
    address private nodeWallet;
    uint256 public nftPrice;
    uint256 private _tokenIds;

    // Nested struct for min and max power
    struct PowerRange {
        uint256 min;
        uint256 max;
    }

    // Main struct to group different rarity types
    struct AntPowerStruct {
        PowerRange common;
        PowerRange rare;
        PowerRange epic;
        PowerRange legendary;
    }

    AntPowerStruct antPowerRanges =
        AntPowerStruct(
            PowerRange(1, 50), // Common
            PowerRange(51, 100), // Rare
            PowerRange(101, 150), // Epic
            PowerRange(151, 200) // Legendary
        );

    // Enum to represent rarity types
    enum Rarity {
        COMMON,
        RARE,
        EPIC,
        LEGENDARY
    }
    // Declare an array with the string representations of the Rarity enum
    string[] private rarityStrings = ["COMMON", "RARE", "EPIC", "LEGENDARY"];

    enum AntTypes {
        WORKER,
        SOLDIER,
        FLYING
    }
    string[] private typeStrings = ["WORKER", "SOLDIER", "FLYING"];

    // Mapping of string to Rarity enum
    // mapping(string => Rarity) public rarityMap;

    // Struct custom percentages param definition
    struct RarityPercentages {
        uint256 common; // Represented in percentage (e.g., 6000 for 60%)
        uint256 rare; // Represented in percentage (e.g., 3700 for 37%)
        uint256 epic; // Represented in percentage (e.g., 250 for 2.5%)
        uint256 legendary; // Represented in percentage (e.g., 050 for 0.5%)
    }

    struct TypePercentages {
        uint256 worker;
        uint256 soldier;
        uint256 flying;
    }

    event NFTMinted(address indexed buyer, uint256 tokenId);
    event NFTMintedInPack(
        address indexed buyer,
        uint256 tokenId,
        string tokenUri
    );
    event Whitelisted(address indexed buyer);
    event NewPendingMint(address indexed buyer, uint256 requestId, string uuid);
    event NFTAttributesGenerated(
        address indexed ogRequester,
        uint256 indexed requestId,
        uint256 chainLinkRandomValue,
        string genRarityStr,
        string genTypeStr,
        uint256 genPower
    );

    // Modifier to restrict access
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    IERC20 public immutable nectarAddress;

    constructor(
        address _vrfConsumerAddress,
        address _poolGeneral,
        address _nodeWallet,
        uint256 _nftPrice,
        address _nectarAddress
    ) ERC721("Ants", "ANT") {
        vrfConsumerAddress = _vrfConsumerAddress;
        nftPrice = _nftPrice;
        poolGeneral = _poolGeneral;
        nodeWallet = _nodeWallet;
        nectarAddress = IERC20(_nectarAddress);

        // Set NODE and deployer as allowed contracts
        allowedContracts[msg.sender] = true;
        allowedContracts[nodeWallet] = true;
    }

    // Add more allowed contracts dynamically if needed
    function addAllowedContract(address _contract) external onlyOwner {
        allowedContracts[_contract] = true;
    }

    // Implement the onERC721Received function

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function mintNFT(address buyer, string memory tokenURI)
        external
        onlyAllowed
        returns (uint256)
    {
        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _safeMint(buyer, newTokenId);
        _setTokenURI(newTokenId, tokenURI);

        emit NFTMinted(buyer, newTokenId);
        return newTokenId;
    }

    function genPendingMintForNFT(string memory uuid) external {
        require(
            nectarAddress.allowance(msg.sender, address(this)) >= nftPrice,
            "Token allowance too low"
        );

        // Transfer tokens directly to the general pool
        require(
            nectarAddress.transferFrom(msg.sender, poolGeneral, nftPrice),
            "Token transfer to poolGeneral failed"
        );

        // call chainlink
        (uint256 requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
            .requestRandomWordsByKind(msg.sender, "MINT");

        emit NewPendingMint(msg.sender, requestId, uuid);
    }

    /// @param newPrice New price of the nft in ETH
    function updateNftPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        nftPrice = newPrice;
    }

    // custom fn to request randomness for a erc721 mint process
    function requestRandomnessForMint(address ogBuyer) public onlyAllowed {
        IChainlinkVRFAntConsumer(vrfConsumerAddress).requestRandomWordsByKind(
            ogBuyer,
            "MINT"
        );
    }

    /**
     * @notice Batch calls processRandomnessAndGenAttrs multiple times with unique inputs.
     */
    function batchProcessRandomness(
        uint256 chainLinkReqId,
        address ogRequester,
        uint256[] calldata chainLinkRandomValues,
        RarityPercentages[] calldata rarityPercents,
        TypePercentages[] calldata typePercents,
        uint256 count
    ) external {
        require(
            count > 0 &&
                count <= chainLinkRandomValues.length &&
                count <= rarityPercents.length &&
                count <= typePercents.length,
            "Invalid count or mismatched input lengths"
        );

        for (uint256 i = 0; i < count; ++i) {
            processRandomnessAndGenAttrs(
                chainLinkReqId,
                ogRequester,
                chainLinkRandomValues[i],
                rarityPercents[i],
                typePercents[i]
            );
        }
    }

    // Function to calculate rarity dynamically
    function getRarityCustom(
        uint256 randomValue,
        RarityPercentages memory percentages
    ) internal pure returns (Rarity) {
        // Ensure the total sum of values is exactly 10,000
        require(
            percentages.common +
                percentages.rare +
                percentages.epic +
                percentages.legendary ==
                10000,
            "RarityPercentages must sum to 10000"
        );

        // Adjust the modulo result to fit the 1-10,000 range
        uint256 adjustedRandomValue = (randomValue % 10000) + 1;

        // Determine thresholds dynamically
        uint256 cumulativeThreshold = 0;

        // Check against the LEGENDARY threshold
        cumulativeThreshold += percentages.legendary;
        if (adjustedRandomValue <= cumulativeThreshold) {
            return Rarity.LEGENDARY;
        }

        // Check against the EPIC threshold
        cumulativeThreshold += percentages.epic;
        if (adjustedRandomValue <= cumulativeThreshold) {
            return Rarity.EPIC;
        }

        // Check against the RARE threshold
        cumulativeThreshold += percentages.rare;
        if (adjustedRandomValue <= cumulativeThreshold) {
            return Rarity.RARE;
        }

        // If none matched, it must be COMMON
        return Rarity.COMMON;
    }

    function getPowerByRange(uint256 randomValue, Rarity rarity)
        internal
        view
        returns (uint256 power)
    {
        PowerRange memory range;

        if (rarity == Rarity.COMMON) {
            range = antPowerRanges.common;
        } else if (rarity == Rarity.RARE) {
            range = antPowerRanges.rare;
        } else if (rarity == Rarity.EPIC) {
            range = antPowerRanges.epic;
        } else if (rarity == Rarity.LEGENDARY) {
            range = antPowerRanges.legendary;
        } else {
            revert("Invalid rarity");
        }

        uint256 rangeSize = range.max - range.min + 1;
        uint256 scaledValue = (randomValue % rangeSize) + range.min;

        // Return power and the string representation of the rarity
        return scaledValue;
    }

    function getType(uint256 randomValue, TypePercentages memory percentages)
        internal
        pure
        returns (AntTypes t)
    {
        // Ensure the total sum of values is exactly 100 or 99
        uint256 sum = percentages.worker +
            percentages.soldier +
            percentages.flying;
        require(
            sum == 99 || sum == 100,
            "TypePercentages must sum to 99 or 100"
        );

        // Reduce the random value to the range [0, sum)
        uint256 adjustedRandomValue = randomValue % sum;

        // Use thresholds directly to determine type
        if (adjustedRandomValue < percentages.worker) {
            return AntTypes.WORKER;
        } else if (
            adjustedRandomValue < percentages.worker + percentages.soldier
        ) {
            return AntTypes.SOLDIER;
        } else {
            return AntTypes.FLYING;
        }
    }

    function processRandomnessAndGenAttrs(
        uint256 chainLinkReqId,
        address ogRequester,
        uint256 chainLinkRandomValue,
        RarityPercentages memory rarityPercents,
        TypePercentages memory typePercents
    ) public onlyAllowed {
        Rarity generatedRarity = getRarityCustom(
            chainLinkRandomValue,
            rarityPercents
        );
        AntTypes genType = getType(chainLinkRandomValue, typePercents);
        uint256 genPower = getPowerByRange(
            chainLinkRandomValue,
            generatedRarity
        );

        // Prepare readable data
        string memory genRaritytStr = enumToString(
            uint8(generatedRarity),
            rarityStrings
        );
        string memory genTypeStr = enumToString(uint8(genType), typeStrings);

        emit NFTAttributesGenerated(
            ogRequester,
            chainLinkReqId,
            chainLinkRandomValue,
            genRaritytStr,
            genTypeStr,
            genPower
        );
    }

    // Used to upgrade ant power mainly
    function updateMetadata(uint256 tokenId, string memory newTokenURI)
        public
        onlyAllowed
    {
        _setTokenURI(tokenId, newTokenURI);
    }

    function withdraw() external onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }

    function enumToString(uint8 enumValue, string[] storage stringArray)
        internal
        view
        returns (string memory)
    {
        // Check for valid enum range to prevent out-of-bounds access
        require(enumValue < stringArray.length, "Invalid value");

        // Directly access the corresponding string in the array
        return stringArray[enumValue];
    }

    // Transfer NFT to a desired address
    function transferToAddress(address to, uint256 tokenId)
        external
        onlyAllowed
    {
        // Ensure the contract owns the token
        require(
            ownerOf(tokenId) == address(this),
            "Contract does not own this token"
        );

        // Transfer ownership to the desired address
        _safeTransfer(address(this), to, tokenId, "");
    }

    // BATCH MINT
    // Mint multiple NFTs dynamically based on received tokenURIs (keeping ownership)
    function mintBatch(
        address ogBuyer,
        string[] memory tokenURIs,
        bool toContract
    ) external onlyAllowed {
        // Loop through the tokenURIs array
        for (uint256 i = 0; i < tokenURIs.length; i++) {
            _tokenIds++;
            uint256 newTokenId = _tokenIds;

            // Mint NFT to the contract's address
            _safeMint(toContract ? address(this) : ogBuyer, newTokenId);

            // Set token URI for the newly minted token
            _setTokenURI(newTokenId, tokenURIs[i]);

            emit NFTMintedInPack(ogBuyer, newTokenId, tokenURIs[i]);
        }
    }

    function updatePoolGeneral(address _newPoolGeneral) external onlyOwner {
        require(_newPoolGeneral != address(0), "Invalid pool address");
        poolGeneral = _newPoolGeneral;
    }

    function updateNodeWallet(address _newNodeWallet) external onlyOwner {
        require(_newNodeWallet != address(0), "Invalid node wallet address");
        allowedContracts[_newNodeWallet] = true; // Optional: Add to allowed contracts
        nodeWallet = _newNodeWallet;
    }
}
