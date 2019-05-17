pragma solidity ^0.5.8;

contract IEventFactory {
    function withdrawEscrow() external returns (uint);
    function didWithdraw() external view returns (bool);
}
