// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./UniswapV2Library.sol";
import "./TransferHelper.sol";
import "./IERC20.sol";
import "./IWETH.sol";
import "./IUniswapV2Pair.sol";
import "./SafeMath.sol";

contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint256;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        // Only accept ETH via fallback from the WETH contract
        require(msg.sender == WETH, "UniswapV2Router: INVALID_SENDER");
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }

        (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);

        IUniswapV2Pair pair = IUniswapV2Pair(
            IUniswapV2Factory(factory).getPair(tokenA, tokenB)
        );

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();

        (uint256 reserveA, uint256 reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = UniswapV2Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2Library.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                require(
                    amountAOptimal <= amountADesired,
                    "UniswapV2Router: EXCESSIVE_A_AMOUNT"
                );
                require(
                    amountAOptimal >= amountAMin,
                    "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function debugPairCheck(address tokenA, address tokenB) external view {
        address officialPair = IUniswapV2Factory(factory).getPair(
            tokenA,
            tokenB
        );
        address libraryPair = IUniswapV2Factory(factory).getPair(
            tokenA,
            tokenB
        );

        // Optional: check that the factory has actually created this pair
        require(officialPair != address(0), "UniswapV2Router: NO_PAIR_CREATED");

        // If mismatch, show them in revert message
        if (officialPair != libraryPair) {
            revert(
                string(
                    abi.encodePacked(
                        "UniswapV2Router: INIT_CODE_PAIR_HASH mismatch. factory.getPair=",
                        _addressToString(officialPair),
                        ", pairFor=",
                        _addressToString(libraryPair)
                    )
                )
            );
        }
    }

    function _addressToString(address _addr)
        internal
        pure
        returns (string memory)
    {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42); // 0x + 40 hex chars
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            // Each byte in the address becomes two hex characters
            uint8 b = uint8(value[i + 12]);
            str[2 + i * 2] = alphabet[b >> 4];
            str[3 + i * 2] = alphabet[b & 0x0f];
        }
        return string(str);
    }

    // function addLiquidityETH(
    //     address token,
    //     uint256 amountTokenDesired,
    //     uint256 amountTokenMin,
    //     uint256 amountETHMin,
    //     address to,
    //     uint256 deadline
    // )
    //     external
    //     payable
    //     virtual
    //     override
    //     ensure(deadline)
    //     returns (
    //         uint256 amountToken,
    //         uint256 amountETH,
    //         uint256 liquidity
    //     )
    // {
    //     (amountToken, amountETH) = _addLiquidity(
    //         token,
    //         WETH,
    //         amountTokenDesired,
    //         msg.value,
    //         amountTokenMin,
    //         amountETHMin
    //     );

    //     address pair = IUniswapV2Factory(factory).getPair(token, WETH);

    //     TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
    //     IWETH(WETH).deposit{value: amountETH}();
    //     assert(IWETH(WETH).transfer(pair, amountETH));

    //     liquidity = IUniswapV2Pair(pair).mint(to);

    //     // refund dust eth, if any
    //     if (msg.value > amountETH) {
    //         TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    //     }
    // }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        // 1. Add liquidity (figure out how many tokens/ETH to deposit)
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        // Add a require to confirm non-zero amounts (useful for debugging).
        require(
            amountToken > 0,
            "Router: after _addLiquidity, amountToken is zero"
        );
        require(
            amountETH > 0,
            "Router: after _addLiquidity, amountETH is zero"
        );

        // 2. Get the pair address from the factory
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        require(
            pair != address(0),
            "Router: pair does not exist (did you create it?)"
        );

        // [Optional] If you want to confirm the user has enough token balance/allowance:
        // require(IERC20(token).balanceOf(msg.sender) >= amountToken, "Router: insufficient token balance");
        // require(IERC20(token).allowance(msg.sender, address(this)) >= amountToken, "Router: insufficient token allowance");

        // 3. Transfer the tokens in
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        // 4. Wrap ETH -> WETH
        IWETH(WETH).deposit{value: amountETH}();
        // [Optional] Could do a post-check: require(IERC20(WETH).balanceOf(address(this)) >= amountETH, "Router: WETH deposit mismatch");

        // 5. Transfer WETH into the pair
        bool success = IWETH(WETH).transfer(pair, amountETH);
        require(success, "Router: failed to transfer WETH to pair");

        // 6. Mint the liquidity tokens
        liquidity = IUniswapV2Pair(pair).mint(to);
        require(liquidity > 0, "Router: liquidity minted is zero");

        // 7. Refund any leftover ETH if msg.value > amountETH
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin,
            "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountB >= amountBMin,
            "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
        );
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IUniswapV2Pair(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountETH)
    {
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IUniswapV2Pair(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        (amountToken, amountETH) = removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // transfer all of token balance to `to`
        TransferHelper.safeTransfer(
            token,
            to,
            IERC20(token).balanceOf(address(this))
        );
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IUniswapV2Pair(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);

            // Sort tokens so we know which side is token0 or token1
            (address token0, ) = UniswapV2Library.sortTokens(input, output);

            // The output amount for this hop
            uint256 amountOut = amounts[i + 1];

            // Decide which token is going out as amount0Out vs amount1Out
            (uint256 amount0Out, uint256 amount1Out) = (input == token0)
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            // Determine the recipient of this swap:
            // If there is another hop after this one, send to the next pair
            // Otherwise, send to the final `_to`
            address next = (i < path.length - 2)
                ? IUniswapV2Factory(factory).getPair(output, path[i + 2])
                : _to;

            // Get the current pair address from the factory
            address currentPair = IUniswapV2Factory(factory).getPair(
                input,
                output
            );
            require(currentPair != address(0), "Router: PAIR_NOT_FOUND");

            // Execute the swap on the current pair
            IUniswapV2Pair(currentPair).swap(
                amount0Out,
                amount1Out,
                next,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        amounts = getAmountsOutByFactory(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "UniswapV2Router: INVALID_PATH");
        // amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        amounts = getAmountsOutByFactory(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                IUniswapV2Factory(factory).getPair(path[0], path[1]),
                amounts[0]
            )
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        // amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        amounts = getAmountsOutByFactory(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "UniswapV2Router: INVALID_PATH");
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= msg.value,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                IUniswapV2Factory(factory).getPair(path[0], path[1]),
                amounts[0]
            )
        );
        _swap(amounts, path, to);
        // refund dust ETH, if any
        if (msg.value > amounts[0]) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(
                IUniswapV2Factory(factory).getPair(input, output)
            );
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair)
                    .getReserves();

                (reserve0, reserve1) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);

                // scope to avoid stack too deep
                // (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(
                    reserveInput
                );
                amountOutput = UniswapV2Library.getAmountOut(
                    amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2
                ? IUniswapV2Factory(factory).getPair(output, path[i + 2])
                : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
                amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WETH, "UniswapV2Router: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(
            IWETH(WETH).transfer(
                IUniswapV2Factory(factory).getPair(path[0], path[1]),
                amountIn
            )
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
                amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            IUniswapV2Factory(factory).getPair(path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(
            amountOut >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        // return UniswapV2Library.getAmountsOut(factory, amountIn, path);
        return getAmountsOutByFactory(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }

    function getAmountsOutByFactory(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path length");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReservesByFactory(
                factory,
                path[i],
                path[i + 1]
            );

            // standard uniswap getAmountOut formula
            uint256 amountIn_ = amounts[i];
            require(amountIn_ > 0, "Insufficient input amount");
            require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

            uint256 amountInWithFee = amountIn_ * 997;
            uint256 numerator = amountInWithFee * reserveOut;
            uint256 denominator = reserveIn * 1000 + amountInWithFee;
            amounts[i + 1] = numerator / denominator;
        }
    }

    function getReservesByFactory(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        require(tokenA != tokenB, "Invalid tokens");
        // Sort so we know which side is token0, token1
        (address token0, ) = sortTokens(tokenA, tokenB);

        // Use the factory’s getPair instead of pairFor
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "No pair found in factory");

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        // Adjust ordering if tokenA != token0
        (reserveA, reserveB) = (tokenA == token0)
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "Identical addresses");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
    }
}
