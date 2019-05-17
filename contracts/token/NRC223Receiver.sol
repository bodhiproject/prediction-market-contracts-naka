pragma solidity ^0.5.8;

/// @title NRC223 receiver interface
contract NRC223Receiver { 
    function tokenFallback(address from, uint amount, bytes calldata data) external;
}
