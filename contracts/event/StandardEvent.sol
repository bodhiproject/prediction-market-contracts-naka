pragma solidity ^0.5.8;

import "../storage/IConfigManager.sol";
import "../token/INRC223.sol";
import "../token/NRC223Receiver.sol";
import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/ByteUtils.sol";

contract StandardEvent is NRC223Receiver, Ownable {
    using ByteUtils for bytes;
    using ByteUtils for bytes32;
    using SafeMath for uint256;

    // Represents all the bets/votes of a specific result.
    struct ResultBalance {
        uint256 totalBets;
        uint256 totalVotes;
        mapping(address => uint256) bets;
        mapping(address => uint256) votes;
    }

    // Represents the aggregated bets/votes of a round.
    struct EventRound {
        bool finished;
        uint8 lastResultIndex;
        uint8 resultIndex;
        uint256 consensusThreshold;
        uint256 arbitrationEndTime;
        ResultBalance[11] resultBalances;
    }

    /// @notice Status types
    /// Betting: Bet with the betting token during this phase.
    /// Arbitration: Vote against set result with the arbitration token during this phase.
    /// Collection: Winners collect their winnings during this phase.
    enum Status {
        Betting,
        Arbitration,
        Collection
    }

    uint16 public constant VERSION = 0;
    uint8 private constant INVALID_RESULT_INDEX = 255;

    Status private _status = Status.Betting;
    bool private _escrowWithdrawn;
    uint8 private _numOfResults;
    uint8 private _currentRound = 0;
    uint8 private _currentResultIndex;
    bytes32[10] private _eventName;
    bytes32[11] private _eventResults;
    address private _bodhiTokenAddress;
    address private _centralizedOracle;
    uint256 private _betStartTime;
    uint256 private _betEndTime;
    uint256 private _resultSetStartTime;
    uint256 private _resultSetEndTime;
    uint256 private _totalBetAmount;
    uint256 private _totalVoteAmount;
    uint256 private _escrowAmount;
    uint256 private _arbitrationLength;
    uint256 private _thresholdPercentIncrease;
    uint256 private _arbitrationRewardPercentage;
    EventRound[] private _eventRounds;
    mapping(address => bool) private _didWithdraw;

    // Events
    event BetPlaced(
        address indexed eventAddress,
        address indexed better,
        uint8 resultIndex,
        uint256 amount
    );
    event ResultSet(
        address indexed eventAddress,
        address indexed centralizedOracle,
        uint8 resultIndex,
        uint256 amount
    );
    event VotePlaced(
        address indexed eventAddress,
        address indexed voter,
        uint8 resultIndex,
        uint256 amount
    );
    event VoteResultSet(
        address indexed eventAddress,
        address indexed voter,
        uint8 resultIndex,
        uint256 amount
    );
    event FinalResultSet(
        address indexed eventAddress,
        uint8 finalResultIndex
    );
    event WinningsWithdrawn(
        address indexed winner,
        uint256 betTokensAmount,
        uint256 voteTokensAmount
    );

    // Modifiers
    modifier inBettingStatus() {
        require(_status == Status.Betting);
        _;
    }
    modifier inArbitrationStatus() {
        require(_status == Status.Arbitration);
        _;
    }
    modifier readyToWithdraw() {
        require(block.timestamp >= _eventRounds[_currentRound].arbitrationEndTime);
        _;
    }
    modifier validResultIndex(uint8 resultIndex) {
        require (resultIndex <= _numOfResults - 1);
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
        bytes32[10] eventName,
        bytes32[11] eventResults,
        uint8 numOfResults,
        uint256 betStartTime,
        uint256 betEndTime,
        uint256 resultSetStartTime,
        uint256 resultSetEndTime,
        address centralizedOracle,
        address configManager)
        Ownable(owner)
        public
        validAddress(resultSetter)
        validAddress(configManager)
    {
        require(!eventName[0].isEmpty());
        require(!eventResults[0].isEmpty());
        require(!eventResults[1].isEmpty());
        require(betEndTime > betStartTime);
        require(resultSetStartTime >= betEndTime);
        require(resultSetEndTime > resultSetStartTime);

        _eventName = eventName;
        _eventResults = eventResults;
        _numOfResults = numOfResults;
        _betStartTime = betStartTime;
        _betEndTime = betEndTime;
        _resultSetStartTime = resultSetStartTime;
        _resultSetEndTime = resultSetEndTime;
        _centralizedOracle = centralizedOracle;

        // Fetch current config and set
        IConfigManager configManager = IConfigManager(configManager);
        _bodhiTokenAddress = configManager.bodhiTokenAddress();
        assert(_bodhiTokenAddress != address(0));
        _escrowAmount = configManager.eventEscrowAmount();
        _arbitrationLength = configManager.arbitrationLength();
        _arbitrationRewardPercentage = configManager.arbitrationRewardPercentage();
        _thresholdPercentIncrease = configManager.thresholdPercentIncrease();

        // Init CentralizedOracle round
        initEventRound(
            INVALID_RESULT_INDEX,
            configManager.startingOracleThreshold(),
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
        bytes data)
        external
    {
        // TODO: check token address and make sure NBOT is accepted only

        bytes memory setResultFunc = hex"a6b4218b";
        bytes memory voteFunc = hex"1e00eb7f";

        bytes memory funcHash = data.sliceBytes(0, 4);
        uint8 resultIndex = uint8(data.sliceUint(4));

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
        inBettingStatus
        validResultIndex(resultIndex)
    {
        require(block.timestamp >= _betStartTime);
        require(block.timestamp < _betEndTime);
        require(msg.value > 0);

        // Update balances
        _eventRounds[0].resultBalances[resultIndex].totalBets =
            _eventRounds[0].resultBalances[resultIndex].totalBets.add(msg.value);
        _eventRounds[0].resultBalances[resultIndex].bets[msg.sender] =
            _eventRounds[0].resultBalances[resultIndex].bets[msg.sender].add(msg.value);
        _totalBetAmount = _totalBetAmount.add(msg.value);

        // Emit events
        emit BetPlaced(address(this), msg.sender, resultIndex, msg.value);
    }

    /// @notice Withdraw winnings if the DecentralizedOracle round arbitrationEndTime has passed.
    function withdraw() external readyToWithdraw {
        // Finalize the result if not already done
        if (_status != status.Collection) {
            finalizeResult()
        }

        require(!_didWithdraw[msg.sender]);

        didWithdraw[msg.sender] = true;
        uint256 voteTokenAmount;
        uint256 betTokenAmount;
        (voteTokenAmount, betTokenAmount) = calculateWinnings();

        if (betTokenAmount > 0) {
            msg.sender.transfer(betTokenAmount);
        }
        if (voteTokenAmount > 0) {
            INRC223(_bodhiTokenAddress).transfer(msg.sender, voteTokenAmount);
        }

        emit WinningsWithdrawn(msg.sender, betTokenAmount, voteTokenAmount);
    }

    /// @notice Allows the owner of the Event to withdraw the escrow.
    function withdrawEscrow() external readyToWithdraw onlyOwner {
        // Finalize the result if not already done
        if (_status != status.Collection) {
            finalizeResult()
        }

        require(!_escrowWithdrawn);

        escrowWithdrawn = true;
        // TODO: IronBank.withdrawEscrow()
        // addressManager.withdrawEscrow(msg.sender, escrowAmount);
    }

    function getEventRound(uint8 index) public view returns (EventRound) {
        return _eventRounds[index];
    }

    /// @notice Gets the final result index and flag indicating if the result is final.
    /// @return Result index and if it is the final result.
    function getFinalResult() public view returns (uint8, bool) {
        return (resultIndex, status == Status.Collection);
    }

    /// @notice Calculates the tokens returned based on the sender's participation.
    /// @return The amount of arbitration tokens and bet tokens won.
    function calculateWinnings()
        public
        view
        inCollectionStatus()
        returns (uint256 arbitrationTokens, uint256 betTokens)
    {
        uint256 votes = balances[resultIndex].votes[msg.sender];
        uint256 bets = balances[resultIndex].bets[msg.sender];

        // Calculate bet token reward
        uint256 losersTotal = 0;
        for (uint8 i = 0; i < numOfResults; i++) {
            if (i != resultIndex) {
                losersTotal = losersTotal.add(balances[i].totalBets);
            }
        }
        uint256 betTokenReward = uint256(ARBITRATION_REWARD_PERCENTAGE).mul(losersTotal).div(100);
        losersTotal = losersTotal.sub(betTokenReward);

        // Calculate bet token return
        uint256 winnersTotal;
        uint256 betTokenReturn = 0;
        if (bets > 0) {
            winnersTotal = balances[resultIndex].totalBets;
            betTokenReturn = bets.mul(losersTotal).div(winnersTotal).add(bets);
        }

        // Calculate arbitration token return
        uint256 arbitrationTokenReturn = 0;
        if (votes > 0) {
            winnersTotal = balances[resultIndex].totalVotes;
            losersTotal = 0;
            for (i = 0; i < numOfResults; i++) {
                if (i != resultIndex) {
                    losersTotal = losersTotal.add(balances[i].totalVotes);
                }
            }
            arbitrationTokenReturn = votes.mul(losersTotal).div(winnersTotal).add(votes);

            // Add the bet token reward from arbitration to the betTokenReturn
            uint256 rewardWon = votes.mul(betTokenReward).div(winnersTotal);
            betTokenReturn = betTokenReturn.add(rewardWon);
        }

        return (arbitrationTokenReturn, betTokenReturn);
    }

    function initEventRound(
        uint8 lastResultIndex,
        uint256 consensusThreshold,
        uint256 arbitrationEndTime)
        private
    {
        _eventRounds.push(EventRound({
            finished: false,
            lastResultIndex: lastResultIndex,
            resultIndex: INVALID_RESULT_INDEX,
            consensusThreshold: consensusThreshold,
            arbitrationEndTime: arbitrationEndTime
        }))
    }

    /// @dev Centralized Oracle sets the result. Only tokenFallback should be calling this.
    /// @param from Address who is setting the result.
    /// @param resultIndex Index of the result to set.
    /// @param value Amount of tokens that was sent when calling setResult.
    function setResult(
        address from,
        uint8 resultIndex,
        uint256 value)
        private
        inBettingStatus
        validResultIndex(resultIndex)
    {
        require(block.timestamp >= _resultSetStartTime);
        if (block.timestamp < _resultSetEndTime) {
            require(from == _centralizedOracle);
        }
        require(value == _eventRounds[0].consensusThreshold);

        // Update status and result
        _status = Status.Arbitration;
        _eventRounds[0].finished = true;
        _eventRounds[0].resultIndex = resultIndex;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;

        // Update balances
        _eventRounds[0].resultBalances[resultIndex].totalVotes =
            _eventRounds[0].resultBalances[resultIndex].totalVotes.add(value);
        _eventRounds[0].resultBalances[resultIndex].votes[from] =
            _eventRounds[0].resultBalances[resultIndex].votes[from].add(value);
        _totalVoteAmount = _totalVoteAmount.add(value);

        // Init DecentralizedOracle round
        initEventRound(
            resultIndex,
            getNextThreshold(_eventRounds[0].consensusThreshold),
            block.timestamp.add(_arbitrationLength));

        // Emit events
        emit ResultSet(address(this), from, resultIndex, value);
    }

    /// @dev Vote against the current result. Only tokenFallback should be calling this.
    /// @param from Address who is voting.
    /// @param resultIndex Index of result to vote.
    /// @param value Amount of tokens used to vote.
    function vote(
        address from,
        uint8 resultIndex,
        uint256 value)
        private
        inArbitrationStatus
        validResultIndex(resultIndex)
    {
        require(block.timestamp < _eventRounds[_currentRound].arbitrationEndTime);
        require(resultIndex != _eventRounds[_currentRound].lastResultIndex);
        require(value > 0);

        // Update balances
        _eventRounds[_currentRound].resultBalances[resultIndex].totalVotes =
            _eventRounds[_currentRound].resultBalances[resultIndex].totalVotes.add(value);
        _eventRounds[_currentRound].resultBalances[resultIndex].votes[from] =
            _eventRounds[_currentRound].resultBalances[resultIndex].votes[from].add(value);
        _totalVoteAmount = _totalVoteAmount.add(value);

        // Emit events
        emit VotePlaced(address(this), from, resultIndex, value);

        // If voted over the threshold, create a new DecentralizedOracle round
        uint256 resultVotes = _eventRounds[_currentRound].resultBalances[resultIndex].totalVotes;
        uint256 threshold = _eventRounds[_currentRound].consensusThreshold;
        if (resultVotes >= threshold) {
            voteSetResult()
        }
    }

    /// @dev Result got voted over the threshold so start a new DecentralizedOracle round.
    /// @param from Address who is voted over the threshold.
    /// @param resultIndex Index of result that was voted over the threshold.
    /// @param value Amount of tokens used to vote.
    function voteSetResult(
        address from,
        uint8 resultIndex,
        uint256 value)
        private
    {
        // Init next DecentralizedOracle round
        initEventRound(
            resultIndex,
            getNextThreshold(_eventRounds[_currentRound].consensusThreshold),
            block.timestamp.add(_arbitrationLength));

        // Update status and result
        _status = Status.Arbitration;
        _eventRounds[_currentRound].resultIndex = resultIndex;
        _eventRounds[_currentRound].finished = true;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;

        // Emit events
        emit VoteResultSet(address(this), from, resultIndex, value);
    }

    /// @dev Finalizes the result before doing a withdraw.
    function finalizeResult() {
        _status = Status.Collection;
        _eventRounds[_currentRound].finished = true

        emit FinalResultSet(address(this), _currentResultIndex);
    }

    function getNextThreshold(
        uint256 currentThreshold)
        private
        returns (uint256)
    {
        uint256 increment = _thresholdPercentIncrease.mul(currentThreshold).div(100);
        return currentThreshold.add(increment);
    }
}
