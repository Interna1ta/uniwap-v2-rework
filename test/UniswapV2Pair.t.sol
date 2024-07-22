// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {UniswapV2ERC20} from "../src/UniswapV2ERC20.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {FixedPointMathLib as Math} from "solady/src/utils/FixedPointMathLib.sol";

import {MyERC20} from "./mock/MyERC20.sol";

contract UniswapV2PairTest is Test {
    using Math for uint256;

    MyERC20 public tokenA;
    MyERC20 public tokenB;
    UniswapV2Pair public pair;
    UniswapV2Factory public factory;
    address public OWNER = makeAddr("OWNER");
    address public SENDER = makeAddr("SENDER");
    address public SENDER_2 = makeAddr("SENDER_2");
    address public RECEIVER = makeAddr("RECEIVER");
    address public FEE_RECEIVER = makeAddr("FEE_RECEIVER");
    uint256 public AMOUNT = 10 * (10 ** 3);
    uint256 public AMOUNT_A_DESIRED = 5 * (10 ** 3);
    uint256 public AMOUNT_B_DESIRED = 5 * (10 ** 3);
    uint256 public AMOUNT_A_MIN = 5 * (10 ** 3);
    uint256 public AMOUNT_B_MIN = 5 * (10 ** 3);
    uint256 public AMOUNT_SWAP_A = 1 * (10 ** 3);
    uint256 public AMOUNT_SWAP_B = 1 * (10 ** 3);
    uint256 public DEADLINE = block.timestamp + 300; // 300 seconds are 5 minutes
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    function setUp() public {
        vm.startPrank(OWNER);
        tokenA = new MyERC20("Token AAA", "AAA", OWNER);
        tokenB = new MyERC20("Token BBB", "BBB", OWNER);
        tokenA.mint(SENDER, AMOUNT);
        tokenB.mint(SENDER, AMOUNT);
        tokenA.mint(SENDER_2, AMOUNT);
        tokenB.mint(SENDER_2, AMOUNT);

        factory = new UniswapV2Factory(OWNER);
        factory.setFeeToSetter(OWNER);
        factory.setFeeTo(FEE_RECEIVER);
        vm.stopPrank();

        vm.startPrank(address(factory));
        pair = new UniswapV2Pair();
        vm.stopPrank();
    }

    // function testInitializeToken0() public {
    //     vm.startPrank(address(factory));
    //     pair.initialize(address(tokenA), address(tokenB));
    //     assertEq(pair.s_token0(), address(tokenA));
    //     vm.stopPrank();
    // }

    // function testInitializeToken1() public {
    //     vm.startPrank(address(factory));
    //     pair.initialize(address(tokenA), address(tokenB));
    //     assertEq(pair.s_token1(), address(tokenB));
    //     vm.stopPrank();
    // }

    function testInitializeForbidden() public {
        vm.startPrank(SENDER);
        vm.expectRevert();
        pair.initialize(address(tokenA), address(tokenB));
        vm.stopPrank();
    }

    function testAddLiquidity() public {
        vm.startPrank(address(factory));
        pair.initialize(address(tokenA), address(tokenB));
        vm.stopPrank();

        vm.startPrank(SENDER);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER_2,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        assertEq(tokenA.balanceOf(address(pair)), AMOUNT_A_DESIRED * 2);
        assertEq(tokenB.balanceOf(address(pair)), AMOUNT_B_DESIRED * 2);

        uint256 liquidity = Math.sqrt(uint256(AMOUNT_A_DESIRED) * AMOUNT_B_DESIRED);
        assertEq(pair.balanceOf(SENDER_2), liquidity);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        vm.startPrank(address(factory));
        pair.initialize(address(tokenA), address(tokenB));
        vm.stopPrank();

        vm.startPrank(SENDER);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER_2,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        assertEq(tokenA.balanceOf(address(pair)), AMOUNT_A_DESIRED * 2);
        assertEq(tokenB.balanceOf(address(pair)), AMOUNT_B_DESIRED * 2);

        uint256 liquidity = Math.sqrt(uint256(AMOUNT_A_DESIRED) * AMOUNT_B_DESIRED);
        assertEq(pair.balanceOf(SENDER_2), liquidity);

        pair.approve(address(pair), liquidity);
        pair.removeLiquidity(
            liquidity,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER_2,
            DEADLINE
        );
        assertEq(pair.balanceOf(SENDER_2), 0);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(address(factory));
        pair.initialize(address(tokenA), address(tokenB));
        vm.stopPrank();

        vm.startPrank(SENDER);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        tokenA.approve(address(pair), AMOUNT_A_DESIRED);
        tokenB.approve(address(pair), AMOUNT_B_DESIRED);
        pair.addLiquidity(
            AMOUNT_A_DESIRED,
            AMOUNT_B_DESIRED,
            AMOUNT_A_MIN,
            AMOUNT_B_MIN,
            SENDER_2,
            DEADLINE
        );
        vm.stopPrank();

        vm.startPrank(SENDER_2);
        uint256 initialBalanceA = tokenA.balanceOf(address(pair));
        uint256 initialBalanceB = tokenB.balanceOf(address(pair));
        assertEq(initialBalanceA, AMOUNT_A_DESIRED * 2);
        assertEq(initialBalanceB, AMOUNT_B_DESIRED * 2);

        uint256 amountIn = AMOUNT / 2;
        uint256 amountOut = AMOUNT / 4;

        tokenB.balanceOf(SENDER_2);
        tokenA.approve(address(pair), amountIn);

        pair.swapExactTokensForTokens(amountIn, address(tokenA), amountOut, address(tokenB), RECEIVER, DEADLINE);

        uint256 finalBalanceA = tokenA.balanceOf(address(pair));
        uint256 finalBalanceB = tokenB.balanceOf(address(pair));

        assertEq(finalBalanceA > initialBalanceA, true); // TokenA balance should decrease
        assertEq(finalBalanceB < initialBalanceB, true); // TokenB balance should increase
        vm.stopPrank();
    }

    // function testSkim() public {

    // }

    // function testSync() public {

    // }
}
