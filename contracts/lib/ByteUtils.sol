pragma solidity ^0.5.8;

library ByteUtils {
    /// @dev Slices a bytes array based on the starting offset and length.
    /// @param _bytes The bytes array to slice.
    /// @param _start The starting offset to slice.
    /// @param _length The length of bytes to slice.
    /// @return The sliced bytes.
    function sliceBytes(bytes memory _bytes, uint _start, uint _length) internal pure returns (bytes memory) {
        require(_bytes.length >= _start + _length);

        bytes memory newBytes = new bytes(_length);
        for (uint i = 0; i < _length; i++) {
            newBytes[i] = _bytes[_start + i];
        }
        return newBytes;
    }

    function isEmpty(bytes32 _source) internal pure returns (bool) {
        return _source == 0x0;
    }
}
