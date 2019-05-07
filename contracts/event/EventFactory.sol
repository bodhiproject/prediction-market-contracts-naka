pragma solidity ^0.5.8;

import "./MultipleResultsEvent.sol";
import "../storage/IConfigManager.sol";
import "../token/NRC223Receiver.sol";

/// @title Event Factory allows the creation of individual prediction events.
contract EventFactory is NRC223Receiver {
    using ByteUtils for bytes32;

    struct EventEscrow {
        address depositer;
        uint256 amount;
    }

    uint16 private constant VERSION = 0;

    address private _configManager;
    address private _bodhiTokenAddress;
    mapping(address => EventEscrow) private _escrows;
    mapping(bytes32 => MultipleResultsEvent) private _events;

    // Events
    event EscrowDeposited(
        address indexed newAddress
    );
    event MultipleResultsEventCreated(
        uint16 indexed version,
        address indexed eventAddress,
        address indexed ownerAddress,
        string name,
        bytes32[11] resultNames,
        uint8 numOfResults
    );

    constructor(address configManager) public {
        require(configManager != address(0));

        _configManager = configManager;
        _bodhiTokenAddress = IConfigManager(_configManager).bodhiTokenAddress();
        assert(_bodhiTokenAddress != address(0));
    }
    
    /// @dev Handle incoming token transfers needed for creating events.
    /// @param from Token sender address.
    /// @param value Amount of tokens.
    /// @param data The message data. First 4 bytes is function hash & rest is function params.
    function tokenFallback(
        address from,
        uint value,
        bytes data)
        external
    {
        // Ensure only NBOT can call this method
        require(msg.sender == _bodhiTokenAddress);

        bytes memory createMultipleResultsEventFunc = hex"8d4c17e1";
        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length);

        bytes32 encodedFunc = keccak256(abi.encodePacked(funcHash));
        if (encodedFunc == keccak256(abi.encodePacked(createMultipleResultsEventFunc))) {
            (string memory eventName, bytes32[10] eventResults, 
                uint256 betStartTime, uint256 betEndTime, 
                uint256 resultSetStartTime, uint256 resultSetEndTime, 
                address centralizedOracle) = abi.decode(params, (string, 
                bytes32[10], uint256, uint256, uint256, uint256, address));
            createMultipleResultsEvent(eventName, eventResults, betStartTime,
                betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    function createMultipleResultsEvent(
        string eventName,
        bytes32[10] eventResults,
        uint256 betStartTime,
        uint256 betEndTime,
        uint256 resultSetStartTime,
        uint256 resultSetEndTime,
        address centralizedOracle)
        private
        returns (MultipleResultsEvent)
    {   
        bytes32[11] memory results;
        uint8 numOfResults;

        results[0] = "Invalid";
        numOfResults++;

        for (uint i = 0; i < eventResults.length; i++) {
            if (!eventResults[i].isEmpty()) {
                results[i + 1] = eventResults[i];
                numOfResults++;
            } else {
                break;
            }
        }

        bytes32 eventHash = getMultipleResultsEventHash(
            name, resultNames, numOfResults, betStartTime, betEndTime, 
            resultSetStartTime, resultSetEndTime);
        // Event should not exist yet
        require(address(_events[eventHash]) == 0);

        // TODO: NRC223.transfer() -> IronBank -> EventFactory.create
        // IAddressManager(addressManager).transferEscrow(msg.sender);

        MultipleResultsEvent mrEvent = new MultipleResultsEvent(
            msg.sender, eventName, results, numOfResults, betStartTime,
            betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle, 
            _configManager);
        _events[eventHash] = mrEvent;

        emit MultipleResultsEventCreated(VERSION, address(mrEvent), msg.sender, 
            eventName, results);

        return mrEvent;
    }

    function getMultipleResultsEventHash(
        string name, 
        bytes32[11] resultNames, 
        uint8 numOfResults,
        uint256 betStartTime,
        uint256 betEndTime,
        uint256 resultSetStartTime,
        uint256 resultSetEndTime)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(name, resultNames, numOfResults, betStartTime, 
            betEndTime, resultSetStartTime, resultSetEndTime));
    }
}
