pragma solidity ^0.5.8;

import "./IConfigManager.sol";
import "../lib/Ownable.sol";

contract ConfigManager is IConfigManager, Ownable {
    uint private constant TOKEN_DECIMALS = 8;

    uint8 private _arbitrationRewardPercentage = 1;
    address private _bodhiTokenAddress;
    address private _eventFactoryAddress;
    uint private _eventEscrowAmount = 100 * (10 ** TOKEN_DECIMALS); // 100 NBOT
    uint[4] private _arbitrationLength = [
        172800, // 48 hours
        86400, // 24 hours
        43200, // 12 hours
        21600 // 6 hours
    ];
    uint[4] private _startingConsensusThreshold = [
        100 * (10 ** TOKEN_DECIMALS),
        1000 * (10 ** TOKEN_DECIMALS),
        5000 * (10 ** TOKEN_DECIMALS),
        10000 * (10 ** TOKEN_DECIMALS)
    ];
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
    /// @param newLength New lengths of arbitration times (unix time seconds).
    function setArbitrationLength(
        uint[4] newLength)
        external
        onlyOwner
    {   
        for (uint8 i = 0; i < 4; i++) {
            require(newLength[i] > 0, "Arbitration time should be > 0");
        }
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
        uint[4] newThreshold)
        external
        onlyOwner
    {
        for (uint8 i = 0; i < 4; i++) {
            require(newThreshold[i] > 0, "Consensus threshold should be > 0");
        }
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

    function bodhiTokenAddress() external view returns (address) {
        return _bodhiTokenAddress;
    }

    function eventFactoryAddress() external view returns (address) {
        return _eventFactoryAddress;
    }

    function eventEscrowAmount() external view returns (uint) {
        return _eventEscrowAmount;
    }

    function arbitrationLength() external view returns (uint[4]) {
        return _arbitrationLength;
    }

    function startingConsensusThreshold() external view returns (uint[4]) {
        return _startingConsensusThreshold;
    }

    function thresholdPercentIncrease() external view returns (uint) {
        return _thresholdPercentIncrease;
    }

    function isWhitelisted(address contractAddress) external view returns (bool) {
        return _whitelistedContracts[contractAddress];
    }
}
