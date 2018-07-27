pragma solidity ^0.4.24;

import "./Oracle.sol";

contract CentralizedOracle is Oracle {
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
    /// @param _consensusThreshold The BOT amount that needs to be paid by the Oracle for their result to be valid.
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

    /// @notice Fallback function that rejects any amount sent to the contract.
    function() external payable {
        revert();
    }

    /// @dev Validate a bet. Must be called from TopicEvent.
    /// @param _bettor The entity who is placing the bet.
    /// @param _resultIndex The index of result to bet on.
    /// @param _amount The amount of the bet.
    function validateBet(address _bettor, uint8 _resultIndex, uint256 _amount)
        external
        isAuthorized(msg.sender)
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

    /// @dev Records the bet. Must be called from TopicEvent.
    /// @param _bettor The entity who is placing the bet.
    /// @param _resultIndex The index of result to bet on.
    /// @param _amount The amount of the bet.
    function recordBet(address _bettor, uint8 _resultIndex, uint256 _amount) external isAuthorized(msg.sender) {
        balances[_resultIndex].totalBets = balances[_resultIndex].totalBets.add(_amount);
        balances[_resultIndex].bets[_bettor] = balances[_resultIndex].bets[_bettor].add(_amount);

        emit OracleResultVoted(version, address(this), _bettor, _resultIndex, _amount, QTUM);
    }

    /// @notice CentralizedOracle should call this to set the result. Requires the Oracle to approve() BOT in the amount 
    ///         of the consensus threshold.
    /// @param _resultIndex The index of the result to set.
    function setResult(uint8 _resultIndex) external validResultIndex(_resultIndex) isNotFinished() {
        require(block.timestamp >= resultSettingStartTime);
        if (block.timestamp < resultSettingEndTime) {
            require(msg.sender == oracle);
        }

        finished = true;
        resultIndex = _resultIndex;

        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(consensusThreshold);
        balances[_resultIndex].votes[msg.sender] = balances[_resultIndex].votes[msg.sender]
            .add(consensusThreshold);

        ITopicEvent(eventAddress).centralizedOracleSetResult(msg.sender, _resultIndex, consensusThreshold);
        emit OracleResultVoted(version, address(this), msg.sender, _resultIndex, consensusThreshold, BOT);
        emit OracleResultSet(version, address(this), _resultIndex);
    }
}
