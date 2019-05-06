pragma solidity ^0.5.8;

import "./MultipleResultsEvent.sol";
import "../storage/IConfigManager.sol";

/// @title Event Factory allows the creation of individual prediction events.
contract EventFactory {
    using ByteUtils for bytes32;

    uint16 private constant VERSION = 0;

    address private _configManager;
    mapping(bytes32 => MultipleResultsEvent) private events;

    // Events
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
    }
    
    function createMultipleResultsEvent(
        string eventName,
        bytes32[10] eventResults,
        uint256 betStartTime,
        uint256 betEndTime,
        uint256 resultSetStartTime,
        uint256 resultSetEndTime,
        address centralizedOracle)
        external
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
        require(address(events[eventHash]) == 0);

        // TODO: NRC223.transfer() -> IronBank -> EventFactory.create
        // IAddressManager(addressManager).transferEscrow(msg.sender);

        MultipleResultsEvent mrEvent = new MultipleResultsEvent(
            msg.sender, eventName, results, numOfResults, betStartTime,
            betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle, 
            _configManager);
        events[eventHash] = mrEvent;
        IConfigManager(_configManager).addWhitelistContract(address(mrEvent));

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
