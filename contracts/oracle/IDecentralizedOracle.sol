pragma solidity ^0.4.24;

contract IDecentralizedOracle {
    uint256 public consensusThreshold;

    function validateVote(address _voter, uint8 _resultIndex, uint256 _amount) external returns (bool isValid);
    function recordVote(address _voter, uint8 _resultIndex, uint256 _amount) external returns (bool didHitThreshold, uint256 currentThreshold);
    function recordSetResult(uint8 _resultIndex) external;
}
