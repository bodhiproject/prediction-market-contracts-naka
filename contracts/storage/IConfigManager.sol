pragma solidity ^0.5.8;

contract IConfigManager {
    function addToWhitelist(address contractAddress) external;
    function bodhiTokenAddress() external view returns (address);
    function eventFactoryAddress() external view returns (address);
    function eventEscrowAmount() external view returns (uint);
    function arbitrationLength() external view returns (uint[4]);
    function startingConsensusThreshold() external view returns (uint[4]);
    function thresholdPercentIncrease() external view returns (uint);
    function isWhitelisted(address contractAddress) external view returns (bool);
}
