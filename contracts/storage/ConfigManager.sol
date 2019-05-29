pragma solidity ^0.5.8;

import "./IConfigManager.sol";
import "../lib/Ownable.sol";

contract ConfigManager is IConfigManager, Ownable {
    uint private constant TOKEN_DECIMALS = 8;

    uint8 private _arbitrationRewardPercentage = 1;
    address private _bodhiTokenAddress;
    address private _eventFactoryAddress;
    uint private _eventEscrowAmount = 100 * (10 ** TOKEN_DECIMALS); // 100 NBOT
    uint private _arbitrationLength = 48 * 60 * 60; // 48 hours
    uint private _startingConsensusThreshold = 100 * (10 ** TOKEN_DECIMALS); // 100 NBOT
    uint private _thresholdPercentIncrease = 10;
    mapping(address => bool) private _whitelistedContracts;

    // Events
    event BodhiTokenChanged(address indexed oldAddress, address indexed newAddress);
    event EventFactoryChanged(address indexed oldAddress, address indexed newAddress);
    event ContractWhitelisted(address indexed contractAddress);

    constructor() Ownable(msg.sender) public {
        _whitelistedContracts[msg.sender] = true;
    }

    /// @dev Adds a whitelisted contract address.
    /// @param contractAddress The address of the contract to whitelist.
    function addToWhitelist(
        address contractAddress)
        external
        validAddress(contractAddress)
    {
        require(
            _whitelistedContracts[msg.sender] == true,
            "Only whitelisted addresses can add to whitelist");
        
        _whitelistedContracts[contractAddress] = true;
        emit ContractWhitelisted(contractAddress);
    }

    /// @dev Allows the owner to set the address of an BodhiToken contract.
    /// @param contractAddress Address of the BodhiToken contract.
    function setBodhiToken(
        address contractAddress)
        external
        onlyOwner
        validAddress(contractAddress) 
    {
        address oldAddress = _bodhiTokenAddress;
        _bodhiTokenAddress = contractAddress;

        emit BodhiTokenChanged(oldAddress, _bodhiTokenAddress);
    }

    /// @dev Allows the owner to set the address of an EventFactory contract.
    /// @param contractAddress The address of the EventFactory contract.
    function setEventFactory(
        address contractAddress)
        external
        onlyOwner
        validAddress(contractAddress) 
    {
        address oldAddress = _eventFactoryAddress;
        _eventFactoryAddress = contractAddress;
        _whitelistedContracts[contractAddress] = true;

        emit EventFactoryChanged(oldAddress, _eventFactoryAddress);
        emit ContractWhitelisted(contractAddress);
    }

    /// @dev Sets the escrow amount that is needed to create an Event.
    /// @param newAmount The new escrow amount needed to create an Event.
    function setEventEscrowAmount(
        uint newAmount)
        external
        onlyOwner
    {
        _eventEscrowAmount = newAmount;
    }

    /// @dev Sets the arbitration length.
    /// @param newLength The new length in seconds (unix time) of an arbitration period.
    function setArbitrationLength(
        uint newLength)
        external
        onlyOwner
    {   
        require(newLength > 0, "newLength should be > 0");
        _arbitrationLength = newLength;
    }

    /// @dev Sets the arbitration reward percentage.
    /// @param newPercentage New percentage of the arbitration participation reward (e.g. 5)
    function setArbitrationRewardPercentage(
        uint8 newPercentage)
        external
        onlyOwner
    {
        _arbitrationRewardPercentage = newPercentage;
    }

    /// @dev Sets the starting betting threshold.
    /// @param newThreshold The new consensus threshold for the betting round.
    function setStartingConsensusThreshold(
        uint newThreshold)
        external
        onlyOwner
    {
        _startingConsensusThreshold = newThreshold;
    }

    /// @dev Sets the threshold percentage increase.
    /// @param newPercentage The new percentage increase for each new round.
    function setConsensusThresholdPercentIncrease(
        uint newPercentage)
        external
        onlyOwner
    {
        _thresholdPercentIncrease = newPercentage;
    }

    /// @dev Calculates the starting consensus threshold based on the arbitration length.
    /// @param length Arbitration length when creating an event.
    /// @return Starting consensus threshold.
    function calculateThreshold(uint length) external view returns (uint) {
        if (length === _arbitrationLength) { // 48 hours
            return _startingConsensusThreshold;
        } else if (length === (_arbitrationLength / 2)) { // 24 hours
            return _startingConsensusThreshold * 10; // Base * 1000%
        } else if (length === (_arbitrationLength / 4)) { // 12 hours
            return _startingConsensusThreshold * 50; // Base * 5000%
        } else if (length === (_arbitrationLength / 8)) { // 6 hours
            return _startingConsensusThreshold * 100; // Base * 10000%
        } else {
            return 0;
        }
    }

    function bodhiTokenAddress() external view returns (address) {
        return _bodhiTokenAddress;
    }

    function eventFactoryAddress() external view returns (address) {
        return _eventFactoryAddress;
    }

    function eventEscrowAmount() external view returns (uint) {
        return _eventEscrowAmount;
    }

    function defaultArbitrationLength() external view returns (uint) {
        return _arbitrationLength;
    }

    function defaultStartingConsensusThreshold() external view returns (uint) {
        return _startingConsensusThreshold;
    }

    function thresholdPercentIncrease() external view returns (uint) {
        return _thresholdPercentIncrease;
    }

    function isWhitelisted(address contractAddress) external view returns (bool) {
        return _whitelistedContracts[contractAddress];
    }
}
