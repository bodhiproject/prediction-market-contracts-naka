pragma solidity ^0.5.8;

import "./IEventFactory.sol";
import "../storage/IConfigManager.sol";
import "../token/INRC223.sol";
import "../token/NRC223Receiver.sol";
import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/ByteUtils.sol";

contract MultipleResultsEvent is NRC223Receiver, Ownable {
    using ByteUtils for bytes;
    using ByteUtils for bytes32;
    using SafeMath for uint;

    /// @dev Represents the aggregated bets/votes of a round.
    struct EventRound {
        bool finished;
        uint8 lastResultIndex;
        uint8 resultIndex;
        uint consensusThreshold;
        uint arbitrationEndTime;
    }

    uint16 private constant VERSION = 6;
    uint8 private constant INVALID_RESULT_INDEX = 255;

    uint8 private _numOfResults;
    uint8 private _currentRound = 0;
    uint8 private _currentResultIndex = INVALID_RESULT_INDEX;
    string private _eventName;
    bytes32[4] private _eventResults;
    address private _bodhiTokenAddress;
    address private _eventFactoryAddress;
    address private _centralizedOracle;
    uint private _betStartTime;
    uint private _betEndTime;
    uint private _resultSetStartTime;
    uint private _resultSetEndTime;
    uint private _escrowAmount;
    uint private _arbitrationLength;
    uint private _thresholdPercentIncrease;
    uint private _arbitrationRewardPercentage;
    uint private _totalBets;
    uint[4] private _betRoundTotals;
    uint[4] private _voteRoundsTotals;
    uint[4] private _currentVotingRoundTotals;
    mapping(address => uint[4]) private _betRoundUserTotals;
    mapping(address => uint[4]) private _voteRoundsUserTotals;
    mapping(uint8 => EventRound) private _eventRounds;
    mapping(address => bool) private _didWithdraw;

    // Events
    event BetPlaced(
        address indexed eventAddress,
        address indexed better,
        uint8 resultIndex,
        uint amount,
        uint8 eventRound
    );
    event ResultSet(
        address indexed eventAddress,
        address indexed centralizedOracle,
        uint8 resultIndex,
        uint amount,
        uint8 eventRound,
        uint nextConsensusThreshold,
        uint nextArbitrationEndTime
    );
    event VotePlaced(
        address indexed eventAddress,
        address indexed voter,
        uint8 resultIndex,
        uint amount,
        uint8 eventRound
    );
    event VoteResultSet(
        address indexed eventAddress,
        address indexed voter,
        uint8 resultIndex,
        uint amount,
        uint8 eventRound,
        uint nextConsensusThreshold,
        uint nextArbitrationEndTime
    );
    event WinningsWithdrawn(
        address indexed eventAddress,
        address indexed winner,
        uint winningAmount,
        uint escrowAmount
    );

    // Modifiers
    modifier validResultIndex(uint8 resultIndex) {
        require (resultIndex <= _numOfResults - 1, "resultIndex is not valid");
        _;
    }

    /// @notice Creates a new StandardEvent contract.
    /// @param owner Address of the owner.
    /// @param eventName Question or statement prediction.
    /// @param eventResults Possible results.
    /// @param numOfResults Number of results.
    /// @param betStartTime Unix time when betting will start.
    /// @param betEndTime Unix time when betting will end.
    /// @param resultSetStartTime Unix time when the CentralizedOracle can set the result.
    /// @param resultSetEndTime Unix time when anyone can set the result.
    /// @param centralizedOracle Address of the user that will decide the result.
    /// @param arbitrationOptionIndex Index of the selected arbitration option.
    /// @param arbitrationRewardPercentage Percentage of loser's bets going to winning arbitrators.
    /// @param configManager Address of the ConfigManager.
    constructor(
        address owner,
        string memory eventName,
        bytes32[4] memory eventResults,
        uint8 numOfResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime,
        address centralizedOracle,
        uint8 arbitrationOptionIndex,
        uint arbitrationRewardPercentage,
        address configManager)
        Ownable(owner)
        public
        validAddress(centralizedOracle)
        validAddress(configManager)
    {
        bytes memory eventNameBytes = bytes(eventName);
        require(eventNameBytes.length > 0, "Event name cannot be empty");
        require(!eventResults[1].isEmpty(), "First event result cannot be empty");
        require(!eventResults[2].isEmpty(), "Second event result cannot be empty");
        require(betEndTime > betStartTime, "betEndTime should be > betStartTime");
        require(
            resultSetStartTime >= betEndTime,
            "resultSetStartTime should be >= betEndTime");
        require(
            resultSetEndTime > resultSetStartTime,
            "resultSetEndTime should be > resultSetStartTime");
        require(
            arbitrationOptionIndex < 4,
            "arbitrationOptionIndex should be < 4");
        require(
            arbitrationRewardPercentage < 100,
            "arbitrationRewardPercentage should be < 100");

        _eventName = eventName;
        _eventResults = eventResults;
        _numOfResults = numOfResults;
        _betStartTime = betStartTime;
        _betEndTime = betEndTime;
        _resultSetStartTime = resultSetStartTime;
        _resultSetEndTime = resultSetEndTime;
        _centralizedOracle = centralizedOracle;
        _arbitrationRewardPercentage = arbitrationRewardPercentage;

        // Fetch current config
        IConfigManager config = IConfigManager(configManager);
        _bodhiTokenAddress = config.bodhiTokenAddress();
        assert(_bodhiTokenAddress != address(0));
        _eventFactoryAddress = config.eventFactoryAddress();
        assert(_eventFactoryAddress != address(0));
        _escrowAmount = config.eventEscrowAmount();
        _arbitrationLength = config.arbitrationLength()[arbitrationOptionIndex];
        _thresholdPercentIncrease = config.thresholdPercentIncrease();

        // Init CentralizedOracle round
        initEventRound(
            0,
            INVALID_RESULT_INDEX,
            config.startingConsensusThreshold()[arbitrationOptionIndex],
            0
        );
    }

    /// @dev Standard NRC223 function that will handle incoming token transfers.
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
        require(data.length >= 4, "Data is not long enough");

        bytes memory betFunc = hex"885ab66d";
        bytes memory setResultFunc = hex"a6b4218b";
        bytes memory voteFunc = hex"1e00eb7f";

        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length - 4);
        (uint8 resultIndex) = abi.decode(params, (uint8));

        bytes32 funcCalled = keccak256(abi.encodePacked(funcHash));
        if (funcCalled == keccak256(abi.encodePacked(betFunc))) {
            bet(from, resultIndex, value);
        } else if (funcCalled == keccak256(abi.encodePacked(setResultFunc))) {
            setResult(from, resultIndex, value);
        } else if (funcCalled == keccak256(abi.encodePacked(voteFunc))) {
            vote(from, resultIndex, value);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    /// @notice Withdraw winnings if the DecentralizedOracle round arbitrationEndTime has passed.
    function withdraw() external {
        require(_currentRound > 0, "Cannot withdraw during betting round.");
        require(
            block.timestamp >= _eventRounds[_currentRound].arbitrationEndTime,
            "Current time should be >= arbitrationEndTime");
        require(!_didWithdraw[msg.sender], "Already withdrawn");

        // Finalize the result if not already done
        if (!_eventRounds[_currentRound].finished) {
            finalizeResult();
        }

        // Calculate and transfer winnings
        _didWithdraw[msg.sender] = true;
        uint winningAmount = calculateWinnings(msg.sender);
        if (winningAmount > 0) {
            INRC223(_bodhiTokenAddress).transfer(msg.sender, winningAmount);
        }

        // Transfer escrow if owner
        uint escrowAmount = 0;
        if (msg.sender == owner
            && !IEventFactory(_eventFactoryAddress).didWithdraw()) {
            escrowAmount = IEventFactory(_eventFactoryAddress).withdrawEscrow();
        }

        // Emit events
        emit WinningsWithdrawn(address(this), msg.sender, winningAmount, 
            escrowAmount);
    }

    /// @notice Calculates the tokens returned based on the sender's participation.
    /// @param player Address to calculate winnings for.
    /// @return Amount of tokens that will be returned.
    function calculateWinnings(
        address player)
        public
        view
        returns (uint)
    {
        // Return 0 if there currentResultIndex is invalid since we cannot
        // iterate through the balances by that index.
        if (_currentResultIndex == INVALID_RESULT_INDEX) {
            return 0;
        }

        // Bets are returned if the currentResultIndex is Invalid
        if (_currentResultIndex == 0) {
            return calculateInvalidWinnings(player);
        }

        // Otherwise calculate winnings for a non-Invalid result
        return calculateNormalWinnings(player);
    }

    function version() public pure returns (uint16) {
        return VERSION;
    }

    function currentRound() public view returns (uint8) {
        return _currentRound;
    }

    function currentResultIndex() public view returns (uint8) {
        return _currentResultIndex;
    }

    function currentConsensusThreshold() public view returns (uint) {
        return _eventRounds[_currentRound].consensusThreshold;
    }

    function currentArbitrationEndTime() public view returns (uint) {
        return _eventRounds[_currentRound].arbitrationEndTime;
    }

    function eventMetadata()
        public
        view
        returns (uint16, string memory, bytes32[4] memory, uint8)
    {
        return (
            VERSION,
            _eventName,
            _eventResults,
            _numOfResults
        );
    }

    function centralizedMetadata()
        public
        view
        returns (address, uint, uint, uint, uint)
    {
        return (
            _centralizedOracle,
            _betStartTime,
            _betEndTime,
            _resultSetStartTime,
            _resultSetEndTime
        );
    }

    function configMetadata() public view returns (uint, uint, uint, uint) {
        return (
            _escrowAmount,
            _arbitrationLength,
            _thresholdPercentIncrease,
            _arbitrationRewardPercentage
        );
    }

    function totalBets() public view returns (uint) {
        return _totalBets;
    }

    function didWithdraw(address withdrawer) public view returns (bool) {
        return _didWithdraw[withdrawer];
    }

    function didWithdrawEscrow() public view returns (bool) {
        return IEventFactory(_eventFactoryAddress).didWithdraw();
    }

    function initEventRound(
        uint8 roundIndex,
        uint8 lastResultIndex,
        uint consensusThreshold,
        uint arbitrationEndTime)
        private
    {
        _eventRounds[roundIndex].lastResultIndex = lastResultIndex;
        _eventRounds[roundIndex].resultIndex = INVALID_RESULT_INDEX;
        _eventRounds[roundIndex].consensusThreshold = consensusThreshold;
        _eventRounds[roundIndex].arbitrationEndTime = arbitrationEndTime;
    }

    /// @notice Places a bet. Only tokenFallback should call this.
    /// @param from Address who is betting.
    /// @param resultIndex Index of the result to bet on.
    /// @param value Amount of tokens used to bet.
    function bet(
        address from,
        uint8 resultIndex,
        uint value)
        private
        validResultIndex(resultIndex)
    {
        require(_currentRound == 0, "Can only bet during the betting round");
        require(
            block.timestamp >= _betStartTime,
            "Current time should be >= betStartTime");
        require(
            block.timestamp < _betEndTime,
            "Current time should be < betEndTime.");
        require(value > 0, "Bet amount should be > 0");

        // Update balances
        _totalBets = _totalBets.add(value);
        _betRoundTotals[resultIndex] = _betRoundTotals[resultIndex].add(value);
        _betRoundUserTotals[from][resultIndex] =
            _betRoundUserTotals[from][resultIndex].add(value);

        // Emit events
        emit BetPlaced(address(this), from, resultIndex, value, _currentRound);
    }

    /// @dev Centralized Oracle sets the result. Only tokenFallback should be calling this.
    /// @param from Address who is setting the result.
    /// @param resultIndex Index of the result to set.
    /// @param value Amount of tokens that was sent when calling setResult.
    function setResult(
        address from,
        uint8 resultIndex,
        uint value)
        private
        validResultIndex(resultIndex)
    {
        require(_currentRound == 0, "Can only set result during the betting round");
        require(!_eventRounds[0].finished, "Result has already been set");
        require(
            block.timestamp >= _resultSetStartTime,
            "Current time should be >= resultSetStartTime");
        if (block.timestamp < _resultSetEndTime) {
            require(
                from == _centralizedOracle,
                "Only the Centralized Oracle can set the result");
        }
        require(
            value == _eventRounds[0].consensusThreshold,
            "Set result amount should = consensusThreshold");

        // Update status and result
        _eventRounds[0].finished = true;
        _eventRounds[0].resultIndex = resultIndex;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;

        // Update balances
        _totalBets = _totalBets.add(value);
        _voteRoundsTotals[resultIndex] = _voteRoundsTotals[resultIndex].add(value);
        _voteRoundsUserTotals[from][resultIndex] =
            _voteRoundsUserTotals[from][resultIndex].add(value);

        // Init DecentralizedOracle round
        uint nextThreshold = getNextThreshold(_eventRounds[0].consensusThreshold);
        uint arbitrationEndTime = block.timestamp.add(_arbitrationLength);
        initEventRound(
            _currentRound,
            resultIndex,
            nextThreshold,
            arbitrationEndTime);

        // Emit events
        emit ResultSet(address(this), from, resultIndex, value, 0,
            nextThreshold, arbitrationEndTime);
    }

    /// @dev Vote against the current result. Only tokenFallback should be calling this.
    /// @param from Address who is voting.
    /// @param resultIndex Index of result to vote.
    /// @param value Amount of tokens used to vote.
    function vote(
        address from,
        uint8 resultIndex,
        uint value)
        private
        validResultIndex(resultIndex)
    {
        require(_currentRound > 0, "Can only vote after the betting round");
        require(
            block.timestamp < _eventRounds[_currentRound].arbitrationEndTime,
            "Current time should be < arbitrationEndTime");
        require(
            resultIndex != _eventRounds[_currentRound].lastResultIndex,
            "Cannot vote on the last result index");
        require(value > 0, "Vote amount should be > 0");

        // Calculate diff if over threshold
        uint adjustedValue = value;
        uint refund;
        if (_currentVotingRoundTotals[resultIndex].add(value) >
            _eventRounds[_currentRound].consensusThreshold) {
            adjustedValue = _eventRounds[_currentRound].consensusThreshold
                .sub(_currentVotingRoundTotals[resultIndex]);
            refund = _currentVotingRoundTotals[resultIndex]
                .add(value)
                .sub(_eventRounds[_currentRound].consensusThreshold);
        }

        // Update balances
        _totalBets = _totalBets.add(adjustedValue);
        _voteRoundsTotals[resultIndex] =
            _voteRoundsTotals[resultIndex].add(adjustedValue);
        _voteRoundsUserTotals[from][resultIndex] =
            _voteRoundsUserTotals[from][resultIndex].add(adjustedValue);
        _currentVotingRoundTotals[resultIndex] = 
            _currentVotingRoundTotals[resultIndex].add(adjustedValue);

        // Emit events
        emit VotePlaced(address(this), from, resultIndex, adjustedValue,
            _currentRound);

        // If voted over the threshold, create a new DecentralizedOracle round
        if (_currentVotingRoundTotals[resultIndex] ==
            _eventRounds[_currentRound].consensusThreshold) {
            voteSetResult(from, resultIndex, adjustedValue, refund);
        }
    }

    /// @dev Result got voted over the threshold so start a new DecentralizedOracle round.
    /// @param from Address who is voted over the threshold.
    /// @param resultIndex Index of result that was voted over the threshold.
    /// @param value Amount of tokens used to vote.
    /// @param refund Amount to refund for voting over the threshold.
    function voteSetResult(
        address from,
        uint8 resultIndex,
        uint value,
        uint refund)
        private
    {
        // Calculate next consensus threshold
        uint currThreshold = _eventRounds[_currentRound].consensusThreshold;
        uint nextThreshold =
            getNextThreshold(_eventRounds[_currentRound].consensusThreshold);
        uint8 previousRound = _currentRound;

        // Update status and result
        _eventRounds[_currentRound].resultIndex = resultIndex;
        _eventRounds[_currentRound].finished = true;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;

        // Clear current voting round totals
        delete _currentVotingRoundTotals;

        // Init next DecentralizedOracle round
        uint arbitrationEndTime = block.timestamp.add(_arbitrationLength);
        initEventRound(
            _currentRound,
            resultIndex,
            nextThreshold,
            arbitrationEndTime);

        // Refund difference over threshold
        if (refund > 0) {
            INRC223(_bodhiTokenAddress).transfer(from, refund);
        }

        // Emit events
        emit VoteResultSet(address(this), from, resultIndex, currThreshold, 
            previousRound, nextThreshold, arbitrationEndTime);
    }

    /// @dev Finalizes the result before doing a withdraw.
    function finalizeResult() private {
        _eventRounds[_currentRound].finished = true;
    }

    function getNextThreshold(
        uint currentThreshold)
        private
        view
        returns (uint)
    {
        uint increment = _thresholdPercentIncrease.mul(currentThreshold).div(100);
        return currentThreshold.add(increment);
    }

    /// @notice Calculates the tokens returned for a non-Invalid final result.
    /// @param player Address to calculate winnings for.
    /// @return Amount of tokens that will be returned.
    function calculateNormalWinnings(
        address player)
        private
        view
        returns (uint)
    {
        // Calculate user's winning bets
        uint myWinningBets = _betRoundUserTotals[player][_currentResultIndex];
        uint myWinningVotes = _voteRoundsUserTotals[player][_currentResultIndex];

        // Calculate bet and vote rounds losing totals
        uint betRoundLosersTotal;
        uint voteRoundsLosersTotal;
        for (uint8 i = 0; i < _numOfResults; i++) {
            if (i != _currentResultIndex) {
                betRoundLosersTotal = betRoundLosersTotal.add(_betRoundTotals[i]);
                voteRoundsLosersTotal =
                    voteRoundsLosersTotal.add(_voteRoundsTotals[i]);
            }
        }

        // Calculate user's winning amount for bet round
        uint maxPercent = 100;
        uint betRoundWinningAmt;
        if (myWinningBets > 0 && _betRoundTotals[_currentResultIndex] > 0) {
            uint percentage = maxPercent.sub(_arbitrationRewardPercentage);
            betRoundWinningAmt =
                betRoundLosersTotal
                .mul(percentage)
                .div(maxPercent)
                .mul(myWinningBets)
                .div(_betRoundTotals[_currentResultIndex]);
        }

        // Calculate user's winning amount for vote rounds
        uint voteRoundsWinningAmt;
        if (myWinningVotes > 0 && _voteRoundsTotals[_currentResultIndex] > 0) {
            voteRoundsWinningAmt =
                betRoundLosersTotal
                .mul(_arbitrationRewardPercentage)
                .div(maxPercent)
                .add(voteRoundsLosersTotal)
                .mul(myWinningVotes)
                .div(_voteRoundsTotals[_currentResultIndex]);
        }

        return myWinningBets
            .add(myWinningVotes)
            .add(betRoundWinningAmt)
            .add(voteRoundsWinningAmt);
    }

    /// @notice Calculates the tokens returned for an Invalid final result.
    /// @param player Address to calculate winnings for.
    /// @return Amount of tokens that will be returned.
    function calculateInvalidWinnings(
        address player)
        private
        view
        returns (uint)
    {
        // Calculate user's winning bets
        uint myWinningBets = _betRoundUserTotals[player][_currentResultIndex];
        uint myWinningVotes = _voteRoundsUserTotals[player][_currentResultIndex];

        // Calculate user's losing bets and vote rounds losing totals
        uint myLosingBets;
        uint voteRoundsLosersTotal;
        for (uint8 i = 0; i < _numOfResults; i++) {
            if (i != _currentResultIndex) {
                myLosingBets = myLosingBets.add(_betRoundUserTotals[player][i]);
                voteRoundsLosersTotal =
                    voteRoundsLosersTotal.add(_voteRoundsTotals[i]);
            }
        }

        // Calculate user's winning amount for vote rounds
        uint voteRoundsWinningAmt;
        if (myWinningVotes > 0 && _voteRoundsTotals[_currentResultIndex] > 0) {
            voteRoundsWinningAmt =
                voteRoundsLosersTotal
                .mul(myWinningVotes)
                .div(_voteRoundsTotals[_currentResultIndex]);
        }

        return myWinningBets
            .add(myLosingBets)
            .add(myWinningVotes)
            .add(voteRoundsWinningAmt);
    }
}
