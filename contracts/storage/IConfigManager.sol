pragma solidity ^0.5.8;

contract IConfigManager {
    function addToWhitelist(address contractAddress) external;
    function bodhiTokenAddress() external view returns (address);
    function eventFactoryAddress() external view returns (address);
    function eventEscrowAmount() external view returns (uint256);
    function startingOracleThreshold() external view returns (uint256);
    function thresholdPercentIncrease() external view returns (uint256);
    function isWhitelisted(address contractAddress) external view returns (bool);
}
