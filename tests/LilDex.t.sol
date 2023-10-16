// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {LilDex} from "../contracts/LilDex.sol";
import {SimpleCoin} from "../contracts/SimpleCoin.sol";
import {AnotherToken} from "../contracts/AnotherToken.sol";

contract TestLilDex is Test {
    LilDex public dex;
    SimpleCoin public tokenA;
    AnotherToken public tokenB;
    address public LP1;
    address public LP2;
    address public swapper;

    function setUp() public {
        dex = new LilDex();
        LP1 = address(0x123);
        LP2 = address(0x456);
        swapper = address(0x6969);

        vm.startPrank(LP1);
        tokenA = new SimpleCoin(5_000 ether);
        tokenA.mint(LP2, 7_000 ether);
        tokenA.mint(swapper, 1_000 ether);
        vm.stopPrank();

        vm.startPrank(LP2);
        tokenB = new AnotherToken(700_000 ether);
        tokenB.mint(LP1, 500_000 ether);
        vm.stopPrank();
    }

    function testSwap() public {
        vm.startPrank(LP1);

        // Approve the DEX to spend the tokens
        tokenA.approve(address(dex), 5000 ether);
        tokenB.approve(address(dex), 500_000 ether);

        dex.createPool(
            address(tokenA),
            address(tokenB),
            5000 ether,
            500_000 ether
        );
        uint tokenABalance;
        uint tokenBBalance;
        uint lp1Balance;
        uint lp2Balance;
        uint totalLpTokens;
        (tokenABalance, tokenBBalance) = dex.getBalances(
            address(tokenA),
            address(tokenB)
        );
        totalLpTokens = dex.getTotalLpTokens(address(tokenA), address(tokenB));
        assertEq(tokenABalance, 5000 ether);
        assertEq(tokenBBalance, 500_000 ether);
        assertEq(totalLpTokens, 10_000 ether);

        vm.stopPrank();
        // add liquidity
        vm.startPrank(LP2);

        // Approve the DEX to spend the tokens
        tokenA.approve(address(dex), 7000 ether);
        tokenB.approve(address(dex), 700_000 ether);

        vm.expectRevert("must add liquidity at the current spot price");
        dex.addLiquidity(
            address(tokenA),
            address(tokenB),
            7000 ether,
            500_000 ether
        );

        dex.addLiquidity(
            address(tokenA),
            address(tokenB),
            7000 ether,
            700_000 ether
        );
        (tokenABalance, tokenBBalance) = dex.getBalances(
            address(tokenA),
            address(tokenB)
        );
        totalLpTokens = dex.getTotalLpTokens(address(tokenA), address(tokenB));
        lp1Balance = dex.getLpBalance(
            address(LP1),
            address(tokenA),
            address(tokenB)
        );
        lp2Balance = dex.getLpBalance(
            address(LP2),
            address(tokenA),
            address(tokenB)
        );
        assertEq(tokenABalance, 12_000 ether);
        assertEq(tokenBBalance, 1_200_000 ether);
        assertEq(totalLpTokens, 24_000 ether);
        assertEq(lp2Balance, 14_000 ether);
        assertEq(lp1Balance, 10_000 ether);

        vm.stopPrank();
        // make a trade
        vm.startPrank(swapper);
        tokenA.approve(address(dex), 1000 ether);
        dex.swap(address(tokenA), address(tokenB), 1000 ether);

        (tokenABalance, tokenBBalance) = dex.getBalances(
            address(tokenA),
            address(tokenB)
        );
        assertEq(tokenABalance, 13_000 ether);
        uint newBBalance = 1_200_000 ether - 92052012002769869969993;
        assertEq(tokenBBalance, newBBalance);
        assertEq(tokenA.balanceOf(swapper), 0);
        assertEq(tokenB.balanceOf(swapper), 92052012002769869969993);

        vm.stopPrank();
        // // remove liquidity
        vm.startPrank(LP1);
        dex.removeLiquidity(address(tokenA), address(tokenB));
        (tokenABalance, tokenBBalance) = dex.getBalances(
            address(tokenA),
            address(tokenB)
        );
        totalLpTokens = dex.getTotalLpTokens(address(tokenA), address(tokenB));
        lp1Balance = dex.getLpBalance(
            address(LP1),
            address(tokenA),
            address(tokenB)
        );
        lp2Balance = dex.getLpBalance(
            address(LP2),
            address(tokenA),
            address(tokenB)
        );
        uint newABalance = 13_000 ether;
        uint aOut = (newABalance * 10) / 24;
        uint bOut = (newBBalance * 10) / 24;
        assertEq(tokenA.balanceOf(LP1), aOut);
        assertEq(tokenB.balanceOf(LP1), bOut);
        assertEq(tokenABalance, newABalance - aOut);
        assertEq(tokenBBalance, newBBalance - bOut);
        assertEq(lp1Balance, 0);
        assertEq(lp2Balance, 14_000 ether);
        vm.stopPrank();
    }
}
