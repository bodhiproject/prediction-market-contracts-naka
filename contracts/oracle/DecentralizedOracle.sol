pragma solidity ^0.4.24;

import "./IDecentralizedOracle.sol";
import "./Oracle.sol";

contract DecentralizedOracle is IDecentralizedOracle, Oracle {
    uint8 public lastResultIndex;
    uint256 public arbitrationEndTime;

    /// @notice Creates new DecentralizedOracle contract.
    /// @param _version The contract version.
    /// @param _owner The address of the owner.
    /// @param _eventAddress The address of the Event.
    /// @param _numOfResults The number of result options.
    /// @param _lastResultIndex The last result index set by the DecentralizedOracle.
    /// @param _arbitrationEndTime The unix time when the voting period ends.
    /// @param _consensusThreshold The BOT amount that needs to be reached for this DecentralizedOracle to be valid.
    constructor(
        uint16 _version,
        address _owner,
        address _eventAddress,
        uint8 _numOfResults,
        uint8 _lastResultIndex,
        uint256 _arbitrationEndTime,
        uint256 _consensusThreshold)
        Ownable(_owner)
        public
        validAddress(_eventAddress)
    {
        require(_numOfResults > 0);
        require(_arbitrationEndTime > block.timestamp);
        require(_consensusThreshold > 0);

        version = _version;
        eventAddress = _eventAddress;
        numOfResults = _numOfResults;
        lastResultIndex = _lastResultIndex;
        arbitrationEndTime = _arbitrationEndTime;
        consensusThreshold = _consensusThreshold;
    }

    /// @dev Validate a vote. Must be called from TopicEvent.
    /// @param _voter Entity who is voting.
    /// @param _resultIndex Index of result to vote.
    /// @param _amount Amount of tokens used to vote.
    function validateVote(address _voter, uint8 _resultIndex, uint256 _amount)
        external
        isEventCaller(msg.sender)
        validAddress(_voter)
        validResultIndex(_resultIndex)
        isNotFinished()
        returns (bool isValid)
    {
        require(block.timestamp < arbitrationEndTime);
        require(_resultIndex != lastResultIndex);
        require(_amount > 0);
        return true;
    }

    /// @dev Records the vote. Must be called from TopicEvent.
    /// @param _voter Entity who is voting.
    /// @param _resultIndex Index of result to vote.
    /// @param _amount Amount of tokens used to vote.
    function recordVote(address _voter, uint8 _resultIndex, uint256 _amount)
        external
        isEventCaller(msg.sender)
        returns (bool didHitThreshold, uint256 currentThreshold)
    {
        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(_amount);
        balances[_resultIndex].votes[_voter] = balances[_resultIndex].votes[_voter].add(_amount);

        emit OracleResultVoted(version, address(this), _voter, _resultIndex, _amount, BOT);

        return (balances[_resultIndex].totalVotes >= consensusThreshold, consensusThreshold);
    }

    /// @dev Records the result. Votes on a result hit the consensusThreshold. Must be called from TopicEvent.
    /// @param _resultIndex Index of the result to set.
    function recordSetResult(uint8 _resultIndex) external isEventCaller(msg.sender) {
        finished = true;
        resultIndex = _resultIndex;

        emit OracleResultSet(version, address(this), _resultIndex);
    }

    /// @notice This can be called by anyone if this VotingOracle did not meet the consensus threshold and has reached 
    ///         the arbitration end time. This finishes the Event and allows winners to withdraw their winnings from the 
    ///         Event contract.
    /// @return Flag to indicate success of finalizing the result.
    function finalizeResult() external isNotFinished() {
        require(block.timestamp >= arbitrationEndTime);

        finished = true;
        resultIndex = lastResultIndex;

        ITopicEvent(eventAddress).decentralizedOracleFinalizeResult();
    }
}
