pragma solidity ^0.5.8;

contract IConfigManager {
    function addToWhitelist(address contractAddress) external;
    function calculateThreshold(uint length) external view returns (uint);
    function bodhiTokenAddress() external view returns (address);
    function eventFactoryAddress() external view returns (address);
    function eventEscrowAmount() external view returns (uint);
    function defaultArbitrationLength() external view returns (uint);
    function defaultStartingConsensusThreshold() external view returns (uint);
    function startingConsensusThreshold(uint length) external view returns (uint);
    function thresholdPercentIncrease() external view returns (uint);
    function isWhitelisted(address contractAddress) external view returns (bool);
}
