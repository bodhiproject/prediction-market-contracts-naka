pragma solidity ^0.4.24;

import "../BaseContract.sol";
import "../event/ITopicEvent.sol";
import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";

contract Oracle is BaseContract, Ownable {
    using SafeMath for uint256;

    bytes32 internal constant QTUM = "QTUM";
    bytes32 internal constant BOT = "BOT";

    bool public finished;
    address public eventAddress;
    uint256 public consensusThreshold;

    // Events
    event OracleResultVoted(
        uint16 indexed _version, 
        address indexed _oracleAddress, 
        address indexed _participant, 
        uint8 _resultIndex, 
        uint256 _votedAmount,
        bytes32 _token
    );
    event OracleResultSet(
        uint16 indexed _version, 
        address indexed _oracleAddress, 
        uint8 _resultIndex
    );

    // Modifiers
    modifier isNotFinished() {
        require(!finished);
        _;
    }

    modifier isEventCaller(address _callerAddress) {
        require(_callerAddress == eventAddress);
        _;
    }
}
