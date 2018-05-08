pragma solidity ^0.4.23;

import './ERC20.sol';

contract ERC223 is ERC20 {
    function transfer(address _to, uint256 _value, bytes _data) public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
}
