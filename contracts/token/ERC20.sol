pragma solidity ^0.4.24;

/**
 * @title ERC20 interface
 * @dev Implements ERC20 Token Standard: https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 {
    uint256 public totalSupply;

    function transfer(address _to, uint256 _value) public returns (bool success);
    function approve(address _spender, uint256 _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
    function balanceOf(address _owner) public view returns (uint256 balance);
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
