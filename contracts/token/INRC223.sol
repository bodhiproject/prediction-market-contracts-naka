pragma solidity ^0.5.8;

/// @title NRC223 interface
contract INRC223 {
    function transfer(address to, uint256 amount, bytes memory data) public returns (bool success);
}
