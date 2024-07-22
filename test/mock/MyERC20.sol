// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MyERC20
/// @notice This contract implements an ERC20 token with additional functionalities.
/// @dev This contract follows the ERC20 standard and allows the creation and transfer of tokens.
contract MyERC20 is ERC20, Ownable {

    /// @notice Creates a new instance of the TokenA contract.
    /// @dev Assigns the initial owner of the contract.
    /// @param initialOwner The address of the initial owner.
    constructor(string memory name, string memory symbol, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {}

    /// @notice Mints new tokens.
    /// @dev Only the contract owner can mint new tokens.
    /// @param to The address that will receive the new tokens.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}