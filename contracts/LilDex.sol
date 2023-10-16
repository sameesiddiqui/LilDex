// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LilDex is ReentrancyGuard {
    mapping(bytes => Pool) pools;
    uint INITIAL_LP_BALANCE = 10_000 * 1e18;
    uint LP_FEE = 30;

    struct Pool {
        mapping(address => uint) tokenBalances;
        mapping(address => uint) lpBalances;
        uint totalLpTokens;
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    )
        public
        validTokenAddresses(tokenA, tokenB)
        hasBalanceAndAllowance(tokenA, tokenB, amountA, amountB)
        nonReentrant
    {
        // check all values are valid
        Pool storage pool = _getPool(tokenA, tokenB);
        require(pool.tokenBalances[tokenA] == 0, "pool already exists!");

        // deposit tokens into contract
        _transferTokens(tokenA, tokenB, amountA, amountB);

        // initalize the pool
        pool.tokenBalances[tokenA] = amountA;
        pool.tokenBalances[tokenB] = amountB;
        pool.lpBalances[msg.sender] = INITIAL_LP_BALANCE;
        pool.totalLpTokens = INITIAL_LP_BALANCE;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    )
        public
        validTokenAddresses(tokenA, tokenB)
        hasBalanceAndAllowance(tokenA, tokenB, amountA, amountB)
        nonReentrant
        poolMustExist(tokenA, tokenB)
    {
        Pool storage pool = _getPool(tokenA, tokenB);
        uint tokenAPrice = getSpotPrice(tokenA, tokenB);
        require(
            tokenAPrice * amountA == amountB * 1e18,
            "must add liquidity at the current spot price"
        );

        _transferTokens(tokenA, tokenB, amountA, amountB);

        uint currentABalance = pool.tokenBalances[tokenA];
        uint newTokens = (amountA * INITIAL_LP_BALANCE) / currentABalance;

        pool.tokenBalances[tokenA] += amountA;
        pool.tokenBalances[tokenB] += amountB;
        pool.totalLpTokens += newTokens;
        pool.lpBalances[msg.sender] += newTokens;
    }

    function removeLiquidity(
        address tokenA,
        address tokenB
    )
        public
        validTokenAddresses(tokenA, tokenB)
        nonReentrant
        poolMustExist(tokenA, tokenB)
    {
        Pool storage pool = _getPool(tokenA, tokenB);
        uint balance = pool.lpBalances[msg.sender];
        require(balance > 0, "No liquidity provided by this user");

        // how much of tokenA and tokenB should we send to the LP?
        uint tokenAAmount = (balance * pool.tokenBalances[tokenA]) /
            pool.totalLpTokens;
        uint tokenBAmount = (balance * pool.tokenBalances[tokenB]) /
            pool.totalLpTokens;

        pool.lpBalances[msg.sender] = 0;
        pool.tokenBalances[tokenA] -= tokenAAmount;
        pool.tokenBalances[tokenB] -= tokenBAmount;
        pool.totalLpTokens -= balance;

        // send tokens to user
        ERC20 contractA = ERC20(tokenA);
        ERC20 contractB = ERC20(tokenB);

        require(
            contractA.transfer(msg.sender, tokenAAmount),
            "transfer failed"
        );
        require(
            contractB.transfer(msg.sender, tokenBAmount),
            "transfer failed"
        );
    }

    function swap(
        address from,
        address to,
        uint amount
    )
        public
        validTokenAddresses(from, to)
        nonReentrant
        poolMustExist(from, to)
    {
        Pool storage pool = _getPool(from, to);

        // deltaY = y * r * deltaX / x + (r * deltaX)
        uint r = 10_000 - LP_FEE;
        uint rDeltaX = (r * amount) / 10_000;

        uint outputTokens = (pool.tokenBalances[to] * rDeltaX) /
            (pool.tokenBalances[from] + rDeltaX);

        pool.tokenBalances[from] += amount;
        pool.tokenBalances[to] -= outputTokens;

        // send and receive tokens
        ERC20 contractFrom = ERC20(from);
        ERC20 contractTo = ERC20(to);

        require(
            contractFrom.transferFrom(msg.sender, address(this), amount),
            "transfer from user failed"
        );
        require(
            contractTo.transfer(msg.sender, outputTokens),
            "transfer to user failed"
        );
    }

    // HELPERS
    function _getPool(
        address tokenA,
        address tokenB
    ) internal view returns (Pool storage pool) {
        bytes memory key;
        if (tokenA < tokenB) {
            key = abi.encodePacked(tokenA, tokenB);
        } else {
            key = abi.encodePacked(tokenB, tokenA);
        }
        return pools[key];
    }

    function _transferTokens(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) internal {
        ERC20 contractA = ERC20(tokenA);
        ERC20 contractB = ERC20(tokenB);

        require(
            contractA.transferFrom(msg.sender, address(this), amountA),
            "Transfer of tokenA failed"
        );
        require(
            contractB.transferFrom(msg.sender, address(this), amountB),
            "Transfer of tokenB failed"
        );
    }

    function getSpotPrice(
        address tokenA,
        address tokenB
    ) public view returns (uint) {
        Pool storage pool = _getPool(tokenA, tokenB);
        require(
            pool.tokenBalances[tokenA] > 0 && pool.tokenBalances[tokenB] > 0,
            "balances must be non-zero"
        );
        return ((pool.tokenBalances[tokenB] * 1e18) /
            pool.tokenBalances[tokenA]);
    }

    function getBalances(
        address tokenA,
        address tokenB
    ) external view returns (uint tokenABalance, uint tokenBBalance) {
        Pool storage pool = _getPool(tokenA, tokenB);
        return (pool.tokenBalances[tokenA], pool.tokenBalances[tokenB]);
    }

    function getLpBalance(
        address lp,
        address tokenA,
        address tokenB
    ) external view returns (uint) {
        Pool storage pool = _getPool(tokenA, tokenB);
        return (pool.lpBalances[lp]);
    }

    function getTotalLpTokens(
        address tokenA,
        address tokenB
    ) external view returns (uint) {
        Pool storage pool = _getPool(tokenA, tokenB);
        return (pool.totalLpTokens);
    }

    // MODIFIERS
    modifier validTokenAddresses(address tokenA, address tokenB) {
        require(tokenA != tokenB, "addresses must be different!");
        require(
            tokenA != address(0) && tokenB != address(0),
            "must be valid addresses!"
        );
        _;
    }

    modifier hasBalanceAndAllowance(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) {
        ERC20 contractA = ERC20(tokenA);
        ERC20 contractB = ERC20(tokenB);

        require(
            contractA.balanceOf(msg.sender) >= amountA,
            "user doesn't have enough tokens"
        );
        require(
            contractB.balanceOf(msg.sender) >= amountB,
            "user doesn't have enough tokens"
        );
        require(
            contractA.allowance(msg.sender, address(this)) >= amountA,
            "user didn't grant allowance"
        );
        require(
            contractB.allowance(msg.sender, address(this)) >= amountB,
            "user didn't grant allowance"
        );

        _;
    }

    modifier poolMustExist(address tokenA, address tokenB) {
        Pool storage pool = _getPool(tokenA, tokenB);
        require(pool.tokenBalances[tokenA] != 0, "pool must exist");
        require(pool.tokenBalances[tokenB] != 0, "pool must exist");
        _;
    }
}
