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

    Status private _status = Status.Betting;
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
        string eventName,
        bytes32[11] eventResults,
        uint8 numOfResults,
        uint betStartTime,
        uint betEndTime,
        uint resultSetStartTime,
        uint resultSetEndTime,
        address centralizedOracle,
        address configManager)
        Ownable(owner)
        public
        validAddress(resultSetter)
        validAddress(configManager)
    {
        bytes memory eventNameBytes = bytes(eventName);
        require(eventNameBytes.length > 0);
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
        _eventFactoryAddress = configManager.eventFactoryAddress();
        assert(_eventFactoryAddress != address(0));
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
        // Ensure only NBOT can call this method
        require(msg.sender == _bodhiTokenAddress);

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
        if (_status != status.Collection) {
            finalizeResult()
        }

        require(!_didWithdraw[msg.sender]);

        didWithdraw[msg.sender] = true;
        uint voteTokenAmount;
        uint betTokenAmount;
        (voteTokenAmount, betTokenAmount) = calculateWinnings();

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
        // TODO: redo with new balance structure
        uint votes = balances[resultIndex].votes[msg.sender];
        uint bets = balances[resultIndex].bets[msg.sender];

        // Calculate bet token reward
        uint losersTotal = 0;
        for (uint8 i = 0; i < numOfResults; i++) {
            if (i != resultIndex) {
                losersTotal = losersTotal.add(balances[i].totalBets);
            }
        }
        uint betTokenReward = uint(ARBITRATION_REWARD_PERCENTAGE).mul(losersTotal).div(100);
        losersTotal = losersTotal.sub(betTokenReward);

        // Calculate bet token return
        uint winnersTotal;
        uint betTokenReturn = 0;
        if (bets > 0) {
            winnersTotal = balances[resultIndex].totalBets;
            betTokenReturn = bets.mul(losersTotal).div(winnersTotal).add(bets);
        }

        // Calculate arbitration token return
        uint arbitrationTokenReturn = 0;
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
            uint rewardWon = votes.mul(betTokenReward).div(winnersTotal);
            betTokenReturn = betTokenReturn.add(rewardWon);
        }

        return (arbitrationTokenReturn, betTokenReturn);
    }

    function version() public view returns (uint16) {
        return VERSION;
    }

    function status() public view returns (Status) {
        return _status;
    }

    function currentRound() public view returns (uint8) {
        return _currentRound;
    }

    function currentResultIndex() public view returns (uint8) {
        return _currentResultIndex;
    }

    function eventMetadata() public view returns (string, bytes32[11], uint8) {
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

    function totalAmounts() public view returns (DepositTotal) {
        return _allTotals;
    }

    function eventRounds() public view returns (EventRound[]) {
        return _eventRounds;
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
        uint value)
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
        inArbitrationStatus
        validResultIndex(resultIndex)
    {
        require(block.timestamp < _eventRounds[_currentRound].arbitrationEndTime);
        require(resultIndex != _eventRounds[_currentRound].lastResultIndex);
        require(value > 0);

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
        _status = Status.Arbitration;
        _eventRounds[_currentRound].resultIndex = resultIndex;
        _eventRounds[_currentRound].finished = true;
        _currentResultIndex = resultIndex;
        _currentRound = _currentRound + 1;
    }

    /// @dev Finalizes the result before doing a withdraw.
    function finalizeResult() {
        _status = Status.Collection;
        _eventRounds[_currentRound].finished = true

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
