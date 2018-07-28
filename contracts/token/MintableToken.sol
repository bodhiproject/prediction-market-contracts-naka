pragma solidity ^0.4.23;

import "./StandardToken.sol";
import "../lib/Ownable.sol";

contract MintableToken is StandardToken, Ownable {
    // Events
    event Mint(uint256 supply, address indexed to, uint256 amount);

    function tokenTotalSupply() public pure returns (uint256);

    /// @dev Allows the owner to mint new tokens
    /// @param _to Address to mint the tokens to
    /// @param _amount Amount of tokens that will be minted
    /// @return Boolean to signify successful minting
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        require(totalSupply.add(_amount) <= tokenTotalSupply());

        totalSupply = totalSupply.add(_amount);
        balances[_to] = balances[_to].add(_amount);

        emit Mint(totalSupply, _to, _amount);
        emit Transfer(address(0), _to, _amount);

        return true;
    }
}
