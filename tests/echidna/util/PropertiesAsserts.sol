// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract PropertiesAsserts {
    event LogUint256(string, uint256);
    event LogAddress(string, address);
    event LogString(string);

    event AssertFail(string);
    event AssertEqFail(string);
    event AssertNeqFail(string);
    event AssertGteFail(string);
    event AssertGtFail(string);
    event AssertLteFail(string);
    event AssertLtFail(string);

    function assertWithMsg(bool b, string memory reason) internal {
        if (!b) {
            emit AssertFail(reason);
            assert(false);
        }
    }

    /// @notice asserts that a is equal to b. Violations are logged using reason.
    function assertEq(uint256 a, uint256 b, string memory reason) internal {
        if (a != b) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "!=", bStr, ", reason: ", reason);
            emit AssertEqFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertEq
    function assertEq(int256 a, int256 b, string memory reason) internal {
        if (a != b) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "!=", bStr, ", reason: ", reason);
            emit AssertEqFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is not equal to b. Violations are logged using reason.
    function assertNeq(uint256 a, uint256 b, string memory reason) internal {
        if (a == b) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "==", bStr, ", reason: ", reason);
            emit AssertNeqFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertNeq
    function assertNeq(int256 a, int256 b, string memory reason) internal {
        if (a == b) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "==", bStr, ", reason: ", reason);
            emit AssertNeqFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is greater than or equal to b. Violations are logged using reason.
    function assertGte(uint256 a, uint256 b, string memory reason) internal {
        if (!(a >= b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "<", bStr, " failed, reason: ", reason);
            emit AssertGteFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertGte
    function assertGte(int256 a, int256 b, string memory reason) internal {
        if (!(a >= b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "<", bStr, " failed, reason: ", reason);
            emit AssertGteFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is greater than b. Violations are logged using reason.
    function assertGt(uint256 a, uint256 b, string memory reason) internal {
        if (!(a > b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "<=", bStr, " failed, reason: ", reason);
            emit AssertGtFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertGt
    function assertGt(int256 a, int256 b, string memory reason) internal {
        if (!(a > b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, "<=", bStr, " failed, reason: ", reason);
            emit AssertGtFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is less than or equal to b. Violations are logged using reason.
    function assertLte(uint256 a, uint256 b, string memory reason) internal {
        if (!(a <= b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, ">", bStr, " failed, reason: ", reason);
            emit AssertLteFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertLte
    function assertLte(int256 a, int256 b, string memory reason) internal {
        if (!(a <= b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, ">", bStr, " failed, reason: ", reason);
            emit AssertLteFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is less than b. Violations are logged using reason.
    function assertLt(uint256 a, uint256 b, string memory reason) internal {
        if (!(a < b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, ">=", bStr, " failed, reason: ", reason);
            emit AssertLtFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice int256 version of assertLt
    function assertLt(int256 a, int256 b, string memory reason) internal {
        if (!(a < b)) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            bytes memory assertMsg =
                abi.encodePacked("Invalid: ", aStr, ">=", bStr, " failed, reason: ", reason);
            emit AssertLtFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is approximately equal to b. Violations are logged using reason.
    function assertEqApprox(uint256 a, uint256 b, uint256 approx, string memory reason) internal {
        emit LogUint256("abs(int(a - b))", abs(int256(a - b)));
        emit LogUint256("approx", approx);
        if (abs(int256(int256(a) - int256(b))) > approx) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            string memory diff = PropertiesLibString.toString(abs(int256(int256(a) - int256(b))));
            bytes memory assertMsg = abi.encodePacked(
                "Invalid: ", aStr, " to far from ", bStr, " by ", diff, " failed, reason: ", reason
            );
            emit AssertGtFail(string(assertMsg));
            assert(false);
        }
    }

    /// @notice asserts that a is approximately equal to b. Violations are logged using reason. Uses percentage for approximation.
    function assertEqApproxPct(uint256 a, uint256 b, uint256 approx, string memory reason)
        internal
    {
        emit LogUint256("abs(int(a - b))", abs(int256(int256(a) - int256(b))));
        emit LogUint256("approx", approx);

        uint256 maxDiff = (b * approx) / 10000;

        emit LogUint256("maxDiff", maxDiff);

        if (abs(int256(int256(a) - int256(b))) > maxDiff) {
            string memory aStr = PropertiesLibString.toString(a);
            string memory bStr = PropertiesLibString.toString(b);
            string memory diff = PropertiesLibString.toString(
                uint256(abs(int256(abs(int256(int256(a) - int256(b)))) - int256(maxDiff)))
            );
            bytes memory assertMsg = abi.encodePacked(
                "Invalid: ", aStr, " to far from ", bStr, " by ", diff, " failed, reason: ", reason
            );
            emit AssertGtFail(string(assertMsg));
            assert(false);
        }
    }

    function assertEqApproxPctRel(uint256 a, uint256 b, uint256 approx)
        internal
        view
        returns (bool)
    {
        uint256 maxDiff = (b * approx) / 10000;

        if (abs(int256(int256(a) - int256(b))) > maxDiff) {
            return false;
        }
        return true;
    }

    /// @notice calculates the absolute value of x.
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    /// @notice Clamps value to be between low and high, both inclusive
    function clampBetween(uint256 value, uint256 low, uint256 high) internal returns (uint256) {
        uint256 ans = low + (value % (high - low));
        string memory valueStr = PropertiesLibString.toString(value);
        string memory ansStr = PropertiesLibString.toString(ans);
        bytes memory message = abi.encodePacked("Clamping value ", valueStr, " to ", ansStr);
        emit LogString(string(message));
        return ans;
    }

    function clampBetweenProportional(uint8 value, uint256 low, uint256 high)
        internal
        returns (uint256)
    {
        uint256 ans = value * (high - low) / type(uint8).max + low;

        string memory valueStr = PropertiesLibString.toString(value);
        string memory ansStr = PropertiesLibString.toString(ans);
        bytes memory message =
            abi.encodePacked("Clamping proportional value ", valueStr, " to ", ansStr);
        emit LogString(string(message));
        return ans;
    }

    /// @notice Clamps value to be between low and high, both inclusive
    function clampBetweenEqual(uint256 value, uint256 low, uint256 high)
        internal
        returns (uint256)
    {
        uint256 ans = low + (value % (high - low + 1));
        string memory valueStr = PropertiesLibString.toString(value);
        string memory ansStr = PropertiesLibString.toString(ans);
        bytes memory message = abi.encodePacked("Clamping value ", valueStr, " to ", ansStr);
        emit LogString(string(message));
        return ans;
    }
}

/// @notice Efficient library for creating string representations of integers.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibString.sol)
/// @author Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol)
/// @dev Name of the library is modified to prevent collisions with contract-under-test uses of LibString
library PropertiesLibString {
    function toString(int256 value) internal pure returns (string memory str) {
        uint256 absValue = value >= 0 ? uint256(value) : uint256(-value);
        str = toString(absValue);

        if (value < 0) {
            str = string(abi.encodePacked("-", str));
        }
    }

    function toString(uint256 value) internal pure returns (string memory str) {
        /// @solidity memory-safe-assembly
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but we allocate 160 bytes
            // to keep the free memory pointer word aligned. We'll need 1 word for the length, 1 word for the
            // trailing zeros padding, and 3 other words for a max of 78 digits. In total: 5 * 32 = 160 bytes.
            let newFreeMemoryPointer := add(mload(0x40), 160)

            // Update the free memory pointer to avoid overriding our string.
            mstore(0x40, newFreeMemoryPointer)

            // Assign str to the end of the zone of newly allocated memory.
            str := sub(newFreeMemoryPointer, 32)

            // Clean the last word of memory it may not be overwritten.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                // Move the pointer 1 byte to the left.
                str := sub(str, 1)

                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))

                // Keep dividing temp until zero.
                temp := div(temp, 10)

                // prettier-ignore
                if iszero(temp) { break }
            }

            // Compute and cache the final total length of the string.
            let length := sub(end, str)

            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 32)

            // Store the string's length at the start of memory allocated for our string.
            mstore(str, length)
        }
    }

    function toString(address value) internal pure returns (string memory str) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(value)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
