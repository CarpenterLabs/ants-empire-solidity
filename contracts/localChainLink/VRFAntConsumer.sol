// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

// Enum for randomness types
enum RandomnessKind {
    MINT,
    EXPEDITION,
    STANDARD
}

interface VRFCoordinatorSC {
    function fulfillRandomWords(uint256 _requestId, address _consumer) external;
}

contract VRFAntConsumer is VRFConsumerBaseV2Plus {
    address vrfCoordinator;
    struct randomReqType {
        uint32 nWords;
    }
    // Mapping of strings to their corresponding nWords (or other data)
    mapping(string => randomReqType) public randomnessTypes;

    mapping(address => bool) public allowedContracts;

    // Chainlink VRF variables
    uint16 public requestConfirmations = 2;
    uint32 public callbackGasLimit = 500000;
    uint32 public numWords = 2;

    uint256 public subscriptionId;
    bytes32 public keyHash;

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
        address requester;
        string kind;
    }

    mapping(uint256 => RequestStatus) public requests;
    uint256[] public requestIds;

    event RandomnessRequested(
        uint256 indexed requestId,
        uint32 numWords,
        address requester,
        string kind
    );
    event RandomnessFulfilled(uint256 indexed requestId, uint256[] randomWords);

    // Modifier to restrict access
    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    constructor(
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        vrfCoordinator = _vrfCoordinator;

        randomnessTypes["MINT"] = randomReqType(1); // MINT requires 1 random words
        randomnessTypes["EXPEDITION"] = randomReqType(1); // EXPEDITION requires 1 random word
        randomnessTypes["STANDARD"] = randomReqType(1); // STANDAR requires 1 random word
    }

    // Add more allowed contracts dynamically if needed
    function addAllowedContract(address _contract) external onlyOwner {
        allowedContracts[_contract] = true;
    }

    // Function to check if a string is part of the randomness mapping
    function isValidRandomnessKind(string memory kind)
        internal
        view
        returns (bool)
    {
        // Check if the struct's nWords is non-zero (i.e., initialized)
        return randomnessTypes[kind].nWords != 0;
    }

    function addRequestIdStatus(
        uint256 requestId,
        address requester,
        string memory kind
    ) internal {
        requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            requester: requester,
            kind: kind
        });
        requestIds.push(requestId);
    }

    function requestRandomWordsByKind(address requester, string memory kind)
        external
        onlyAllowed
        returns (
            uint256 requestId,
            uint32 words,
            address ogRequester,
            string memory kindOf
        )
    {
        require(isValidRandomnessKind(kind), "Invalid randomness kind");

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: randomnessTypes[kind].nWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );

        addRequestIdStatus(requestId, requester, kind);

        emit RandomnessRequested(
            requestId,
            randomnessTypes[kind].nWords,
            requester,
            kind
        );
        return (requestId, randomnessTypes[kind].nWords, requester, kind);
    }

    function requestRandomWordsCustom(address requester, uint32 numOfWords)
        external
        onlyAllowed
        returns (
            uint256 requestId,
            uint32 words,
            address ogRequester,
            string memory kindOf
        )
    {
        require(numOfWords > 0, "Invalid randomness number");

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numOfWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );

        addRequestIdStatus(requestId, requester, "CUSTOM");

        emit RandomnessRequested(requestId, numOfWords, requester, "CUSTOM");
        return (requestId, numOfWords, requester, "CUSTOM");
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        require(requests[requestId].exists, "Request not found");
        requests[requestId].fulfilled = true;
        requests[requestId].randomWords = randomWords;
        emit RandomnessFulfilled(requestId, randomWords);
    }

    function getRequestStatus(uint256 requestId)
        external
        view
        returns (
            bool fulfilled,
            uint256[] memory randomWords,
            string memory kind
        )
    {
        RequestStatus memory status = requests[requestId];
        require(status.exists, "Request not found");
        return (status.fulfilled, status.randomWords, status.kind);
    }

    function callFulfillRandomWords(uint256[] memory chainLinkReqIds) public onlyAllowed{
        for (uint256 i = 0; i < chainLinkReqIds.length; i++) {
            VRFCoordinatorSC(vrfCoordinator).fulfillRandomWords(
                chainLinkReqIds[i],
                address(this)
            );
        }
    }
}
