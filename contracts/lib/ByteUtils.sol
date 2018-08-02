pragma solidity ^0.4.24;

library ByteUtils {
    /// @dev Slices a bytes array based on the starting offset and length.
    /// @param _bytes The bytes array to slice.
    /// @param _start The starting offset to slice.
    /// @param _length The length of bytes to slice.
    /// @return The sliced bytes.
    function sliceBytes(bytes _bytes, uint _start, uint _length) internal pure returns (bytes) {
        require(_bytes.length >= _start + _length);

        bytes memory newBytes = new bytes(_length);
        for (uint i = 0; i < _length; i++) {
            newBytes[i] = _bytes[_start + i];
        }
        return newBytes;
    }

    /// @dev Slices a bytes array and extracts a 32 byte uint based on the starting offset.
    /// @param _bytes The bytes array to slice.
    /// @param _start The starting offset to slice the uint.
    /// @return The sliced uint.
    function sliceUint(bytes _bytes, uint _start) internal pure returns (uint) {
        require(_bytes.length >= _start + 32);

        uint x;
        assembly {
            x := mload(add(_bytes, add(0x20, _start)))
        }
        return x;
    }

    /// @dev Slices a bytes array and extracts a 20 byte address based on the starting offset.
    /// @param _bytes The bytes array to slice.
    /// @param _start The starting offset to slice the address.
    /// @return The sliced address.
    function sliceAddress(bytes _bytes, uint _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20);

        address addr;
        assembly {
            addr := mload(add(_bytes, add(0x14, _start)))
        }
        return addr;
    }

    function isEmpty(bytes32 _source) internal pure returns (bool) {
        return _source == 0x0;
    }

    function bytesArrayToString(bytes32[10] _data) internal pure returns (string) {
        bytes memory allBytes = new bytes(10 * 32);
        uint length;
        for (uint i = 0; i < 10; i++) {
            for (uint j = 0; j < 32; j++) {
                byte char = _data[i][j];
                if (char != 0) {
                    allBytes[length] = char;
                    length++;
                }
            }
        }

        bytes memory trimmedBytes = new bytes(length + 1);
        for (i = 0; i < length; i++) {
            trimmedBytes[i] = allBytes[i];
        }

        return string(trimmedBytes);
    }

    function bytesToString(bytes32 _data) internal pure returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(_data) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }

        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }

        return string(bytesStringTrimmed);
    }
}
