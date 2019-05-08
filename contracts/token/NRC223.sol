pragma solidity ^0.5.8;

import "./INRC223.sol";
import "./NRC223Receiver.sol";
import "../lib/SafeMath.sol";

contract NRC223 is INRC223 {
    using SafeMath for uint256;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowed;

    modifier validAddress(address _address) {
        require(_address != address(0), "Requires valid address.");
        _;
    }

    function name() public view returns (string memory tokenName) {
        return _name;
    }

    function symbol() public view returns (string memory tokenSymbol) {
        return _symbol;
    }

    function decimals() public view returns (uint8 tokenDecimals) {
        return _decimals;
    }

    function balanceOf(address owner) public view returns (uint256 balance) {
        return _balances[owner];
    }

    function allowance(address owner, address spender) public view returns (uint256 remaining) {
        return _allowed[owner][spender];
    }

    function transfer(address to, uint256 amount) public validAddress(to) returns (bool success) {
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _balances[to] = _balances[to].add(amount);

        bytes memory empty;
        emit Transfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount, empty);
        return true;
    }

    function transfer(address to, uint256 amount, bytes memory data) public validAddress(to) returns (bool success) {
        uint codeLength;
        assembly {
            // Retrieve the size of the code on target address, this needs assembly
            codeLength := extcodesize(to)
        }

        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _balances[to] = _balances[to].add(amount);

        // Call tokenFallback() if 'to' is a contract. Rejects if not implemented.
        if (codeLength > 0) {
            NRC223Receiver(to).tokenFallback(msg.sender, amount, data);
        }

        emit Transfer(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount, data);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool success) {
        // To change the approve amount you first have to reduce the addresses'
        //  allowance to zero by calling `approve(spender, 0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require((amount == 0) || (_allowed[msg.sender][spender] == 0), "Requires amount to be 0 or current allowance to be 0");

        _allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public validAddress(to) returns (bool success) {
        uint256 _allowance = _allowed[from][msg.sender];
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount);
        _allowed[from][msg.sender] = _allowance.sub(amount);

        bytes memory empty;
        emit Transfer(from, to, amount);
        emit Transfer(from, to, amount, empty);
        return true;
    }
}
