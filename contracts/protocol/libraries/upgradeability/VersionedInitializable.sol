// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.23;

/**
 * @title VersionedInitializable
 * @author Conclave, inspired by the OpenZeppelin Initializable contract
 * @notice Helper contract to implement initializer functions. To use it, replace
 * the constructor with a function that has the `initializer` modifier.
 * @dev WARNING: Unlike constructors, initializer functions must be manually
 * invoked. This applies both to deploying an Initializable contract, as well
 * as extending an Initializable contract via inheritance.
 * WARNING: When used with inheritance, manual care must be taken to not invoke
 * a parent initializer twice, or ensure that all initializers are idempotent,
 * because this is not dealt with automatically as with constructors.
 */
abstract contract VersionedInitializable {
    /**
     * @dev Indicates that the contract has been initialized through the `lastInitializedRevision` variable.
     */
    uint256 private lastInitializedRevision = 0;

    /**
     * @dev Indicates that the contract is in the process of being initialized through the `initializing` flag.
     */
    bool private initializing;

    /**
     * @dev Modifier to use in the initializer function of a contract.
     * @notice Ensures initialization can only happen once per revision.
     */
    modifier initializer() {
        uint256 revision = getRevision();
        require(
            initializing || isConstructor() || revision > lastInitializedRevision,
            "Contract instance has already been initialized"
        );

        bool isTopLevelCall = !initializing;
        if (isTopLevelCall) {
            initializing = true;
            lastInitializedRevision = revision;
        }

        _;

        if (isTopLevelCall) {
            initializing = false;
        }
    }

    /**
     * @notice Returns the revision number of the contract.
     * @dev Needs to be defined in the inherited class as a constant.
     * @return The revision number of the implementing contract.
     */
    function getRevision() internal pure virtual returns (uint256);

    /**
     * @notice Returns true if and only if the function is running in the constructor.
     * @dev Uses assembly to check if code size is zero, which is only true during construction.
     * @return True if the function is running in the constructor.
     */
    function isConstructor() private view returns (bool) {
        // extcodesize checks the size of the code stored in an address, and
        // address returns the current address. Since the code is still not
        // deployed when running a constructor, any checks on its code size will
        // yield zero, making it an effective way to detect if a contract is
        // under construction or not.
        uint256 cs;

        assembly {
            cs := extcodesize(address())
        }
        return cs == 0;
    }

    function _blockInitializing() internal {
        if (isConstructor()) {
            lastInitializedRevision = type(uint256).max;
        }
    }

    /**
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private ______gap;
}
