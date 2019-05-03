pragma solidity ^0.5.8;

contract IConfigManager {
    function eventEscrowAmount() external view returns (uint256);
    function arbitrationLength() external view returns (uint256);
    function startingOracleThreshold() external view returns (uint256);
    function thresholdPercentIncrease() external view returns (uint256);
}
