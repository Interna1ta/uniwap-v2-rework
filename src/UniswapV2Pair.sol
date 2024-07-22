// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib as Math} from "solady/src/utils/FixedPointMathLib.sol";

import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

/// @title Re-implement UniswapV2Pair (which inherits from ERC20)
/// @notice Automated market maker (AMM) pair contract for Uniswap V2
/// @dev This contract manages liquidity pools, token swaps, and reserves for Uniswap pairs.
contract UniswapV2Pair is UniswapV2ERC20, ReentrancyGuard, IUniswapV2Pair {
    using Math for uint256;
    using UQ112x112 for uint224;

    /* ========== ERRORS ========== */

    error UniswapV2Pair__EXPIRED();
    error UniswapV2Pair__FORBIDDEN();
    error UniswapV2Pair__INSUFFICIENT_LIQUIDITY_MINTED();
    error UniswapV2Pair__INSUFFICIENT_LIQUIDITY_BURNED();
    error UniswapV2Pair__INSUFFICIENT_OUTPUT_AMOUNT();
    error UniswapV2Pair__INSUFFICIENT_LIQUIDITY();
    error UniswapV2Pair__INVALID_TO();
    error UniswapV2Pair__INVALID_TOKEN();
    error UniswapV2Pair__INSUFFICIENT_INPUT_AMOUNT();
    error UniswapV2Pair__K();
    error UniswapV2Pair__INSUFFICIENT_B_AMOUNT();
    error UniswapV2Pair__INSUFFICIENT_A_AMOUNT();
    error UniswapV2Pair__A_AMOUNT_EXCEEDS_DESIRED_AMOUNT();
    error UniswapV2Pair__EXCESSIVE_INPUT_AMOUNT();

    /* ========== VARIABLES ========== */

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    string private s_name;
    string private s_symbol;

    address public immutable i_factory;
    address public s_token0;
    address public s_token1;

    uint112 private s_reserve0; // uses single storage slot, accessible via getReserves
    uint112 private s_reserve1; // uses single storage slot, accessible via getReserves
    uint32 private s_blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public s_price0CumulativeLast;
    uint256 public s_price1CumulativeLast;
    uint256 public s_kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    /* ========== MODIFIERS ========== */

    modifier ensure(uint256 _deadline) {
        if (_deadline < block.timestamp) {
            revert UniswapV2Pair__EXPIRED();
        }
        _;
    }

    /* ========== CONSTRUCTOR AND INITIALIZE ========== */

    constructor() {
        i_factory = msg.sender;
    }

    /**
     * @notice Initializes the pair contract with two token addresses.
     * @dev This function is called once by the factory at the time of deployment to set the token pair.
     * @param _token0 Address of the first token in the pair.
     * @param _token1 Address of the second token in the pair.
     */
    function initialize(address _token0, address _token1) external {
        if (msg.sender != i_factory) {
            revert UniswapV2Pair__FORBIDDEN(); // sufficient check
        }
        s_token0 = _token0;
        s_token1 = _token1;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Adds liquidity to the Uniswap pair.
    /// @param _amountADesired The desired amount of token0 to add as liquidity.
    /// @param _amountBDesired The desired amount of token1 to add as liquidity.
    /// @param _amountAMin Minimum amount of token0 to add as liquidity.
    /// @param _amountBMin Minimum amount of token1 to add as liquidity.
    /// @param _to Recipient address receiving the liquidity tokens.
    /// @param _deadline Deadline timestamp for the transaction.
    /// @return amountA The actual amount of token0 added.
    /// @return amountB The actual amount of token1 added.
    /// @return liquidity The amount of liquidity tokens minted.
    function addLiquidity(
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    )
        external
        ensure(_deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            _amountADesired,
            _amountBDesired,
            _amountAMin,
            _amountBMin
        );
        TransferHelper.safeTransferFrom(
            s_token0,
            msg.sender,
            address(this),
            amountA
        );
        TransferHelper.safeTransferFrom(
            s_token1,
            msg.sender,
            address(this),
            amountB
        );
        liquidity = _mint(_to);
    }

    /**
     * @notice Removes liquidity to the Uniswap pair.
     * @dev The caller must have approved the contract to spend the liquidity tokens on their behalf.
     * @param _liquidity The amount of liquidity tokens to burn and convert back into underlying tokens.
     * @param _amountAMin The minimum amount of token0 (from the pair) to receive.
     * @param _amountBMin The minimum amount of token1 (from the pair) to receive.
     * @param _to Address to send the underlying tokens to.
     * @param _deadline Latest timestamp by which the transaction must be included to effect the removal.
     * @return amount0 The amount of token0 received.
     * @return amount1 The amount of token1 received.
     */
    function removeLiquidity(
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) public ensure(_deadline) returns (uint256 amount0, uint256 amount1) {
        // send liquidity to pair
        TransferHelper.safeTransferFrom(
            address(this),
            msg.sender,
            address(this),
            _liquidity
        );
        (amount0, amount1) = _burn(_to);
        if (amount0 < _amountAMin) {
            revert UniswapV2Pair__INSUFFICIENT_A_AMOUNT();
        }
        if (amount1 < _amountBMin) {
            revert UniswapV2Pair__INSUFFICIENT_B_AMOUNT();
        }
    }

    /**
     * @notice Swaps an amount of tokens for an exact output, capped by a minimum output limit.
     * @dev The caller must have approved the contract to spend the input tokens on their behalf.
     * @param _amountIn The exact amount of input tokens to swap.
     * @param _tokenIn Address of the input token.
     * @param _amountOutMin The minimum amount of output tokens to receive.
     * @param _tokenOut Address of the output token.
     * @param _to Address to send the output tokens to.
     * @param _deadline Latest timestamp by which the transaction must be included to effect the swap.
     */
    function swapExactTokensForTokens(
        uint256 _amountIn,
        address _tokenIn,
        uint256 _amountOutMin,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        if (_tokenIn != s_token0 && _tokenIn != s_token1) {
            revert UniswapV2Pair__INVALID_TOKEN();
        }
        if (_tokenOut != s_token0 && _tokenOut != s_token1) {
            revert UniswapV2Pair__INVALID_TOKEN();
        }

        (uint256 reserve0, uint256 reserve1, ) = getReserves();
        uint256 amountOut;

        if (_tokenIn == s_token0) {
            amountOut = getAmountOut(_amountIn, reserve0, reserve1);
        } else {
            amountOut = getAmountOut(_amountIn, reserve1, reserve0);
        }

        if (amountOut < _amountOutMin) {
            revert UniswapV2Pair__INSUFFICIENT_OUTPUT_AMOUNT();
        }
        TransferHelper.safeTransferFrom(
            _tokenIn,
            msg.sender,
            address(this),
            _amountIn
        );
        if (_tokenIn == s_token0) {
            _swap(0, amountOut, _to);
        } else {
            _swap(amountOut, 0, _to);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Mints liquidity tokens and assigns them to the specified recipient, based on the deposited amounts of token0 and token1.
     * @dev Ensures fee calculation and updates reserves accordingly.
     * @param _to Address to receive the minted liquidity tokens.
     * @return liquidity The amount of liquidity tokens minted.
     */
    function _mint(
        address _to
    ) internal nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint256 balance0 = UniswapV2ERC20(s_token0).balanceOf(address(this));
        uint256 balance1 = UniswapV2ERC20(s_token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            super._mint(address(0), MINIMUM_LIQUIDITY); // permanently nonReentrant the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }
        if (liquidity <= 0) {
            revert UniswapV2Pair__INSUFFICIENT_LIQUIDITY_MINTED();
        }
        super._mint(_to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) s_kLast = uint256(s_reserve0) * s_reserve1; // s_reserve0 and s_reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Burns liquidity tokens held by the caller and returns the equivalent amounts of token0 and token1.
     * @dev Ensures fee calculation and updates reserves accordingly.
     * @param _to Address to receive the underlying tokens.
     * @return amount0 The amount of token0 received.
     * @return amount1 The amount of token1 received.
     */
    function _burn(
        address _to
    ) internal nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        address token0 = s_token0; // gas savings
        address token1 = s_token1; // gas savings
        uint256 balance0 = UniswapV2ERC20(token0).balanceOf(address(this));
        uint256 balance1 = UniswapV2ERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = (liquidity * balance0) / totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / totalSupply; // using balances ensures pro-rata distribution
        if (!(amount0 > 0 && amount1 > 0)) {
            revert UniswapV2Pair__INSUFFICIENT_LIQUIDITY_BURNED();
        }
        super._burn(address(this), liquidity);
        TransferHelper.safeTransfer(token0, _to, amount0);
        TransferHelper.safeTransfer(token1, _to, amount1);
        balance0 = UniswapV2ERC20(token0).balanceOf(address(this));
        balance1 = UniswapV2ERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) s_kLast = uint256(s_reserve0) * s_reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, _to);
    }

    /**
     * @notice Swaps input tokens for output tokens, ensuring sufficient liquidity and fee calculation.
     * @dev Ensures the swap doesn't exceed reserves and performs safety checks.
     * @param _amount0Out Amount of token0 to send out in the swap.
     * @param _amount1Out Amount of token1 to send out in the swap.
     * @param _to Address to receive the swapped tokens.
     */
    function _swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to
    ) internal nonReentrant {
        if (!(_amount0Out > 0 || _amount1Out > 0)) {
            revert UniswapV2Pair__INSUFFICIENT_OUTPUT_AMOUNT();
        }
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        if (!(_amount0Out < _reserve0 && _amount1Out < _reserve1)) {
            revert UniswapV2Pair__INSUFFICIENT_LIQUIDITY();
        }

        uint256 balance0;
        uint256 balance1;

        {
            // scope for token{0,1}, avoids stack too deep errors
            address token0 = s_token0;
            address token1 = s_token1;
            if (_to == token0 || _to == token1) {
                revert UniswapV2Pair__INVALID_TO();
            }
            if (_amount0Out > 0)
                TransferHelper.safeTransfer(token0, _to, _amount0Out); // optimistically transfer tokens
            if (_amount1Out > 0)
                TransferHelper.safeTransfer(token1, _to, _amount1Out); // optimistically transfer tokens
            balance0 = UniswapV2ERC20(token0).balanceOf(address(this));
            balance1 = UniswapV2ERC20(token1).balanceOf(address(this));
        }

        uint256 amount0In = balance0 > _reserve0 - _amount0Out
            ? balance0 - (_reserve0 - _amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - _amount1Out
            ? balance1 - (_reserve1 - _amount1Out)
            : 0;

        {
            if (!(amount0In > 0 || amount1In > 0)) {
                revert UniswapV2Pair__INSUFFICIENT_INPUT_AMOUNT();
            }

            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * 1000 - (amount0In * 3);
            uint256 balance1Adjusted = balance1 * 1000 - (amount1In * 3);
            if (
                balance0Adjusted * balance1Adjusted <
                uint256(_reserve0) * _reserve1 * (1000 ** 2)
            ) {
                revert UniswapV2Pair__K();
            }
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(
            msg.sender,
            amount0In,
            amount1In,
            _amount0Out,
            _amount1Out,
            _to
        );
    }

    /* ========== VIEWS ========== */

    /// @notice Retrieves the current reserves of the Uniswap pair.
    /// @return reserve0 The reserve amount of token0.
    /// @return reserve1 The reserve amount of token1.
    /// @return blockTimestampLast The timestamp of the last block update.
    function getReserves()
        public
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        reserve0 = s_reserve0;
        reserve1 = s_reserve1;
        blockTimestampLast = s_blockTimestampLast;
    }

    /* ========== WRAPPING PURE FUNCTIONS ========== */

    /**
     * @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset.
     * @param _amountA Amount of asset A.
     * @param _reserveA Reserve of asset A in the pair.
     * @param _reserveB Reserve of asset B in the pair.
     * @return amountB The maximum output amount of asset B.
     */
    function quote(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _reserveB
    ) public pure returns (uint256 amountB) {
        return UniswapV2Library.quote(_amountA, _reserveA, _reserveB);
    }

    /**
     * @notice Given an input amount of tokens, returns the maximum output amount of the other token given the reserves.
     * @param _amountIn Amount of input token.
     * @param _reserveIn Reserve of the input token.
     * @param _reserveOut Reserve of the output token.
     * @return amountOut The maximum output amount of the other token.
     */
    function getAmountOut(
        uint256 _amountIn,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) public pure returns (uint256 amountOut) {
        return
            UniswapV2Library.getAmountOut(_amountIn, _reserveIn, _reserveOut);
    }

    /**
     * @notice Given an output amount of tokens, returns the required input amount of the other token given the reserves.
     * @param _amountOut Amount of output token.
     * @param _reserveIn Reserve of the input token.
     * @param _reserveOut Reserve of the output token.
     * @return amountIn The required input amount of the other token.
     */
    function getAmountIn(
        uint256 _amountOut,
        uint256 _reserveIn,
        uint256 _reserveOut
    ) public pure returns (uint256 amountIn) {
        UniswapV2Library.getAmountOut(_amountOut, _reserveIn, _reserveOut);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /**
     * @notice Adds liquidity to the pair contract by depositing specified amounts of token0 and token1.
     * @dev Computes optimal amounts of tokens to deposit based on current reserves and desired amounts.
     * @param _amountADesired Desired amount of token0 to deposit.
     * @param _amountBDesired Desired amount of token1 to deposit.
     * @param _amountAMin Minimum acceptable amount of token0 to deposit.
     * @param _amountBMin Minimum acceptable amount of token1 to deposit.
     * @return amountA Amount of token0 deposited.
     * @return amountB Amount of token1 deposited.
     */
    function _addLiquidity(
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin
    ) private view returns (uint256 amountA, uint256 amountB) {
        uint256 reserveA = s_reserve0;
        uint256 reserveB = s_reserve1;
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (_amountADesired, _amountBDesired);
        } else {
            uint256 amountBOptimal = quote(_amountADesired, reserveA, reserveB);
            if (amountBOptimal <= _amountBDesired) {
                if (amountBOptimal < _amountBMin) {
                    revert UniswapV2Pair__INSUFFICIENT_B_AMOUNT();
                }
                (amountA, amountB) = (_amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(
                    _amountBDesired,
                    reserveB,
                    reserveA
                );
                // assert(amountAOptimal <= _amountADesired);
                if (amountAOptimal > _amountADesired) {
                    revert UniswapV2Pair__A_AMOUNT_EXCEEDS_DESIRED_AMOUNT();
                }
                if (amountAOptimal < _amountAMin) {
                    revert UniswapV2Pair__INSUFFICIENT_A_AMOUNT();
                }
                (amountA, amountB) = (amountAOptimal, _amountBDesired);
            }
        }
    }

    /**
     * @notice Updates the reserves of token0 and token1 and accumulates price information for the pair.
     * @dev Called during liquidity provision, ensures accurate reserve tracking and price calculations.
     * @param _balance0 Updated balance of token0.
     * @param _balance1 Updated balance of token1.
     * @param _reserve0 Previous reserve of token0.
     * @param _reserve1 Previous reserve of token1.
     */
    function _update(
        uint256 _balance0,
        uint256 _balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        unchecked {
            uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
            uint32 timeElapsed = blockTimestamp - s_blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows, and + overflow is desired
                s_price0CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                    timeElapsed;
                s_price1CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                    timeElapsed;
            }

            s_reserve0 = uint112(_balance0);
            s_reserve1 = uint112(_balance1);
            s_blockTimestampLast = blockTimestamp;
        }
        emit Sync(s_reserve0, s_reserve1);
    }

    /**
     * @notice Applies fees on liquidity providers based on changes in the sqrt(k) product of reserves.
     * @dev Calculates and mints additional liquidity tokens proportional to the growth in sqrt(k).
     * @param _reserve0 Reserve amount of token0.
     * @param _reserve1 Reserve amount of token1.
     * @return feeOn Whether fees are enabled and applied.
     */
    function _mintFee(
        uint112 _reserve0,
        uint112 _reserve1
    ) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(i_factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 kLast = s_kLast; // gas savings
        if (feeOn) {
            if (kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    // uint256 numerator = 10;
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (kLast != 0) {
            s_kLast = 0;
        }
    }
}
