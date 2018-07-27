pragma solidity ^0.4.24;

contract ICentralizedOracle {
    function validateBet(address _bettor, uint8 _resultIndex, uint256 _amount) external returns (bool isValid);
    function recordBet(address _bettor, uint8 _resultIndex, uint256 _amount) external;
}
