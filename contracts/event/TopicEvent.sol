pragma solidity ^0.4.24;

import "../BaseContract.sol";
import "../storage/IAddressManager.sol";
import "../oracle/IOracleFactory.sol";
import "../oracle/ICentralizedOracle.sol";
import "../oracle/IDecentralizedOracle.sol";
import "../token/ERC20.sol";
import "../token/ERC223ReceivingContract.sol";
import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/ByteUtils.sol";

contract TopicEvent is BaseContract, Ownable {
    using ByteUtils for bytes32;
    using SafeMath for uint256;

    /// @notice Status types
    ///         Betting: Bet with QTUM during this phase.
    ///         Arbitration: Vote with BOT during this phase.
    ///         Collection: Winners collect their winnings during this phase.
    enum Status {
        Betting,
        OracleVoting,
        Collection
    }

    // Amount of QTUM to be distributed to BOT winners
    uint8 public constant QTUM_PERCENTAGE = 1;

    Status public status = Status.Betting;
    bool public escrowWithdrawn;
    bytes32[10] public eventName;
    bytes32[11] public eventResults;
    uint256 public totalQtumValue;
    uint256 public totalBotValue;
    uint256 public escrowAmount;
    IAddressManager private addressManager;
    mapping(address => bool) public didWithdraw;

    // Events
    event FinalResultSet(
        uint16 indexed _version, 
        address indexed _eventAddress, 
        uint8 _finalResultIndex
    );
    event WinningsWithdrawn(
        uint16 indexed _version, 
        address indexed _winner, 
        uint256 _qtumTokenWon, 
        uint256 _botTokenWon
    );

    // Modifiers
    modifier inCollectionStatus() {
        require(status == Status.Collection);
        _;
    }

    /// @notice Creates new TopicEvent contract.
    /// @param _version The contract version.
    /// @param _owner The address of the owner.
    /// @param _centralizedOracle The address of the CentralizedOracle that will decide the result.
    /// @param _name The question or statement prediction broken down by multiple bytes32.
    /// @param _resultNames The possible results.
    /// @param _bettingStartTime The unix time when betting will start.
    /// @param _bettingEndTime The unix time when betting will end.
    /// @param _resultSettingStartTime The unix time when the CentralizedOracle can set the result.
    /// @param _resultSettingEndTime The unix time when anyone can set the result.
    /// @param _escrowAmount The amount of BOT deposited to create the Event.
    /// @param _addressManager The address of the AddressManager.
    constructor(
        uint16 _version,
        address _owner,
        address _centralizedOracle,
        bytes32[10] _name,
        bytes32[11] _resultNames,
        uint8 _numOfResults,
        uint256 _bettingStartTime,
        uint256 _bettingEndTime,
        uint256 _resultSettingStartTime,
        uint256 _resultSettingEndTime,
        address _addressManager)
        Ownable(_owner)
        public
        validAddress(_centralizedOracle)
        validAddress(_addressManager)
    {
        require(!_name[0].isEmpty());
        require(!_resultNames[0].isEmpty());
        require(!_resultNames[1].isEmpty());
        require(_bettingEndTime > _bettingStartTime);
        require(_resultSettingStartTime >= _bettingEndTime);
        require(_resultSettingEndTime > _resultSettingStartTime);

        version = _version;
        owner = _owner;
        eventName = _name;
        eventResults = _resultNames;
        numOfResults = _numOfResults;
        addressManager = IAddressManager(_addressManager);
        escrowAmount = addressManager.eventEscrowAmount();

        createCentralizedOracle(
            _centralizedOracle, _bettingStartTime, _bettingEndTime, _resultSettingStartTime, _resultSettingEndTime
        );
    }

    /// @notice Fallback function that rejects any amount sent to the contract.
    function() external payable {
        revert();
    }

    /// @dev Standard ERC223 function that will handle incoming token transfers.
    /// @param _from Token sender address.
    /// @param _value Amount of tokens.
    /// @param _data Transaction metadata.
    function tokenFallback(address _from, uint _value, bytes _data) external {
        // TODO: handle setResult call
        // TODO: handle vote call
    }

    /// @dev Places a bet.
    /// @param _centralizedOracle Address of the CentralizedOracle.
    /// @param _resultIndex Index of result to bet on.
    function bet(address _centralizedOracle, uint8 _resultIndex) external payable {
        bool isValid = ICentralizedOracle(_centralizedOracle).validateBet(msg.sender, _resultIndex, msg.value);
        assert(isValid);

        // Update balances
        balances[_resultIndex].totalBets = balances[_resultIndex].totalBets.add(msg.value);
        balances[_resultIndex].bets[msg.sender] = balances[_resultIndex].bets[msg.sender].add(msg.value);
        totalQtumValue = totalQtumValue.add(msg.value);

        ICentralizedOracle(_centralizedOracle).recordBet(msg.sender, _resultIndex, msg.value);
    }

    /// @dev Set the result as the result setter. tokenFallback should be calling this.
    /// @param _centralizedOracle Address of the CentralizedOracle contract.
    /// @param _resultSetter Entity who is setting the result.
    /// @param _resultIndex Index of the result to set.
    /// @param _consensusThreshold Threshold that the result setter is voting to validate the result.
    function setResult(
        address _centralizedOracle,
        address _resultSetter,
        uint8 _resultIndex,
        uint256 _consensusThreshold)
        external
    {
        require(status == Status.Betting);

        bool isValid = ICentralizedOracle(_centralizedOracle)
            .validateSetResult(_resultSetter, _resultIndex, _consensusThreshold);
        assert(isValid);

        // Update statuses and current result
        status = Status.OracleVoting;
        resultIndex = _resultIndex;

        // Update balances
        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(_consensusThreshold);
        balances[_resultIndex].votes[_resultSetter] = balances[_resultIndex].votes[_resultSetter]
            .add(_consensusThreshold);
        totalBotValue = totalBotValue.add(_consensusThreshold);

        ICentralizedOracle(_centralizedOracle).recordSetResult(_resultSetter, _resultIndex, _consensusThreshold);

        // Deploy DecentralizedOracle
        uint256 increment = addressManager.thresholdPercentIncrease().mul(_consensusThreshold).div(100);
        createDecentralizedOracle(_consensusThreshold.add(increment));
    }

    /// @dev Vote against the current result. tokenFallback should be calling this.
    /// @param _decentralizedOracle Address of the DecentralizedOracle contract.
    /// @param _voter Entity who is voting.
    /// @param _resultIndex Index of result to vote.
    /// @param _amount Amount of tokens used to vote.
    function vote(address _decentralizedOracle, address _voter, uint8 _resultIndex, uint256 _amount) external {
        bool isValid = IDecentralizedOracle(_decentralizedOracle).validateVote(_voter, _resultIndex, _amount);
        assert(isValid);

        // Update balances
        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(_amount);
        balances[_resultIndex].votes[_voter] = balances[_resultIndex].votes[_voter].add(_amount);
        totalBotValue = totalBotValue.add(_amount);

        // Set result and deploy new DecentralizedOracle if threshold hit
        bool didHitThreshold;
        uint256 currentThreshold;
        (didHitThreshold, currentThreshold) = IDecentralizedOracle(_decentralizedOracle)
            .recordVote(_voter, _resultIndex, _amount);
        if (didHitThreshold) {
            decentralizedOracleSetResult(_decentralizedOracle, _resultIndex, currentThreshold);
        }
    }

    /// @dev Finalizes the current result.
    /// @param _decentralizedOracle Address of the DecentralizedOracle contract.
    function finalizeResult(address _decentralizedOracle) external {
        require(status == Status.OracleVoting);
        bool isValid = IDecentralizedOracle(_decentralizedOracle).validateFinalize();
        assert(isValid);

        // Update status
        status = Status.Collection;

        // Record result in DecentralizedOracle
        uint8 lastResultIndex = IDecentralizedOracle(_decentralizedOracle).lastResultIndex();
        IDecentralizedOracle(_decentralizedOracle).recordSetResult(lastResultIndex, false);
 
        emit FinalResultSet(version, address(this), lastResultIndex);
    }

    /// @notice Allows winners of the Event to withdraw their winnings after the final result is set.
    function withdrawWinnings() external inCollectionStatus() {
        require(!didWithdraw[msg.sender]);

        didWithdraw[msg.sender] = true;

        uint256 botWon;
        uint256 qtumWon;
        (botWon, qtumWon) = calculateWinnings();

        if (qtumWon > 0) {
            msg.sender.transfer(qtumWon);
        }
        if (botWon > 0) {
            ERC20(addressManager.bodhiTokenAddress()).transfer(msg.sender, botWon);
        }

        emit WinningsWithdrawn(version, msg.sender, qtumWon, botWon);
    }

    /// @notice Allows the creator of the Event to withdraw the escrow amount.
    function withdrawEscrow() external onlyOwner() inCollectionStatus() {
        require(!escrowWithdrawn);

        escrowWithdrawn = true;

        addressManager.withdrawEscrow(msg.sender, escrowAmount);
    }

    /// @notice Gets the final result index and flag indicating if the result is final.
    /// @return The result index and finalized bool.
    function getFinalResult() public view returns (uint8, bool) {
        return (resultIndex, status == Status.Collection);
    }

    /// @notice Calculates the BOT and QTUM tokens won based on the sender's contributions.
    /// @return The amount of BOT and QTUM tokens won.
    function calculateWinnings() public view inCollectionStatus() returns (uint256, uint256) {
        uint256 votes = balances[resultIndex].votes[msg.sender];
        uint256 bets = balances[resultIndex].bets[msg.sender];

        // Calculate Qtum reward total
        uint256 losersTotal = 0;
        for (uint8 i = 0; i < numOfResults; i++) {
            if (i != resultIndex) {
                losersTotal = losersTotal.add(balances[i].totalBets);
            }
        }
        uint256 rewardQtum = uint256(QTUM_PERCENTAGE).mul(losersTotal).div(100);
        losersTotal = losersTotal.sub(rewardQtum);

        // Calculate QTUM winnings
        uint256 winnersTotal;
        uint256 qtumWon = 0;
        if (bets > 0) {
            winnersTotal = balances[resultIndex].totalBets;
            qtumWon = bets.mul(losersTotal).div(winnersTotal).add(bets);
        }

        // Calculate BOT winnings
        uint256 botWon = 0;
        if (votes > 0) {
            winnersTotal = balances[resultIndex].totalVotes;
            losersTotal = 0;
            for (i = 0; i < numOfResults; i++) {
                if (i != resultIndex) {
                    losersTotal = losersTotal.add(balances[i].totalVotes);
                }
            }
            botWon = votes.mul(losersTotal).div(winnersTotal).add(votes);
            uint256 rewardWon = votes.mul(rewardQtum).div(winnersTotal);
            qtumWon = qtumWon.add(rewardWon);
        }

        return (botWon, qtumWon);
    }

    function createCentralizedOracle(
        address _centralizedOracle, 
        uint256 _bettingStartTime,
        uint256 _bettingEndTime,
        uint256 _resultSettingStartTime,
        uint256 _resultSettingEndTime)
        private
    {
        address oracleFactory = addressManager.oracleFactoryVersionToAddress(version);
        address newOracle = IOracleFactory(oracleFactory).createCentralizedOracle(address(this), 
            numOfResults, _centralizedOracle, _bettingStartTime, _bettingEndTime, _resultSettingStartTime, 
            _resultSettingEndTime, addressManager.startingOracleThreshold());
        assert(newOracle != address(0));
    }

    function createDecentralizedOracle(uint256 _consensusThreshold) private {
        address oracleFactory = addressManager.oracleFactoryVersionToAddress(version);
        uint256 arbitrationLength = addressManager.arbitrationLength();
        address newOracle = IOracleFactory(oracleFactory).createDecentralizedOracle(address(this), numOfResults, 
            resultIndex, block.timestamp.add(arbitrationLength), _consensusThreshold);
        assert(newOracle != address(0));
    }

    /// @dev Sets the result of the DecentralizedOracle and creates a new one.
    /// @param _decentralizedOracle Address of the DecentralizedOracle contract.
    /// @param _resultIndex Index of the result to set.
    /// @param _currentConsensusThreshold The current consensus threshold for the DecentralizedOracle.
    function decentralizedOracleSetResult(
        address _decentralizedOracle,
        uint8 _resultIndex,
        uint256 _currentConsensusThreshold)
        private
    {
        // Update statuses
        status = Status.OracleVoting;
        resultIndex = _resultIndex;

        // Record result in DecentralizedOracle
        IDecentralizedOracle(_decentralizedOracle).recordSetResult(_resultIndex, true);

        // Deploy new DecentralizedOracle
        uint256 increment = addressManager.thresholdPercentIncrease().mul(_currentConsensusThreshold).div(100);
        createDecentralizedOracle(_currentConsensusThreshold.add(increment));
    }
}
