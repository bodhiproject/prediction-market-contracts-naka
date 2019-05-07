pragma solidity ^0.5.8;

import "./IConfigManager.sol";
import "../lib/Ownable.sol";

contract ConfigManager is IConfigManager, Ownable {
    uint256 private constant TOKEN_DECIMALS = 8;

    uint8 private _arbitrationRewardPercentage = 1;
    address private _bodhiTokenAddress;
    address private _eventFactoryAddress;
    uint256 private _eventEscrowAmount = 100 * (10 ** TOKEN_DECIMALS);
    uint256 private _arbitrationLength = 24 * 60 * 60; // 1 day
    uint256 private _startingOracleThreshold = 100 * (10 ** TOKEN_DECIMALS);
    uint256 private _thresholdPercentIncrease = 10;
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
        uint256 newAmount)
        external
        onlyOwner
    {
        _eventEscrowAmount = newAmount;
    }

    /// @dev Sets the arbitration length.
    /// @param newLength The new length in seconds (unix time) of an arbitration period.
    function setArbitrationLength(
        uint256 newLength)
        external
        onlyOwner
    {   
        require(newLength > 0, "newLength should be > 0");
        _arbitrationLength = newLength;
    }

    /// @dev Sets the arbitration reward percentage.
    /// @param newPercentage New percentage of the arbitration participation reward (e.g. 5)
    function setArbitrationRewardPercentage(
        uint256 newPercentage)
        external
        onlyOwner
    {
        _arbitrationRewardPercentage = newPercentage;
    }

    /// @dev Sets the starting betting threshold.
    /// @param newThreshold The new consensus threshold for the betting round.
    function setStartingOracleThreshold(
        uint256 newThreshold)
        external
        onlyOwner
    {
        _startingOracleThreshold = newThreshold;
    }

    /// @dev Sets the threshold percentage increase.
    /// @param newPercentage The new percentage increase for each new round.
    function setConsensusThresholdPercentIncrease(
        uint256 newPercentage)
        external
        onlyOwner
    {
        _thresholdPercentIncrease = newPercentage;
    }

    function bodhiTokenAddress() external view returns (address) {
        return _bodhiTokenAddress;
    }

    function eventFactoryAddress() external view returns (address) {
        return _eventFactoryAddress;
    }

    function eventEscrowAmount() external view returns (uint256) {
        return _eventEscrowAmount;
    }

    function arbitrationLength() external view returns (uint256) {
        return _arbitrationLength;
    }

    function arbitrationRewardPercentage() external view returns (uint8) {
        return _arbitrationRewardPercentage;
    }

    function startingOracleThreshold() external view returns (uint256) {
        return _startingOracleThreshold;
    }

    function thresholdPercentIncrease() external view returns (uint256) {
        return _thresholdPercentIncrease;
    }

    function isWhitelisted(address contractAddress) external view returns (bool) {
        return _whitelistedContracts[contractAddress];
    }
}
