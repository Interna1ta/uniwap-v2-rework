// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

/// @title Re-implement UniswapV2Factory
/// @notice This contract is used to create new UniswapV2Pair contracts.
/// @dev This contract allows for the creation of new UniswapV2Pair contracts and keeps track of all created pairs.
contract UniswapV2Factory is IUniswapV2Factory {
    address public s_feeTo;
    address public s_feeToSetter;

    mapping(address => mapping(address => address)) public s_getPair;
    address[] public s_allPairs;

    /* ========== ERRORS ========== */

    error UniswapV2Factory__IdenticalAddresses();
    error UniswapV2Factory__ZeroAddress();
    error UniswapV2Factory__PairExists();
    error UniswapV2Factory__Forbidden();

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor for the UniswapV2Factory contract.
    /// @dev Sets the feeToSetter address.
    /// @param _feeToSetter The address that will have the rights to set the feeTo address.
    constructor(address _feeToSetter) {
        s_feeToSetter = _feeToSetter;
    }

    /* ========== VIEWS ========== */

    /// @notice Returns the number of all pairs created by the factory.
    /// @dev This function is a view, so it doesn't modify the state and can be freely called.
    /// @return The length of the s_allPairs array.
    function allPairsLength() external view returns (uint) {
        return s_allPairs.length;
    }

    /// @notice Creates a new UniswapV2 token pair.
    /// @dev Ensures that the tokens are not the same and that the pair does not already exist.
    /// @param _tokenA The address of the first token.
    /// @param _tokenB The address of the second token.
    /// @return pair The address of the created pair.
    function createPair(
        address _tokenA,
        address _tokenB
    ) external returns (address pair) {
        if (_tokenA == _tokenB) {
            revert UniswapV2Factory__IdenticalAddresses();
        }
        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        if (token0 == address(0)) {
            revert UniswapV2Factory__ZeroAddress();
        }
        if (s_getPair[token0][token1] != address(0)) {
            revert UniswapV2Factory__PairExists(); // single check is sufficient
        }
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        s_getPair[token0][token1] = pair;
        s_getPair[token1][token0] = pair; // populate mapping in the reverse direction
        s_allPairs.push(pair);
        emit PairCreated(token0, token1, pair, s_allPairs.length);
    }

    /// @notice Sets the address to which protocol fees will be sent.
    /// @dev Only the current `feeToSetter` can call this function.
    /// @param _feeTo The address to which protocol fees will be sent.
    function setFeeTo(address _feeTo) external {
        if (msg.sender != s_feeToSetter) {
            revert UniswapV2Factory__Forbidden();
        }
        s_feeTo = _feeTo;
    }

    /// @notice Sets the address that has the right to change the `feeTo` address.
    /// @dev Only the current `feeToSetter` can call this function.
    /// @param _feeToSetter The address that will have the right to change the `feeTo` address.
    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != s_feeToSetter) {
            revert UniswapV2Factory__Forbidden();
        }
        s_feeToSetter = _feeToSetter;
    }

    /* ========== MISSING ========== */

    function allPairs(uint _index) external view returns (address pair) {
        return s_allPairs[_index];
    }

    function feeTo() external view returns (address) {
        return s_feeTo;
    }

    function feeToSetter() external view returns (address) {
        return s_feeToSetter;
    }

    function getPair(address _tokenA, address _tokenB) external view returns (address pair) {
        return s_getPair[_tokenA][_tokenB];
    }
}
