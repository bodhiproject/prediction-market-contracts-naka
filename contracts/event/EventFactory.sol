pragma solidity ^0.5.8;

import "./MultipleResultsEvent.sol";
import "../storage/IConfigManager.sol";
import "../token/INRC223.sol";
import "../token/NRC223Receiver.sol";

/// @title EventFactory allows the creation of individual prediction events.
contract EventFactory is NRC223Receiver {
    using ByteUtils for bytes32;

    struct EventEscrow {
        bool didWithdraw;
        address depositer;
        uint amount;
    }

    uint16 private constant VERSION = 0;

    address private _configManager;
    address private _bodhiTokenAddress;
    mapping(address => EventEscrow) private _escrows;
    mapping(bytes32 => MultipleResultsEvent) private _events;

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
        require(configManager != address(0), "configManager address is invalid");

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
        require(msg.sender == _bodhiTokenAddress, "Only NBOT is accepted");

        bytes memory createMultipleResultsEventFunc = hex"2b2601bf";
        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length);

        bytes32 encodedFunc = keccak256(abi.encodePacked(funcHash));
        if (encodedFunc == keccak256(abi.encodePacked(createMultipleResultsEventFunc))) {
            (string memory eventName, bytes32[10] eventResults, 
                uint betStartTime, uint betEndTime, uint resultSetStartTime,
                uint resultSetEndTime, address centralizedOracle) = 
                abi.decode(params, (string, bytes32[10], uint256, uint256, 
                uint256, uint256, address));
            createMultipleResultsEvent(from, value, eventName, eventResults, 
                betStartTime, betEndTime, resultSetStartTime, resultSetEndTime, 
                centralizedOracle);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    /// @dev Withdraws escrow for the sender.
    ///      Event contracts (which are whitelisted) will call this.
    function withdrawEscrow() external returns (uint) {
        require(
            IConfigManager(_configManager).isWhitelisted(msg.sender),
            "Sender is not whitelisted");
        require(!_events[msg.sender].didWithdraw, "Already withdrew escrow");

        uint amount = _events[msg.sender].amount;
        INRC223(_bodhiTokenAddress).transfer(msg.sender, amount);

        return amount;
    }

    function didWithdraw() external view returns (bool) {
        return _events[msg.sender].didWithdraw;
    }

    function getMultipleResultsEventHash(
        string name, 
        bytes32[11] resultNames, 
        uint8 numOfResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime)
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(name, resultNames, numOfResults, betStartTime, 
            betEndTime, resultSetStartTime, resultSetEndTime));
    }

    function createMultipleResultsEvent(
        address creator,
        uint escrowDeposited,
        string eventName,
        bytes32[10] eventResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime,
        address centralizedOracle)
        private
        returns (MultipleResultsEvent)
    {   
        // Validate escrow amount
        uint escrowAmount = IConfigManager(_configManager).eventEscrowAmount();
        require(escrowDeposited >= escrowAmount, "Escrow deposit is not enough");

        // Add Invalid result to eventResults
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

        // Event should not exist yet
        bytes32 eventHash = getMultipleResultsEventHash(
            name, resultNames, numOfResults, betStartTime, betEndTime, 
            resultSetStartTime, resultSetEndTime);
        require(address(_events[eventHash]) == 0, "Event already exists");

        // Create event
        MultipleResultsEvent mrEvent = new MultipleResultsEvent(
            creator, eventName, results, numOfResults, betStartTime,
            betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle, 
            _configManager);
        address eventAddress = address(mrEvent);

        // Store escrow entry and event
        _events[eventHash] = mrEvent;
        _escrows[eventAddress] = EventEscrow(false, creator, escrowDeposited);

        // Add to whitelist
        IConfigManager(_configManager).addToWhitelist(eventAddress);

        // Emit events
        emit MultipleResultsEventCreated(VERSION, eventAddress, creator, 
            eventName, results, numOfResults);

        return mrEvent;
    }
}
