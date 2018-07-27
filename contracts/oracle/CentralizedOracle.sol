pragma solidity ^0.4.24;

import "./ICentralizedOracle.sol";
import "./Oracle.sol";

contract CentralizedOracle is ICentralizedOracle, Oracle {
    address public oracle;
    uint256 public bettingStartTime;
    uint256 public bettingEndTime;
    uint256 public resultSettingStartTime;
    uint256 public resultSettingEndTime;

    /// @notice Creates new CentralizedOracle contract.
    /// @param _version The contract version.
    /// @param _owner The address of the owner.
    /// @param _eventAddress The address of the Event.
    /// @param _numOfResults The number of result options.
    /// @param _oracle The address of the CentralizedOracle that will ultimately decide the result.
    /// @param _bettingStartTime The unix time when betting will start.
    /// @param _bettingEndTime The unix time when betting will end.
    /// @param _resultSettingStartTime The unix time when the CentralizedOracle can set the result.
    /// @param _resultSettingEndTime The unix time when anyone can set the result.
    /// @param _consensusThreshold The amount that needs to be paid by the Oracle for their result to be valid.
    constructor(
        uint16 _version,
        address _owner,
        address _eventAddress,
        uint8 _numOfResults,
        address _oracle,
        uint256 _bettingStartTime,
        uint256 _bettingEndTime,
        uint256 _resultSettingStartTime,
        uint256 _resultSettingEndTime,
        uint256 _consensusThreshold)
        Ownable(_owner)
        public
        validAddress(_oracle)
        validAddress(_eventAddress)
    {
        require(_numOfResults > 0);
        require(_bettingEndTime > _bettingStartTime);
        require(_resultSettingStartTime >= _bettingEndTime);
        require(_resultSettingEndTime > _resultSettingStartTime);
        require(_consensusThreshold > 0);

        version = _version;
        eventAddress = _eventAddress;
        numOfResults = _numOfResults;
        oracle = _oracle;
        bettingStartTime = _bettingStartTime;
        bettingEndTime = _bettingEndTime;
        resultSettingStartTime = _resultSettingStartTime;
        resultSettingEndTime = _resultSettingEndTime;
        consensusThreshold = _consensusThreshold;
    }

    /// @dev Validate a bet. Must be called from Event.
    /// @param _bettor The entity who is placing the bet.
    /// @param _resultIndex The index of result to bet on.
    /// @param _amount The amount of the bet.
    /// @return Is validated.
    function validateBet(address _bettor, uint8 _resultIndex, uint256 _amount)
        external
        isEventCaller(msg.sender)
        validAddress(_bettor)
        validResultIndex(_resultIndex)
        isNotFinished()
        returns (bool isValid)
    {
        require(block.timestamp >= bettingStartTime);
        require(block.timestamp < bettingEndTime);
        require(_amount > 0);
        return true;
    }

    /// @dev Records the bet. Must be called from Event.
    /// @param _bettor The entity who is placing the bet.
    /// @param _resultIndex The index of result to bet on.
    /// @param _amount The amount of the bet.
    function recordBet(address _bettor, uint8 _resultIndex, uint256 _amount) external isEventCaller(msg.sender) {
        balances[_resultIndex].totalBets = balances[_resultIndex].totalBets.add(_amount);
        balances[_resultIndex].bets[_bettor] = balances[_resultIndex].bets[_bettor].add(_amount);

        emit OracleResultVoted(version, address(this), _bettor, _resultIndex, _amount, ETH);
    }

    /// @dev Validate a set result. Must be called from Event.
    /// @param _resultSetter Entity who is setting the result.
    /// @param _resultIndex Index of result to set.
    /// @param _amount Amount of tokens used to set the result.
    /// @return Is validated.
    function validateSetResult(address _resultSetter, uint8 _resultIndex, uint256 _amount)
        external
        isEventCaller(msg.sender)
        validAddress(_resultSetter)
        validResultIndex(_resultIndex)
        isNotFinished()
        returns (bool isValid)
    {
        require(block.timestamp >= resultSettingStartTime);
        if (block.timestamp < resultSettingEndTime) {
            require(_resultSetter == oracle);
        }
        require (_amount >= consensusThreshold);
        return true;
    }

    /// @dev Records the result. Must be called from Event.
    /// @param _resultSetter Entity who is setting the result.
    /// @param _resultIndex The index of the result to set.
    /// @param _amount Amount of tokens used to set the result.
    function recordSetResult(address _resultSetter, uint8 _resultIndex, uint256 _amount)
        external
        isEventCaller(msg.sender)
    {
        finished = true;
        resultIndex = _resultIndex;
        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(_amount);
        balances[_resultIndex].votes[_resultSetter] = balances[_resultIndex].votes[_resultSetter].add(_amount);

        emit OracleResultVoted(version, address(this), _resultSetter, _resultIndex, _amount, BOE);
        emit OracleResultSet(version, address(this), _resultIndex);
    }
}
