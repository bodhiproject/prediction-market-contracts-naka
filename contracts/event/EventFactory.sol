pragma solidity ^0.5.8;

import "./StandardEvent.sol";
import "../storage/IConfigManager.sol";

/// @title Event Factory allows the creation of individual prediction events.
contract EventFactory {
    using ByteUtils for bytes32;

    uint16 private constant _version = 0;
    address private _configManager;
    mapping(bytes32 => StandardEvent) public events;

    // Events
    event StandardEventCreated(
        uint16 indexed version,
        address indexed eventAddress, 
        address indexed creatorAddress,
        bytes32[10] name, 
        bytes32[11] resultNames,
        uint8 numOfResults,
        uint256 escrowAmount
    );

    constructor(address configManager) public {
        require(configManager != address(0));
        _configManager = configManager;
    }
    
    function createStandardEvent(
        address centralizedOracle, 
        bytes32[10] name, 
        bytes32[10] resultNames, 
        uint256 bettingStartTime,
        uint256 bettingEndTime,
        uint256 resultSettingStartTime,
        uint256 resultSettingEndTime)
        public
        returns (StandardEvent sEvent) 
    {
        require(!name[0].isEmpty());
        require(!resultNames[0].isEmpty());
        require(!resultNames[1].isEmpty());
        
        bytes32[11] memory resultNames;
        uint8 numOfResults;

        resultNames[0] = "Invalid";
        numOfResults++;

        for (uint i = 0; i < _resultNames.length; i++) {
            if (!_resultNames[i].isEmpty()) {
                resultNames[i + 1] = _resultNames[i];
                numOfResults++;
            } else {
                break;
            }
        }

        bytes32 eventHash = getStandardEventHash(
            _name, resultNames, numOfResults, _bettingStartTime, _bettingEndTime, _resultSettingStartTime,
            _resultSettingEndTime);
        // Event should not exist yet
        require(address(events[eventHash]) == 0);

        // TODO: create EscrowBank contract to handle escrows with ERC223
        // IAddressManager(addressManager).transferEscrow(msg.sender);

        StandardEvent standardEvent = new StandardEvent(version, msg.sender, _oracle, _name, resultNames, numOfResults, 
            _bettingStartTime, _bettingEndTime, _resultSettingStartTime, _resultSettingEndTime, addressManager);
        events[eventHash] = standardEvent;

        IAddressManager(addressManager).addWhitelistContract(address(standardEvent));

        emit StandardEventCreated(
            version, address(standardEvent), msg.sender, _name, resultNames, numOfResults,
            IAddressManager(addressManager).eventEscrowAmount());

        return standardEvent;
    }

    function getStandardEventHash(
        bytes32[10] _name, 
        bytes32[11] _resultNames, 
        uint8 _numOfResults,
        uint256 _bettingStartTime,
        uint256 _bettingEndTime,
        uint256 _resultSettingStartTime,
        uint256 _resultSettingEndTime)
        internal
        pure    
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(_name, _resultNames, _numOfResults, _bettingStartTime, _bettingEndTime, 
            _resultSettingStartTime, _resultSettingEndTime)
        );
    }
}
