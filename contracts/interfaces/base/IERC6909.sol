// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IERC6909 interface.
 * @author Cod3x
 */
interface IERC6909 {
    /// @dev Emitted when `by` transfers `amount` of token `id` from `from` to `to`.
    event Transfer(
        address by, address indexed from, address indexed to, uint256 indexed id, uint256 amount
    );

    /// @dev Emitted when `owner` enables or disables `operator` to manage all of their tokens.
    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    /// @dev Emitted when `owner` approves `spender` to use `amount` of `id` token.
    event Approval(
        address indexed owner, address indexed spender, uint256 indexed id, uint256 amount
    );

    /// @notice Returns the name for token `id`.
    function name(uint256 id) external view returns (string memory);

    /// @notice Returns the symbol for token `id`.
    function symbol(uint256 id) external view returns (string memory);

    /// @notice Returns the number of decimals for token `id`.
    /// @dev Returns 18 by default.
    function decimals(uint256 id) external view returns (uint8);

    /// @notice Returns the Uniform Resource Identifier (URI) for token `id`.
    function tokenURI(uint256 id) external view returns (string memory);

    /// @notice Returns the amount of token `id` owned by `owner`.
    function balanceOf(address owner, uint256 id) external view returns (uint256 amount);

    /// @notice Returns the amount of token `id` that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender, uint256 id)
        external
        view
        returns (uint256 amount);

    /// @notice Checks if a `spender` is approved by `owner` to manage all of their tokens.
    function isOperator(address owner, address spender) external view returns (bool status);

    /// @notice Transfers `amount` of token `id` from the caller to `to`.
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` of token `id` from `from` to `to`.
    function transferFrom(address from, address to, uint256 id, uint256 amount)
        external
        returns (bool);

    /// @notice Sets `amount` as the allowance of `spender` for the caller for token `id`.
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);

    /// @notice Sets whether `operator` is approved to manage the tokens of the caller.
    function setOperator(address operator, bool approved) external returns (bool);

    /// @notice Returns true if this contract implements the interface defined by `interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function scaledTotalSupply(uint256 id) external view returns (uint256);
}
