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

    /// @notice Status types
    /// Betting: Bet with the betting token.
    /// Arbitration: Vote against previous rounds result with the arbitration token.
    /// Collection: Winners collect their winnings.
    enum Status {
        Betting,
        Arbitration,
        Collection
    }

    // Represents the accumulated bets/votes.
    struct DepositTotal {
        uint totalBets;
        uint totalVotes;
    }

    // Represents all the bets/votes of a result.
    struct RoundDeposits {
        uint roundBets;
        uint roundVotes;
        mapping(address => uint) bets;
        mapping(address => uint) votes;
    }

    // Represents the aggregated bets/votes of a round.
    struct EventRound {
        bool finished;
        uint8 lastResultIndex;
        uint8 resultIndex;
        uint consensusThreshold;
        uint arbitrationEndTime;
        RoundDeposits[11] deposits;
    }

    uint16 private constant VERSION = 0;
    uint8 private constant INVALID_RESULT_INDEX = 255;

    uint8 private _numOfResults;
    uint8 private _currentRound = 0;
    uint8 private _currentResultIndex;
    string private _eventName;
    bytes32[11] private _eventResults;
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
    DepositTotal private _allTotals;
    DepositTotal[11] private _resultTotals;
    EventRound[] private _eventRounds;
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
        uint8 eventRound
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
        uint8 eventRound
    );
    event FinalResultSet(
        address indexed eventAddress,
        uint8 finalResultIndex,
        uint8 eventRound
    );
    event WinningsWithdrawn(
        address indexed winner,
        uint betTokensAmount,
        uint voteTokensAmount,
        uint escrowAmount
    );

    // Modifiers
    modifier readyToWithdraw() {
        require(
            block.timestamp >= _eventRounds[_currentRound].arbitrationEndTime,
            "Current time should be >= arbitrationEndTime");
        _;
    }
    modifier validResultIndex(uint8 resultIndex) {
        require (resultIndex <= _numOfResults - 1, "resultIndex is not valid");
        _;
    }

    /// @notice Creates a new StandardEvent contract.
    /// @param owner Address of the owner.
    /// @param eventName Question or statement prediction broken down by multiple bytes32.
    /// @param eventResults Possible results.
    /// @param numOfResults Number of results for the event.
    /// @param betStartTime Unix time when betting will start.
    /// @param betEndTime Unix time when betting will end.
    /// @param resultSetStartTime Unix time when the CentralizedOracle can set the result.
    /// @param resultSetEndTime Unix time when anyone can set the result.
    /// @param centralizedOracle Address of the user that will decide the result.
    /// @param configManager Address of the ConfigManager.
    constructor(
        address owner,
        string memory eventName,
        bytes32[11] memory eventResults,
        uint8 numOfResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime,
        address centralizedOracle,
        address configManager)
        Ownable(owner)
        public
        validAddress(centralizedOracle)
        validAddress(configManager)
    {
        bytes memory eventNameBytes = bytes(eventName);
        require(eventNameBytes.length > 0, "Event name cannot be empty");
        require(!eventResults[0].isEmpty(), "Event result 0 cannot be empty");
        require(!eventResults[1].isEmpty(), "Event result 1 cannot be empty");
        require(betEndTime > betStartTime, "betEndTime should be > betStartTime");
        require(
            resultSetStartTime >= betEndTime,
            "resultSetStartTime should be >= betEndTime");
        require(
            resultSetEndTime > resultSetStartTime,
            "resultSetEndTime should be > resultSetStartTime");

        _eventName = eventName;
        _eventResults = eventResults;
        _numOfResults = numOfResults;
        _betStartTime = betStartTime;
        _betEndTime = betEndTime;
        _resultSetStartTime = resultSetStartTime;
        _resultSetEndTime = resultSetEndTime;
        _centralizedOracle = centralizedOracle;

        // Fetch current config and set
        IConfigManager config = IConfigManager(configManager);
        _bodhiTokenAddress = config.bodhiTokenAddress();
        assert(_bodhiTokenAddress != address(0));
        _eventFactoryAddress = config.eventFactoryAddress();
        assert(_eventFactoryAddress != address(0));
        _escrowAmount = config.eventEscrowAmount();
        _arbitrationLength = config.arbitrationLength();
        _arbitrationRewardPercentage = config.arbitrationRewardPercentage();
        _thresholdPercentIncrease = config.thresholdPercentIncrease();

        // Init CentralizedOracle round
        initEventRound(
            INVALID_RESULT_INDEX,
            config.startingOracleThreshold(),
            0);
    }

    /// @notice Fallback function implemented to accept native tokens for betting.
    function() external payable {}

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
        // Ensure only NBOT can call this method
        require(msg.sender == _bodhiTokenAddress, "Only NBOT is accepted");

        bytes memory setResultFunc = hex"a6b4218b";
        bytes memory voteFunc = hex"1e00eb7f";

        bytes memory funcHash = data.sliceBytes(0, 4);
        bytes memory params = data.sliceBytes(4, data.length);
        (uint8 resultIndex) = abi.decode(params, (uint8));

        bytes32 encodedFunc = keccak256(abi.encodePacked(funcHash));
        if (encodedFunc == keccak256(abi.encodePacked(setResultFunc))) {
            assert(data.length == 36);
            setResult(from, resultIndex, value);
        } else if (encodedFunc == keccak256(abi.encodePacked(voteFunc))) {
            assert(data.length == 36);
            vote(from, resultIndex, value);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    /// @notice Place a bet.
    /// @param resultIndex Index of result to bet on.
    function bet(
        uint8 resultIndex)
        external
        payable
        validResultIndex(resultIndex)
    {
        require(
            block.timestamp >= _betStartTime,
            "Current time should be >= betStartTime");
        require(
            block.timestamp < _betEndTime,
            "Current time should be < betEndTime.");
        require(msg.value > 0, "Bet amount should be > 0");

        // Update balances
        _eventRounds[0].deposits[resultIndex].roundBets =
            _eventRounds[0].deposits[resultIndex].roundBets.add(msg.value);
        _eventRounds[0].deposits[resultIndex].bets[msg.sender] =
            _eventRounds[0].deposits[resultIndex].bets[msg.sender].add(msg.value);
        _resultTotals[resultIndex].totalBets =
            _resultTotals[resultIndex].totalBets.add(msg.value);
        _allTotals.totalBets = _allTotals.totalBets.add(msg.value);

        // Emit events
        emit BetPlaced(address(this), msg.sender, resultIndex, msg.value, 
            _currentRound);
    }

    /// @notice Withdraw winnings if the DecentralizedOracle round arbitrationEndTime has passed.
    function withdraw() external readyToWithdraw {
        // Finalize the result if not already done
        if (!_eventRounds[_currentRound].finished) {
            finalizeResult();
        }

        require(!_didWithdraw[msg.sender], "Already withdrawn");

        _didWithdraw[msg.sender] = true;
        uint betTokenAmount;
        uint voteTokenAmount;
        (betTokenAmount, voteTokenAmount) = calculateWinnings();

        if (betTokenAmount > 0) {
            msg.sender.transfer(betTokenAmount);
        }
        if (voteTokenAmount > 0) {
            INRC223(_bodhiTokenAddress).transfer(msg.sender, voteTokenAmount);
        }

        // Withdraw escrow if owner
        uint escrowAmount = 0;
        if (msg.sender == owner
            && !IEventFactory(_eventFactoryAddress).didWithdraw()) {
            escrowAmount = IEventFactory(_eventFactoryAddress).withdrawEscrow();
        }

        emit WinningsWithdrawn(msg.sender, betTokenAmount, voteTokenAmount, 
            escrowAmount);
    }

    /// @notice Calculates the tokens returned based on the sender's participation.
    /// @return Amount of bet and vote tokens won.
    function calculateWinnings()
        public
        view
        returns (uint, uint)
    {
        // Get winning bets/votes for sender
        uint bets;
        uint votes;
        for (uint i = 0; i <= _currentRound; i++) {
            bets = bets.add(
                _eventRounds[i].deposits[_currentResultIndex].bets[msg.sender]);
            votes = votes.add(
                _eventRounds[i].deposits[_currentResultIndex].votes[msg.sender]);
        }

        // Calculate losers' bets
        uint losersTotal;
        for (uint i = 0; i < _numOfResults; i++) {
            if (i != _currentResultIndex) {
                losersTotal = losersTotal.add(_resultTotals[i].totalBets);
            }
        }
        // Subtract arbitration participation reward from losers total
        uint betTokenReward = 
            uint(_arbitrationRewardPercentage).mul(losersTotal).div(100);
        losersTotal = losersTotal.sub(betTokenReward);

        // Calculate bet token return
        uint winnersTotal;
        uint betTokenReturn;
        if (bets > 0) {
            winnersTotal = _resultTotals[_currentResultIndex].totalBets;
            betTokenReturn = bets.mul(losersTotal).div(winnersTotal).add(bets);
        }

        // Calculate vote token return
        uint voteTokenReturn;
        if (votes > 0) {
            winnersTotal = _resultTotals[_currentResultIndex].totalVotes;
            losersTotal = 0;
            for (uint i = 0; i < _numOfResults; i++) {
                if (i != _currentResultIndex) {
                    losersTotal = losersTotal.add(_resultTotals[i].totalVotes);
                }
            }
            voteTokenReturn = votes.mul(losersTotal).div(winnersTotal).add(votes);

            // Add bet token reward from arbitration to betTokenReturn
            uint rewardWon = votes.mul(betTokenReward).div(winnersTotal);
            betTokenReturn = betTokenReturn.add(rewardWon);
        }

        return (betTokenReturn, voteTokenReturn);
    }

    function version() public view returns (uint16) {
        return VERSION;
    }

    function currentRound() public view returns (uint8) {
        return _currentRound;
    }

    function currentResultIndex() public view returns (uint8) {
        return _currentResultIndex;
    }

    function eventMetadata()
        public
        view
        returns (string memory, bytes32[11] memory, uint8)
    {
        return (
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

    function totalAmounts() public view returns (uint, uint) {
        return (_allTotals.totalBets, _allTotals.totalVotes);
    }

    function didWithdraw() public view returns (bool) {
        return _didWithdraw[msg.sender];
    }

    function didWithdrawEscrow() public view returns (bool) {
        return IEventFactory(_eventFactoryAddress).didWithdraw();
    }

    function initEventRound(
        uint8 lastResultIndex,
        uint consensusThreshold,
        uint arbitrationEndTime)
        private
    {
        EventRound memory round;
        round.finished = false;
        round.lastResultIndex = lastResultIndex;
        round.consensusThreshold = consensusThreshold;
        round.arbitrationEndTime = arbitrationEndTime;
        _eventRounds.push(round);
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
        require(!_eventRounds[0].finished, "Result has already been set");
        require(
            block.timestamp >= _resultSetStartTime,
            "Current time should be >= resultSetStartTime");
        if (block.timestamp < _resultSetEndTime) {
            require(
                from == _centralizedOracle,
                "Only the CentralizedOracle can set the result");
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
        _eventRounds[0].deposits[resultIndex].roundVotes =
            _eventRounds[0].deposits[resultIndex].roundVotes.add(value);
        _eventRounds[0].deposits[resultIndex].votes[from] =
            _eventRounds[0].deposits[resultIndex].votes[from].add(value);
        _resultTotals[resultIndex].totalVotes =
            _resultTotals[resultIndex].totalVotes.add(value);
        _allTotals.totalVotes = _allTotals.totalVotes.add(value);

        // Init DecentralizedOracle round
        initEventRound(
            resultIndex,
            getNextThreshold(_eventRounds[0].consensusThreshold),
            block.timestamp.add(_arbitrationLength));

        // Emit events
        emit ResultSet(address(this), from, resultIndex, value, 0);
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
        require(
            block.timestamp < _eventRounds[_currentRound].arbitrationEndTime,
            "Current time should be < arbitrationEndTime");
        require(
            resultIndex != _eventRounds[_currentRound].lastResultIndex,
            "Cannot vote on the last result index");
        require(value > 0, "Vote amount should be > 0");

        // Update balances
        _eventRounds[_currentRound].deposits[resultIndex].roundVotes =
            _eventRounds[_currentRound].deposits[resultIndex].roundVotes.add(value);
        _eventRounds[_currentRound].deposits[resultIndex].votes[from] =
            _eventRounds[_currentRound].deposits[resultIndex].votes[from].add(value);
        _resultTotals[resultIndex].totalVotes =
            _resultTotals[resultIndex].totalVotes.add(value);
        _allTotals.totalVotes = _allTotals.totalVotes.add(value);

        // Emit events
        emit VotePlaced(address(this), from, resultIndex, value, _currentRound);

        // If voted over the threshold, create a new DecentralizedOracle round
        uint resultVotes = _eventRounds[_currentRound].deposits[resultIndex].roundVotes;
        uint threshold = _eventRounds[_currentRound].consensusThreshold;
        if (resultVotes >= threshold) {
            voteSetResult(from, resultIndex, value);
        }
    }

    /// @dev Result got voted over the threshold so start a new DecentralizedOracle round.
    /// @param from Address who is voted over the threshold.
    /// @param resultIndex Index of result that was voted over the threshold.
    /// @param value Amount of tokens used to vote.
    function voteSetResult(
        address from,
        uint8 resultIndex,
        uint value)
        private
    {
        // Init next DecentralizedOracle round
        initEventRound(
            resultIndex,
            getNextThreshold(_eventRounds[_currentRound].consensusThreshold),
            block.timestamp.add(_arbitrationLength));

        // Emit events
        emit VoteResultSet(address(this), from, resultIndex, value, _currentRound);

        // Update status and result
        _eventRounds[_currentRound].resultIndex = resultIndex;
        _eventRounds[_currentRound].finished = true;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;
    }

    /// @dev Finalizes the result before doing a withdraw.
    function finalizeResult() private {
        _eventRounds[_currentRound].finished = true;
        emit FinalResultSet(address(this), _currentResultIndex, _currentRound);
    }

    function getNextThreshold(
        uint currentThreshold)
        private
        returns (uint)
    {
        uint increment = _thresholdPercentIncrease.mul(currentThreshold).div(100);
        return currentThreshold.add(increment);
    }
}
