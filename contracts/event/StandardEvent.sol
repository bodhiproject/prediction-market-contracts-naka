pragma solidity ^0.4.24;

import "../BaseContract.sol";
import "../storage/IAddressManager.sol";
import "../oracle/IOracleFactory.sol";
import "../oracle/ICentralizedOracle.sol";
import "../oracle/IDecentralizedOracle.sol";
import "../token/ERC223.sol";
import "../token/ERC223ReceivingContract.sol";
import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/ByteUtils.sol";
import "bytes/BytesLib.sol";

contract StandardEvent is BaseContract, Ownable {
    using BytesLib for bytes;
    using ByteUtils for bytes32;
    using SafeMath for uint256;

    /// @notice Status types
    ///         Betting: Bet with the betting token during this phase.
    ///         OracleVoting: Arbitrate with the arbitration token during this phase.
    ///         Collection: Winners collect their winnings during this phase.
    enum Status {
        Betting,
        OracleVoting,
        Collection
    }

    // Percentage of loser's betting tokens to be distributed to winners who particated in arbitration
    uint8 public constant ARBITRATION_REWARD_PERCENTAGE = 1;

    Status public status = Status.Betting;
    bool public escrowWithdrawn;
    bytes32[10] public eventName;
    bytes32[11] public eventResults;
    uint256 public totalBetTokens;
    uint256 public totalArbitrationTokens;
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
        uint256 _betTokensAmount,
        uint256 _arbitrationTokensAmount
    );

    // Modifiers
    modifier inCollectionStatus() {
        require(status == Status.Collection);
        _;
    }

    /// @notice Creates new StandardEvent contract.
    /// @param _version The contract version.
    /// @param _owner The address of the owner.
    /// @param _resultSetter The address of the CentralizedOracle that will decide the result.
    /// @param _name The question or statement prediction broken down by multiple bytes32.
    /// @param _resultNames The possible results.
    /// @param _bettingStartTime The unix time when betting will start.
    /// @param _bettingEndTime The unix time when betting will end.
    /// @param _resultSettingStartTime The unix time when the CentralizedOracle can set the result.
    /// @param _resultSettingEndTime The unix time when anyone can set the result.
    /// @param _addressManager The address of the AddressManager.
    constructor(
        uint16 _version,
        address _owner,
        address _resultSetter,
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
        validAddress(_resultSetter)
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
            _resultSetter, _bettingStartTime, _bettingEndTime, _resultSettingStartTime, _resultSettingEndTime
        );
    }

    /// @notice Fallback function that rejects any amount sent to the contract.
    function() external payable {
        revert();
    }

    /// @dev Standard ERC223 function that will handle incoming token transfers.
    /// @param _from Token sender address.
    /// @param _value Amount of tokens.
    /// @param _data The message data. First 4 bytes is function hash & rest is function params.
    function tokenFallback(address _from, uint _value, bytes _data) external {
        bytes memory functionId = _data.slice(0, 4);
        bytes memory setResultFunc = hex"65f4ced1";
        bytes memory voteFunc = hex"6f02d1fb";

        address centralizedOracle = _data.toAddress(4);
        address resultSetter = _data.toAddress(24);
        uint8 resultIndex = uint8(_data.toUint(44));

        if (functionId.equal(setResultFunc)) {
            setResult(centralizedOracle, resultSetter, resultIndex, _value);
        } else if (functionId.equal(voteFunc)) {
            vote(centralizedOracle, resultSetter, resultIndex, _value);
        } else {
            revert("Unhandled function in tokenFallback");
        }
    }

    /// @notice Places a bet.
    /// @param _centralizedOracle Address of the CentralizedOracle.
    /// @param _resultIndex Index of result to bet on.
    function bet(address _centralizedOracle, uint8 _resultIndex) external payable {
        bool isValid = ICentralizedOracle(_centralizedOracle).validateBet(msg.sender, _resultIndex, msg.value);
        assert(isValid);

        // Update balances
        balances[_resultIndex].totalBets = balances[_resultIndex].totalBets.add(msg.value);
        balances[_resultIndex].bets[msg.sender] = balances[_resultIndex].bets[msg.sender].add(msg.value);
        totalBetTokens = totalBetTokens.add(msg.value);

        ICentralizedOracle(_centralizedOracle).recordBet(msg.sender, _resultIndex, msg.value);
    }

    /// @notice Finalizes the current result.
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

        uint256 arbitrationTokenAmount;
        uint256 betTokenAmount;
        (arbitrationTokenAmount, betTokenAmount) = calculateWinnings();

        if (betTokenAmount > 0) {
            msg.sender.transfer(betTokenAmount);
        }
        if (arbitrationTokenAmount > 0) {
            ERC223(addressManager.bodhiTokenAddress()).transfer(msg.sender, arbitrationTokenAmount);
        }

        emit WinningsWithdrawn(version, msg.sender, betTokenAmount, arbitrationTokenAmount);
    }

    /// @notice Allows the creator of the Event to withdraw the escrow amount.
    function withdrawEscrow() external onlyOwner() inCollectionStatus() {
        require(!escrowWithdrawn);

        escrowWithdrawn = true;

        addressManager.withdrawEscrow(msg.sender, escrowAmount);
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
        private
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
        totalArbitrationTokens = totalArbitrationTokens.add(_consensusThreshold);

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
    function vote(address _decentralizedOracle, address _voter, uint8 _resultIndex, uint256 _amount) private {
        bool isValid = IDecentralizedOracle(_decentralizedOracle).validateVote(_voter, _resultIndex, _amount);
        assert(isValid);

        // Update balances
        balances[_resultIndex].totalVotes = balances[_resultIndex].totalVotes.add(_amount);
        balances[_resultIndex].votes[_voter] = balances[_resultIndex].votes[_voter].add(_amount);
        totalArbitrationTokens = totalArbitrationTokens.add(_amount);

        // Set result and deploy new DecentralizedOracle if threshold hit
        bool didHitThreshold;
        uint256 currentThreshold;
        (didHitThreshold, currentThreshold) = IDecentralizedOracle(_decentralizedOracle)
            .recordVote(_voter, _resultIndex, _amount);
        if (didHitThreshold) {
            decentralizedOracleSetResult(_decentralizedOracle, _resultIndex, currentThreshold);
        }
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
