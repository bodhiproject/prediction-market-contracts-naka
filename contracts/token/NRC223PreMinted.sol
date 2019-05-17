pragma solidity ^0.5.4;

import "./NRC223.sol";
import "../lib/Ownable.sol";

contract NRC223PreMinted is NRC223, Ownable {
    /**
     * @dev Creates the token and mints the entire token supply to the owner.
     * @param name Name of the token.
     * @param symbol Symbol of the token.
     * @param decimals Decimals of the token.
     * @param totalSupply Total supply of all the tokens.
     * @param owner Owner of all the tokens.
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply,
        address owner)
        Ownable(owner)
        public
        validAddress(owner)
    {
        require(bytes(name).length > 0, "name cannot be empty.");
        require(bytes(symbol).length > 0, "symbol cannot be empty.");
        require(totalSupply > 0, "totalSupply must be greater than 0.");

        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _totalSupply = totalSupply;
        _balances[owner] = totalSupply;

        bytes memory empty;
        emit Transfer(address(0), owner, totalSupply);
        emit Transfer(address(0), owner, totalSupply, empty);
    }
}
