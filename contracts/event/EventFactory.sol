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

    uint16 private constant VERSION = 3;

    address private _configManager;
    address private _bodhiTokenAddress;
    mapping(address => EventEscrow) private _escrows;

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

        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length - 4);
        bytes32 encodedFunc = keccak256(abi.encodePacked(funcHash));
        if (encodedFunc == keccak256(abi.encodePacked(hex"2b2601bf"))) {
            handleCreateMultipleResultsEvent(from, value, params);
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

        // Transfer to escrow depositer
        INRC223(_bodhiTokenAddress).transfer(_escrows[msg.sender].depositer, amount);

        return amount;
    }

    /// @dev Checks if the escrow has been withdrawn for an event.
    /// @return If escrow has been withdrawn for an event.
    function didWithdraw() external view returns (bool) {
        return _escrows[msg.sender].didWithdraw;
    }

    function handleCreateMultipleResultsEvent(
        address from,
        uint value,
        bytes memory params)
        private
        returns (MultipleResultsEvent)
    {
        (string memory eventName, bytes32[3] memory eventResults, 
            uint betStartTime, uint betEndTime, uint resultSetStartTime,
            uint resultSetEndTime, address centralizedOracle,
            uint arbitrationOptionIndex, uint arbitrationRewardPercentage) =
            abi.decode(params, (string, bytes32[3], uint, uint, uint, uint, 
            address, uint, uint));
        return createMultipleResultsEvent(from, value, eventName, eventResults, 
            betStartTime, betEndTime, resultSetStartTime, resultSetEndTime, 
            centralizedOracle, arbitrationOptionIndex, arbitrationRewardPercentage);
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
    /// @param arbitrationOptionIndex Index of the selected arbitration option.
    /// @param arbitrationRewardPercentage Percentage of loser's bets going to winning arbitrators.
    /// @return New MultipleResultsEvent.
    function createMultipleResultsEvent(
        address creator,
        uint escrowDeposited,
        string memory eventName,
        bytes32[3] memory eventResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime,
        address centralizedOracle,
        uint8 arbitrationOptionIndex,
        uint arbitrationRewardPercentage)
        private
        returns (MultipleResultsEvent)
    {   
        // Validate escrow amount
        uint escrowAmount = IConfigManager(_configManager).eventEscrowAmount();
        require(escrowDeposited >= escrowAmount, "Escrow deposit is not enough");

        // Add Invalid result to eventResults
        bytes32[4] memory results;
        uint8 numOfResults;
        results[0] = "Invalid";
        numOfResults++;

        // Copy results to new array with Invalid option
        for (uint i = 0; i < eventResults.length; i++) {
            if (!eventResults[i].isEmpty()) {
                results[i + 1] = eventResults[i];
                numOfResults++;
            } else {
                break;
            }
        }

        // Create event
        MultipleResultsEvent mrEvent = new MultipleResultsEvent(
            creator, eventName, results, numOfResults, betStartTime,
            betEndTime, resultSetStartTime, resultSetEndTime, centralizedOracle, 
            arbitrationOptionIndex, arbitrationRewardPercentage, _configManager);

        // Store escrow info
        _escrows[address(mrEvent)].depositer = creator;
        _escrows[address(mrEvent)].amount = escrowDeposited;

        // Add to whitelist
        IConfigManager(_configManager).addToWhitelist(address(mrEvent));

        // Emit events
        emit MultipleResultsEventCreated(address(mrEvent), creator);

        return mrEvent;
    }
}
