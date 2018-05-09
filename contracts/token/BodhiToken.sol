pragma solidity ^0.4.23;

import './MintableToken.sol';

contract BodhiToken is MintableToken {
    // Token configurations
    string public constant name = "Bodhi Ethereum";
    string public constant symbol = "BOE";
    uint256 public constant decimals = 8;

    constructor() Ownable(msg.sender) public {
    }

    // 100 million BOE ever created
    function tokenTotalSupply() public pure returns (uint256) {
        return 100 * (10**6) * (10**decimals);
    }
}
