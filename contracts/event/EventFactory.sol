pragma solidity ^0.5.8;

import "./MultipleResultsEvent.sol";
import "../storage/IConfigManager.sol";
import "../token/INRC223.sol";
import "../token/NRC223Receiver.sol";

/// @title EventFactory allows the creation of individual prediction events.
contract EventFactory is NRC223Receiver {
    using ByteUtils for bytes;
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
        address indexed eventAddress,
        address indexed ownerAddress
    );

    /// @dev Creates a new EventFactory.
    /// @param configManager ConfigManager address.
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
        bytes calldata data)
        external
    {
        require(msg.sender == _bodhiTokenAddress, "Only NBOT is accepted");
        require(data.length >= 4, "Data is not long enough.");

        bytes memory createMultipleResultsEventFunc = hex"2b2601bf";
        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length);

        bytes32 encodedFunc = keccak256(abi.encodePacked(funcHash));
        if (encodedFunc == keccak256(abi.encodePacked(createMultipleResultsEventFunc))) {
            (bytes32[10] memory eventName, bytes32[10] memory eventResults, 
                uint betStartTime, uint betEndTime, uint resultSetStartTime,
                uint resultSetEndTime, address centralizedOracle) = 
                abi.decode(params, (bytes32[10], bytes32[10], uint256, uint256, 
                uint256, uint256, address));
            createMultipleResultsEvent(from, value, eventName, eventResults, 
                betStartTime, betEndTime, resultSetStartTime, resultSetEndTime, 
                centralizedOracle);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    /// @dev Withdraws escrow for the sender. Event contracts (which are whitelisted) will call this.
    /// @return Amount of escrow withdrawn.
    function withdrawEscrow() external returns (uint) {
        require(
            IConfigManager(_configManager).isWhitelisted(msg.sender),
            "Sender is not whitelisted");
        require(!_escrows[msg.sender].didWithdraw, "Already withdrew escrow");

        _escrows[msg.sender].didWithdraw = true;
        uint amount = _escrows[msg.sender].amount;
        INRC223(_bodhiTokenAddress).transfer(msg.sender, amount);

        return amount;
    }

    /// @dev Checks if the escrow has been withdrawn for an event.
    /// @return If escrow has been withdrawn for an event.
    function didWithdraw() external view returns (bool) {
        return _escrows[msg.sender].didWithdraw;
    }

    /// @dev Creates a new MultipleResultsEvent. Only tokenFallback can call this.
    /// @param creator Address of the creator.
    /// @param escrowDeposited Amount of escrow deposited to create the event.
    /// @param eventName Question or statement prediction.
    /// @param eventResults Possible results.
    /// @param betStartTime Unix time when betting will start.
    /// @param betEndTime Unix time when betting will end.
    /// @param resultSetStartTime Unix time when the CentralizedOracle can set the result.
    /// @param resultSetEndTime Unix time when anyone can set the result.
    /// @param centralizedOracle Address of the user that will decide the result.
    /// @return New MultipleResultsEvent.
    function createMultipleResultsEvent(
        address creator,
        uint escrowDeposited,
        bytes32[10] memory eventName,
        bytes32[10] memory eventResults,
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
            eventName, results, numOfResults, betStartTime, betEndTime, 
            resultSetStartTime, resultSetEndTime);
        require(address(_events[eventHash]) == address(0), "Event already exists");

        // Create event
        MultipleResultsEvent mrEvent = new MultipleResultsEvent(
            creator, eventName, results, numOfResults, betStartTime,
            betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle, 
            _configManager);

        // Store escrow entry and event
        _events[eventHash] = mrEvent;
        _escrows[address(mrEvent)].depositer = creator;
        _escrows[address(mrEvent)].amount = escrowDeposited;

        // Add to whitelist
        IConfigManager(_configManager).addToWhitelist(address(mrEvent));

        // Emit events
        emit MultipleResultsEventCreated(address(mrEvent), creator);

        return mrEvent;
    }

    /// @dev Gets the hash based of the event parameters.
    /// @param eventName Question or statement prediction.
    /// @param eventResults Possible results.
    /// @param numOfResults Number of results.
    /// @param betStartTime Unix time when betting will start.
    /// @param betEndTime Unix time when betting will end.
    /// @param resultSetStartTime Unix time when the CentralizedOracle can set the result.
    /// @param resultSetEndTime Unix time when anyone can set the result.
    /// @return Hash of the event params.
    function getMultipleResultsEventHash(
        bytes32[10] memory eventName,
        bytes32[11] memory eventResults,
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
            abi.encodePacked(eventName, eventResults, numOfResults, betStartTime, 
            betEndTime, resultSetStartTime, resultSetEndTime));
    }
}
