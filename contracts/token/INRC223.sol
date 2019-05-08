pragma solidity ^0.5.8;

/// @title NRC223 interface
contract INRC223 {
    uint256 internal _totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount, bytes data);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @return Name of the token.
    function name() public view returns (string memory tokenName);

    /// @return Symbol of the token.
    function symbol() public view returns (string memory tokenSymbol);

    /// @return Decimals of the token.
    function decimals() public view returns (uint8 tokenDecimals);

    /// @return Total supply of tokens.
    function totalSupply() public view returns (uint256 supply) {
        return _totalSupply;
    }

    /// @dev Gets the balance of the specified address.
    /// @param owner Address to query the the balance of.
    /// @return Balance of the owner.
    function balanceOf(address owner) public view returns (uint256 balance);

    /// @dev Gets the approved amount between the owner and spender.
    /// @param owner Address of the approver.
    /// @param spender Address of the approvee.
    function allowance(address owner, address spender) public view returns (uint256 remaining);

    /// @dev Transfer tokens to a specified address.
    /// @param to The address to transfer to.
    /// @param amount The amount to be transferred.
    /// @return Transfer successful or not.
    function transfer(address to, uint256 amount) public returns (bool success);

    /// @dev Transfer tokens to a specified address with data. A receiver who is a contract must implement the NRC223Receiver interface.
    /// @param to The address to transfer to.
    /// @param amount The amount to be transferred.
    /// @param data Transaction metadata.
    /// @return Transfer successful or not.
    function transfer(address to, uint256 amount, bytes memory data) public returns (bool success);

    /// @dev Approves the spender to be able to withdraw up to the amount.
    /// @param spender Address of spender.
    /// @param amount Allowed amount the spender may transfer up to.
    /// @return Approve successful or not.
    function approve(address spender, uint256 amount) public returns (bool success);

    /// @dev Transfer tokens for a previously approved amount.
    /// @param from Address which tokens will be transferred from.
    /// @param to Address which tokens will be transferred to.
    /// @param amount Amount of tokens to be transferred.
    /// @return Transfer successful or not.
    function transferFrom(address from, address to, uint256 amount) public returns (bool success);
}
