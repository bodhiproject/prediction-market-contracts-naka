pragma solidity ^0.5.8;

contract IEventFactory {
    function withdrawEscrow() external;
    function didWithdraw() external view returns (bool);
}
