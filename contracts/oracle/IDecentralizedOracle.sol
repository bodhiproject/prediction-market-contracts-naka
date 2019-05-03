pragma solidity ^0.5.8;

contract IDecentralizedOracle {
    uint8 public lastResultIndex;

    function validateVote(address _voter, uint8 _resultIndex, uint256 _amount) external returns (bool isValid);
    function recordVote(address _voter, uint8 _resultIndex, uint256 _amount) external returns (bool didHitThreshold, uint256 currentThreshold);
    function recordSetResult(uint8 _resultIndex, bool _emitResultSetEvent) external;
    function validateFinalize() external returns (bool isValid);
}
