// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title IERC6909 interface.
 * @author Cod3x
 */
interface IERC6909 {
    /**
     * @dev Emitted when tokens are transferred from one account to another
     * @param by The address that initiated the transfer
     * @param from The address tokens are transferred from
     * @param to The address tokens are transferred to
     * @param id The token identifier
     * @param amount The amount of tokens transferred
     */
    event Transfer(
        address by, address indexed from, address indexed to, uint256 indexed id, uint256 amount
    );

    /**
     * @dev Emitted when an operator is set or unset for an owner
     * @param owner The address of the token owner
     * @param operator The address being granted or revoked operator status
     * @param approved True if the operator is approved, false to revoke approval
     */
    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Emitted when an approval is set for a specific token
     * @param owner The address of the token owner
     * @param spender The address of the spender being approved
     * @param id The token identifier
     * @param amount The amount of tokens approved
     */
    event Approval(
        address indexed owner, address indexed spender, uint256 indexed id, uint256 amount
    );

    function name(uint256 id) external view returns (string memory);

    function symbol(uint256 id) external view returns (string memory);

    function decimals(uint256 id) external view returns (uint8);

    function tokenURI(uint256 id) external view returns (string memory);

    function balanceOf(address owner, uint256 id) external view returns (uint256 amount);

    function allowance(address owner, address spender, uint256 id)
        external
        view
        returns (uint256 amount);

    function isOperator(address owner, address spender) external view returns (bool status);

    function transfer(address to, uint256 id, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 id, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 id, uint256 amount) external returns (bool);

    function setOperator(address operator, bool approved) external returns (bool);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
