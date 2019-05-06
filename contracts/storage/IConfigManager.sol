pragma solidity ^0.5.8;

contract IConfigManager {
    function addWhitelistContract(address contractAddress) external;
    function bodhiTokenAddress() external view returns (address);
    function eventEscrowAmount() external view returns (uint256);
    function arbitrationLength() external view returns (uint256);
    function arbitrationRewardPercentage() external view returns (uint8);
    function startingOracleThreshold() external view returns (uint256);
    function thresholdPercentIncrease() external view returns (uint256);
}
