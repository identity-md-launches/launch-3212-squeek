// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Squeek (SQK)
/// @notice A fixed supply ERC-20 with 18 decimals and no administrative privileges.
contract Squeek is ERC20 {
    /// @notice The entire supply in base units: one billion SQK, each with 18 decimals.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the caller deploying this contract.
    /// @dev During a factory launch, msg.sender is the factory, which handles distribution.
    constructor() ERC20("Squeek", "SQK") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
