// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import "./Common.sol";
import "contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "contracts/protocol/libraries/math/WadRayMath.sol";
import "forge-std/console2.sol";

contract RayMathTest is Common {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    int256 internal constant RAYint = 1e27;
    int256 internal constant halfRAYint = RAYint / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function setUp() public {}

    function testRayMulInt(int256 a, int256 b) public pure {
        int256 delta = int256(2.4061596916800453e38 - halfRAYint);
        a = bound(a, -delta, delta);
        b = bound(b, -delta, delta);
        if (a >= 0 && b >= 0 || a < 0 && b < 0) {
            assertEq(
                int256(WadRayMath.rayMul(uint256(abs(a)), uint256(abs(b)))),
                WadRayMath.rayMulInt(a, b)
            );
        } else {
            assertEq(
                -int256(WadRayMath.rayMul(uint256(abs(a)), uint256(abs(b)))),
                WadRayMath.rayMulInt(a, b)
            );
        }
    }

    function testRayDivInt(int248 a, int248 b) public pure {
        vm.assume(b != 0);
        vm.assume(a != 0);
        if (a >= 0 && b >= 0 || a <= 0 && b <= 0) {
            vm.assume(abs(a) < uint256(type(int256).max) / RAY);
            assertEq(
                int256(WadRayMath.rayDiv(uint256(abs(a)), uint256(abs(b)))),
                WadRayMath.rayDivInt(a, b)
            );
        } else {
            int256 halfB = b / 2;
            vm.assume(abs(a) < (uint256(type(int256).max) - abs(halfB)) / RAY);
            assertEq(
                -int256(WadRayMath.rayDiv(uint256(abs(a)), uint256(abs(b)))),
                WadRayMath.rayDivInt(a, b)
            );
        }
    }

    // ----- helpers -----

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}
