pragma solidity ^0.4.23;

import '../token/StandardToken.sol';

contract StandardTokenMock is StandardToken {
    constructor(address _initialAccount, uint256 _initialBalance) public {
        balances[_initialAccount] = _initialBalance;
        totalSupply = _initialBalance;
    }
}
