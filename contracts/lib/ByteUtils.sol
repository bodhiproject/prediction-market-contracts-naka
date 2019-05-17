pragma solidity ^0.5.8;

library ByteUtils {
    /// @dev Slices a bytes array based on the starting offset and length.
    /// @param b The bytes array to slice.
    /// @param start The starting offset to slice.
    /// @param len The length of bytes to slice.
    /// @return The sliced bytes.
    function sliceBytes(
        bytes memory b,
        uint start,
        uint len)
        internal
        pure
        returns (bytes memory)
    {
        require(b.length >= start + len);

        bytes memory newBytes = new bytes(len);
        for (uint i = 0; i < len; i++) {
            newBytes[i] = b[start + i];
        }
        return newBytes;
    }

    function isEmpty(bytes32 b) internal pure returns (bool) {
        return b == 0x0;
    }
}
