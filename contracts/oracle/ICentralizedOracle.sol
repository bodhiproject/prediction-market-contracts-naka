pragma solidity ^0.5.8;

contract ICentralizedOracle {
    function validateBet(address _bettor, uint8 _resultIndex, uint256 _amount) external returns (bool isValid);
    function recordBet(address _bettor, uint8 _resultIndex, uint256 _amount) external;
    function validateSetResult(address _resultSetter, uint8 _resultIndex, uint256 _amount) external returns (bool isValid);
    function recordSetResult(address _resultSetter, uint8 _resultIndex, uint256 _amount) external;
}
