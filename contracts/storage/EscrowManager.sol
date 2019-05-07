pragma solidity ^0.5.8;

import "./IConfigManager.sol";
import "../lib/Ownable.sol";

contract EscrowManager is IEscrowManager, Ownable {
    struct EventEscrow {
        address depositer;
        uint256 amount;
    }

    mapping(address => EventEscrow) private _eventEscrows;

    // Events
    event BodhiTokenChanged(address indexed oldAddress, address indexed newAddress);
    event EventFactoryChanged(address indexed oldAddress, address indexed newAddress);
    event ContractWhitelisted(address indexed contractAddress);

    // Modifiers
    modifier isWhitelisted(address _contractAddress) {
        require(whitelistedContracts[_contractAddress] == true);
        _;
    }

    constructor() Ownable(msg.sender) public {
    }

    /// @dev Adds a whitelisted contract address. Only allowed to be called from previously whitelisted addresses.
    /// @param contractAddress The address of the contract to whitelist.
    function addWhitelistContract(
        address contractAddress)
        external
        onlyOwner
        isWhitelisted(msg.sender)
        validAddress(contractAddress)
    {
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
        require(newLength > 0);
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
}
