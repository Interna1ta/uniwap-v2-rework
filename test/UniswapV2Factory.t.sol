// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2ERC20} from "../src/UniswapV2ERC20.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MyERC20} from "./mock/MyERC20.sol";

contract UniswapV2FactoryTest is Test {
    MyERC20 public tokenA;
    MyERC20 public tokenB;
    MyERC20 public tokenC;
    UniswapV2Factory public factory;
    address public OWNER = makeAddr("OWNER");
    address public FEE_RECEIVER = makeAddr("FEE_RECEIVER");

    function setUp() public {
        tokenA = new MyERC20("Token AAA", "AAA", OWNER);
        tokenB = new MyERC20("Token BBB", "BBB", OWNER);
        tokenC = new MyERC20("Token CCC", "CCC", OWNER);
        factory = new UniswapV2Factory(FEE_RECEIVER);
    }

    function testCreatePair() public {
        vm.startPrank(OWNER);
        factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.allPairsLength(), 1);
        vm.stopPrank();
    }

    function testCreatePairEqualToken() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        factory.createPair(address(tokenA), address(tokenA));
        vm.stopPrank();
    }

    function testCreatePairWithZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        factory.createPair(address(0), address(tokenA));
        vm.stopPrank();
    }

    function testCreatePairAlreadyExists() public {
        vm.startPrank(OWNER);
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert();
        factory.createPair(address(tokenA), address(tokenB));
        vm.stopPrank();
    }

    function testSetFeeTo() public {
        vm.startPrank(FEE_RECEIVER);
        factory.setFeeTo(FEE_RECEIVER);
        assertEq(factory.feeTo(), FEE_RECEIVER);
        vm.stopPrank();
    }

    function testSetFeeToForbidden() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        factory.setFeeTo(FEE_RECEIVER);
        vm.stopPrank();
    }

    function testSetFeeToSetter() public {
        vm.startPrank(FEE_RECEIVER);
        factory.setFeeToSetter(FEE_RECEIVER);
        assertEq(factory.feeToSetter(), FEE_RECEIVER);
        vm.stopPrank();
    }

    function testSetFeeToSetterForbidden() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        factory.setFeeToSetter(FEE_RECEIVER);
        vm.stopPrank();
    }

    function testAllPairs() public {
        vm.startPrank(OWNER);
        factory.createPair(address(tokenA), address(tokenB));
        factory.createPair(address(tokenB), address(tokenC));
        address pair = factory.getPair(address(tokenB), address(tokenC));
        assertEq(factory.allPairs(1), pair);
        vm.stopPrank();
    }
}
