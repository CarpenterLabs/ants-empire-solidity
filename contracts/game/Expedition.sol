// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";

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

contract Expedition is Ownable {
    using SafeERC20 for IERC20;
    // -------------------- State Variables --------------------
    address public vrfConsumerAddress;
    address public nodeWallet;
    address public rewardPool;
    address public questPool;
    address public generalPool;
    address public nodeAddress;
    uint256 public lastDistributionTime; // TimeStamp of last distribution
    uint256 public rewardPercentage; // Represented as whole numbers, e.g., 70 for 70%
    uint256 public questPercentage; // Represented as whole numbers, e.g., 20 for 20%
    uint256 public distributionInterval; // Distribution interval in seconds

    mapping(address => bool) public allowedContracts;

    // -------------------- Events --------------------
    event PendingExpeditionExecution(
        address indexed player,
        uint256 destinationId,
        string colonyId,
        uint256 amountPaid,
        uint256[] antsIds,
        string uuid,
        uint256 requestId
    );
    event ExpeditionResult(
        address ogBuyer,
        string colonyId,
        uint256 diceRollResult,
        uint256 successPercentScaled,
        bool success
    );
    event NectarDistributed(
        uint256 timestamp,
        uint256 totalNectar,
        uint256 transferredToRewardPool,
        uint256 transferredToQuestPool
    );
    event RewardPercentageUpdated(uint256 newRewardPercentage);
    event QuestPercentageUpdated(uint256 newQuestPercentage);
    event DistributionIntervalUpdated(uint256 newInterval);

    // -------------------- Modifiers --------------------
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    IERC20 public immutable nectarToken; // The ERC-20 token this pool works with

    // -------------------- Constructor --------------------
    constructor(
        address _nodeWallet,
        address _vrfConsumerAddress,
        address _rewardPoolSC,
        address _questPoolSC,
        address _generalPoolSC,
        address _nectarAddress
    ) {
        vrfConsumerAddress = _vrfConsumerAddress;
        nodeWallet = _nodeWallet;
        rewardPool = _rewardPoolSC;
        questPool = _questPoolSC;
        generalPool = _generalPoolSC;
        nectarToken = IERC20(_nectarAddress);

        // Set NODE and deployer as allowed contracts
        allowedContracts[msg.sender] = true;
        allowedContracts[_nodeWallet] = true;

        // -------------------- Initialize Trigger Variables --------------------
        rewardPercentage = 70;
        questPercentage = 20;
        distributionInterval = 24 hours;
    }

    // -------------------- Access Management --------------------

    /// @notice Add a new allowed contract
    /// @param _contract The contract address to allow
    function addAllowedContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid contract address");
        allowedContracts[_contract] = true;
    }

    // -------------------- Trigger Management --------------------

    /// @notice Update the reward pool percentage
    /// @param _newRewardPercentage New percentage for the rewardPool
    function setRewardPercentage(uint256 _newRewardPercentage)
        external
        onlyOwner
    {
        require(
            _newRewardPercentage + questPercentage <= 100,
            "Total percentages exceed 100"
        );
        rewardPercentage = _newRewardPercentage;
        emit RewardPercentageUpdated(_newRewardPercentage);
    }

    /// @notice Update the quest pool percentage
    /// @param _newQuestPercentage New percentage for the questPool
    function setQuestPercentage(uint256 _newQuestPercentage)
        external
        onlyOwner
    {
        require(
            rewardPercentage + _newQuestPercentage <= 100,
            "Total percentages exceed 100"
        );
        questPercentage = _newQuestPercentage;
        emit QuestPercentageUpdated(_newQuestPercentage);
    }

    /// @notice Update the distribution interval
    /// @param _newInterval New distribution interval in seconds
    function setDistributionInterval(uint256 _newInterval) external onlyOwner {
        require(_newInterval >= 1 hours, "Interval too short"); // 1h min
        distributionInterval = _newInterval;
        emit DistributionIntervalUpdated(_newInterval);
    }

    /**
     * @notice Requests randomness from Chainlink VRF
     * @param ogBuyer Original buyer's address
     */
    // MAYBE IT WILL BE DELETED BC UNUSED IN PRD
    function requestRandomnessForExpedition(address ogBuyer)
        public
        onlyAllowed
    {
        IChainlinkVRFAntConsumer(vrfConsumerAddress).requestRandomWordsCustom(
            ogBuyer,
            1
        );
    }

    /// @notice Execute an expedition to a specific destination
    /// @param player The address of the player executing the expedition
    /// @param destinationId The ID of the destination
    /// @param colonyId The ID of the colony involved in the expedition
    function executeExpedition(
        address player,
        uint256 destinationId,
        string memory colonyId,
        uint256[] memory antsIds,
        uint256 expeCostPrice,
        string memory uuid
    ) external {
        // Validate destinationId
        require(
            destinationId >= 1 && destinationId <= 10,
            "Invalid destination ID"
        );

        // Ensure player address is valid
        require(player != address(0), "Invalid player address");

        if (destinationId == 1 || destinationId == 2) {
            // Perform zero-cost logic
        } else {
            // Process paid expeditions
            require(
                nectarToken.allowance(msg.sender, address(this)) >=
                    expeCostPrice,
                "Token allowance too low"
            );

            // Transfer tokens from the buyer to the rewardPool contract
            require(
                nectarToken.transferFrom(msg.sender, rewardPool, expeCostPrice),
                "Token transfer failed"
            );

            // Call distributeNectarIfNeeded after transferring to rewardPool
            _distributeNectarIfNeeded();
        }

        // Generate the randomRequest on chainlink and get the requestId
        (uint256 requestId, , , ) = IChainlinkVRFAntConsumer(vrfConsumerAddress)
            .requestRandomWordsCustom(player, 1);

        // Emit event for expedition execution
        emit PendingExpeditionExecution(
            player,
            destinationId,
            colonyId,
            expeCostPrice,
            antsIds,
            uuid,
            requestId
        );
    }

    function rollExpeditionDice(
        address ogBuyer,
        string memory colonyId,
        uint256 randomValue,
        uint256 successPercentScaled
    ) public onlyAllowed {
        // Scale the random value to simulate decimals (0–100.00)
        uint256 mappedValue = randomValue % 10000;
        bool success = mappedValue <= successPercentScaled;
        emit ExpeditionResult(
            ogBuyer,
            colonyId,
            mappedValue,
            successPercentScaled,
            success
        ); // Example: 4237 represents 42.37
    }

    // -------------------- Nectar Trigger --------------------

    /**
     * @notice Distributes Nectar from the generalPool to rewardPool and questPool
     *         to maintain 70% and 20% respectively, leaving 10% in the generalPool.
     *         This function only executes if at least 24 hours have passed since the last distribution.
     */
    function _distributeNectarIfNeeded() internal {
        // Check if at least distributionInterval has passed since the last distribution
        if (block.timestamp >= lastDistributionTime + distributionInterval) {
            // Get current balances
            uint256 rewardBalance = nectarToken.balanceOf(rewardPool);
            uint256 questBalance = nectarToken.balanceOf(questPool);
            uint256 generalBalance = nectarToken.balanceOf(generalPool);

            uint256 totalNectar = rewardBalance + questBalance + generalBalance;

            // If there is no Nectar in total, do nothing
            if (totalNectar == 0) {
                return;
            }

            // Calculate distribution targets
            uint256 targetReward = (totalNectar * rewardPercentage) / 100;
            uint256 targetQuest = (totalNectar * questPercentage) / 100;

            uint256 transferredToRewardPool = 0;
            uint256 transferredToQuestPool = 0;

            // Adjust rewardPool
            if (rewardBalance < targetReward) {
                uint256 toTransfer = targetReward - rewardBalance;

                uint256 amountToTransfer = generalBalance >= toTransfer
                    ? toTransfer
                    : generalBalance;

                require(
                    nectarToken.transferFrom(
                        generalPool,
                        rewardPool,
                        amountToTransfer
                    ),
                    "Transfer to rewardPool failed"
                );
                transferredToRewardPool = toTransfer;
            }

            // Adjust questPool
            if (questBalance < targetQuest) {
                uint256 toTransfer = targetQuest - questBalance;

                // Update the general balance after the possible previous transfer
                uint256 updatedGeneralBalance = nectarToken.balanceOf(
                    generalPool
                );
                require(
                    updatedGeneralBalance >= toTransfer,
                    "Insufficient Nectar in generalPool for questPool"
                );

                // Transfer Nectar from generalPool to questPool
                require(
                    nectarToken.transferFrom(
                        generalPool,
                        questPool,
                        toTransfer
                    ),
                    "Transfer to questPool failed"
                );
                transferredToQuestPool = toTransfer;
            }

            // Update the timestamp of the last distribution
            lastDistributionTime = block.timestamp;

            emit NectarDistributed(
                lastDistributionTime,
                totalNectar,
                transferredToRewardPool,
                transferredToQuestPool
            );
        }
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
     * @notice Allows the owner to update the rewardPool address.
     * @param _newRewardPool Address of the new reward pool.
     */
    function updateRewardPool(address _newRewardPool) external onlyOwner {
        require(_newRewardPool != address(0), "Invalid reward pool address");
        rewardPool = _newRewardPool;
    }

    /**
     * @notice Allows the owner to update the questPool address.
     * @param _newQuestPool Address of the new quest pool.
     */
    function updateQuestPool(address _newQuestPool) external onlyOwner {
        require(_newQuestPool != address(0), "Invalid quest pool address");
        questPool = _newQuestPool;
    }

    /**
     * @notice Allows the owner to update the generalPool address.
     * @param _newGeneralPool Address of the new general pool.
     */
    function updateGeneralPool(address _newGeneralPool) external onlyOwner {
        require(_newGeneralPool != address(0), "Invalid general pool address");
        generalPool = _newGeneralPool;
    }

    /**
     * @notice Allows the owner to update the nodeAddress.
     * @param _newNodeAddress Address of the new node.
     */
    function updateNodeAddress(address _newNodeAddress) external onlyOwner {
        require(_newNodeAddress != address(0), "Invalid node address");
        nodeAddress = _newNodeAddress;
    }
}
