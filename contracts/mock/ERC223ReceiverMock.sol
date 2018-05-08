pragma solidity ^0.4.23;

import '../token/ERC223ReceivingContract.sol';

contract ERC223ReceiverMock is ERC223ReceivingContract {
    bool public tokenFallbackExec;

    function tokenFallback(address _from, uint _value, bytes _data) external {
        tokenFallbackExec = true;
    }
}
