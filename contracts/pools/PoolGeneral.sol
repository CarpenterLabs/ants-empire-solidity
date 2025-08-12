// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BasePool.sol";

interface IUniswapV2Router {
    /**
     * @notice Given an input asset amount and an array of token addresses,
     * calculates all subsequent maximum output token amounts by calling
     * getReserves for each pair in the path in turn, then using the pair’s
     * formula.
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Receive an ETH amount from the sender, convert it to WETH,
     * then perform a token swap along a path to some output token,
     * sending the result to `to`.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin, // Revert if output is below this
        address[] calldata path, // Path of tokens: [WETH, token1, token2, ...]
        address to, // Recipient of the final output tokens
        uint256 deadline // Unix timestamp after which the swap is invalid
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Transfer `amountIn` tokens from the sender,
     * swap along a path to some output token, sending the result to `to`.
     */
    function swapExactTokensForTokens(
        uint256 amountIn, // Amount of the first token to swap
        uint256 amountOutMin, // Revert if output is below this
        address[] calldata path, // Path of tokens: [tokenIn, tokenMid, ..., tokenOut]
        address to, // Recipient of the final output tokens
        uint256 deadline // Unix timestamp after which the swap is invalid
    ) external returns (uint256[] memory amounts);
}

interface VRFCoordinatorV2Interface {
    /**
     * @notice Fund a subscription using native currency (e.g., ETH or MATIC)
     * @param subId - ID of the subscription to fund
     */
    function fundSubscriptionWithNative(uint256 subId) external payable;
}

contract GeneralPool is BasePool {
    using SafeERC20 for IERC20;
    event NectarAdded(address indexed contributor, uint256 nectarAmount);
    event NectarSent(address indexed contributor, uint256 nectarAmount);
    address public uniswapRouter;
    address public devWallet;
    address public usdt;
    address public weth;
    address immutable vrfCoordinator;

    uint256 subscriptionId;

    struct SwapAmounts {
        uint256 swapAmount;
        uint256 secondaryAmount;
        uint256 devAmount;
        uint256 gasWalletShare;
        uint256 scConsumerShare;
    }

    struct MultiSwapParams {
        uint256 amountIn;
        address pool;
        address ogRequester;
        uint256 deadline;
    }

    struct SwapData {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address recipient;
        bool sendToRecipient;
        uint256 deadline;
        bool isETHOut;
        uint256 outputAmount;
    }

    uint256 slippageTolerance = 50;

    constructor(
        address _nodeWallet,
        address _nectarAddress,
        address _usdt,
        address _weth,
        address _uniswapRouterAddress,
        address _devWallet,
        address _vrfCoordinator,
        uint256 _chainLinkSubscriptionId
    ) BasePool(_nodeWallet, _nectarAddress) {
        uniswapRouter = _uniswapRouterAddress;
        usdt = _usdt;
        weth = _weth;
        devWallet = _devWallet;
        vrfCoordinator = _vrfCoordinator;
        subscriptionId = _chainLinkSubscriptionId;
    }

    /**
     * @dev Updates the slippage tolerance.
     * @param newSlippageTolerance The new slippage tolerance value.
     */
    function setSlippageTolerance(uint256 newSlippageTolerance)
        external
        onlyAllowed
    {
        require(
            newSlippageTolerance > 0,
            "Slippage tolerance must be greater than 0"
        );
        slippageTolerance = newSlippageTolerance;
    }

    /// @notice Send a specific amount of ERC-20 tokens to a given address
    /// @param recipient The address to send tokens to
    /// @param amount The amount of tokens to send
    function sendFunds(address recipient, uint256 amount) external onlyAllowed {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= nectarToken.balanceOf(address(this)),
            "Insufficient contract balance"
        );

        // Transfer the tokens to the recipient
        IERC20(nectarToken).safeTransfer(recipient, amount);

        emit FundsSent(recipient, amount);
    }

    /**
     * @dev Approve token for the router if not already approved.
     * @param token Address of the token to approve.
     * @param amount Amount to approve.
     */
    // function _approveUniswapRouterIfNeeded(address token, uint256 amount)
    //     internal
    // {
    //     uint256 allowance = IERC20(token).allowance(
    //         address(this),
    //         uniswapRouter
    //     );
    //     if (allowance < amount) {
    //         IERC20(token).approve(uniswapRouter, type(uint256).max);
    //     }
    // }

    function _approveUniswapRouterIfNeeded(address token, uint256 amount)
        internal
    {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than zero");
        require(uniswapRouter != address(0), "Uniswap Router not set");

        uint256 allowance = IERC20(token).allowance(
            address(this),
            uniswapRouter
        );
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (token != weth) {
            require(balance >= amount, "Insufficient token balance");
        }

        if (allowance < amount) {
            bool success = IERC20(token).approve(
                uniswapRouter,
                type(uint256).max
            );
            require(success, "Approval failed");
        }
    }

    function modifySubscriptionId(uint256 _newSubId) external onlyOwner {
        require(_newSubId > 0, "New sub Id must be greater than 0");
        subscriptionId = _newSubId;
    }

    /**
     * @dev Swap tokens using PancakeSwap Router. Optionally send output tokens to a recipient.
     * @param tokenIn Address of the input token (TokenA).
     * @param tokenOut Address of the output token (TokenB).
     * @param amountIn Amount of input tokens to swap.
     * @param recipient Address to send the output tokens to.
     * @param sendToRecipient Whether to send output tokens to the recipient.
     * @param deadline Timestamp deadline for the swap.
     * @param isETHOut Defines if we are going to get ETH or not.
     * @return outputAmount The amount of tokenOut received from the swap.
     */
    // function swapAndSend(
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn,
    //     // uint256 amountOutMin,
    //     address recipient,
    //     bool sendToRecipient,
    //     uint256 deadline,
    //     bool isETHOut
    // ) internal returns (uint256 outputAmount) {
    //     require(
    //         IERC20(tokenIn).balanceOf(address(this)) >= amountIn,
    //         "Insufficient token balance"
    //     );

    //     // Approve the router to spend the input token, if not already approved
    //     _approveUniswapRouterIfNeeded(tokenIn, amountIn);

    //     // Define the swap path (TokenA -> TokenB or TokenA -> ETH)
    //     address[] memory path = new address[](2);
    //     path[0] = tokenIn; // selling token
    //     path[1] = tokenOut; // buying token or WETH if ETH out

    //     /*uint256[] memory amountsOut = IUniswapRouter(uniswapRouter)
    //         .getAmountsOut(amountIn, path);*/

    //     uint256 amountOutput = IUniswapRouter(uniswapRouter).getAmountOut(
    //         amountIn,
    //         tokenIn,
    //         tokenOut
    //     );

    //     uint256 amountOutMin = (amountOutput * (100 - slippageTolerance)) / 100;

    //     uint256[] memory amounts;

    //     if (isETHOut) {
    //         // Perform the swap via UniSwap Router for Token -> ETH
    //         amounts = IUniswapRouter(uniswapRouter).swapExactTokensForETH(
    //             amountIn,
    //             amountOutMin,
    //             path,
    //             address(this), // ETH received in this contract
    //             deadline
    //         );
    //     } else {
    //         // Perform the swap via UniSwap Router for Token -> Token
    //         amounts = IUniswapRouter(uniswapRouter).swapExactTokensForTokens(
    //             amountIn,
    //             amountOutMin,
    //             path,
    //             address(this), // Tokens received in this contract
    //             deadline
    //         );
    //     }

    //     // The amount of tokenOut received
    //     outputAmount = amounts[amounts.length - 1];

    //     // Optionally send the swapped tokens or ETH to the recipient
    //     if (sendToRecipient) {
    //         if (isETHOut) {
    //             (bool success, ) = recipient.call{value: outputAmount}("");
    //             require(success, "ETH transfer failed");
    //         } else {
    //             IERC20(tokenOut).safeTransfer(recipient, outputAmount);
    //         }
    //     }

    //     return outputAmount;
    // }

    function swapAndSend(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        bool sendToRecipient,
        uint256 deadline,
        bool isETHOut
    ) internal returns (uint256 outputAmount) {
        require(tokenIn != address(0), "Invalid tokenIn");
        require(tokenOut != address(0), "Invalid tokenOut");
        require(amountIn > 0, "Invalid amountIn");
        require(block.timestamp <= deadline, "Deadline exceeded");

        SwapData memory swap = SwapData({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            recipient: recipient,
            sendToRecipient: sendToRecipient,
            deadline: deadline,
            isETHOut: isETHOut,
            outputAmount: 0
        });

        if (swap.tokenIn != weth) {
            uint256 contractBalanceBefore = IERC20(swap.tokenIn).balanceOf(
                address(this)
            );

            require(
                contractBalanceBefore >= swap.amountIn,
                "Insufficient balance"
            );
        }

        _approveUniswapRouterIfNeeded(swap.tokenIn, swap.amountIn);

        address[] memory path = new address[](2);
        path[0] = swap.tokenIn;
        path[1] = swap.tokenOut;

        uint256[] memory amountsOut = IUniswapV2Router(uniswapRouter)
            .getAmountsOut(amountIn, path);
        uint256 amountOutMin = (amountsOut[amountsOut.length - 1] *
            (100 - slippageTolerance)) / 100;

        uint256[] memory amounts;

        if (swap.isETHOut) {
            amounts = IUniswapV2Router(uniswapRouter).swapExactTokensForETH(
                swap.amountIn, // exact tokens you are swapping in
                amountOutMin, // minimum ETH you want out
                path, // [tokenIn, ..., WETH]
                address(this), // receive ETH here (router un-wraps WETH)
                swap.deadline
            );
            require(amounts.length > 0, "ETH swap failed");
            swap.outputAmount = amounts[amounts.length - 1];

            if (swap.sendToRecipient) {
                (bool success, ) = swap.recipient.call{
                    value: swap.outputAmount
                }("");
                require(success, "ETH transfer failed");
            }
        } else {
            // Ensure the input token is WETH when swapping ETH for tokens
            require(swap.tokenIn == weth, "Invalid tokenIn for ETH swap");

            // Ensure the contract has sufficient ETH balance
            require(
                address(this).balance >= swap.amountIn,
                "Insufficient ETH balance"
            );

            amounts = IUniswapV2Router(uniswapRouter).swapExactETHForTokens{
                value: swap.amountIn
            }(amountOutMin, path, address(this), swap.deadline);
            require(amounts.length > 0, "Token swap failed");
            swap.outputAmount = amounts[amounts.length - 1];

            if (swap.sendToRecipient) {
                require(
                    IERC20(swap.tokenOut).transfer(
                        swap.recipient,
                        swap.outputAmount
                    ),
                    "Token transfer failed"
                );
            }
        }

        return swap.outputAmount;
    }

    function uint256ToString(uint256 value)
        internal
        pure
        returns (string memory)
    {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Borrow the specified amount of tokens from the user.
     * @param token Address of the token to borrow.
     * @param amount Amount to borrow.
     */
    function _borrowFromUser(
        address token,
        uint256 amount,
        address ogRequester
    ) internal {
        require(token != address(0), "Invalid token address");
        require(ogRequester != address(0), "Invalid requester");
        require(amount > 0, "Invalid amount");

        IERC20 erc20Token = IERC20(token);

        uint256 allowance = erc20Token.allowance(ogRequester, address(this));
        uint256 balance = IERC20(token).balanceOf(ogRequester);
        require(
            balance >= amount,
            string(
                abi.encodePacked(
                    "Insufficient balance. Need: ",
                    uint256ToString(amount),
                    ", Have: ",
                    uint256ToString(balance)
                )
            )
        );

        require(allowance >= amount, "Insufficient allowance");
        require(balance >= amount, "Insufficient balance");

        // Debugging events
        emit DebugAllowance(ogRequester, address(this), allowance);
        emit DebugBalance(ogRequester, balance);

        // Using SafeERC20 to prevent failing transferFrom
        SafeERC20.safeTransferFrom(
            erc20Token,
            ogRequester,
            address(this),
            amount
        );
    }

    // Debugging events to track values
    event DebugAllowance(
        address indexed owner,
        address indexed spender,
        uint256 allowance
    );
    event DebugBalance(address indexed account, uint256 balance);

    // function multiSwapAndSend(MultiSwapParams calldata params)
    //     external
    //     onlyAllowed
    // {
    //     require(params.pool != address(0), "Invalid pool address");

    //     // Borrow the USDT from the user
    //     _borrowFromUser(usdt, params.amountIn, params.ogRequester);

    //     // Calculate the split using a struct
    //     SwapAmounts memory amounts;
    //     amounts.swapAmount = (params.amountIn * 70) / 100;
    //     amounts.secondaryAmount = (params.amountIn * 10) / 100;
    //     amounts.devAmount = (params.amountIn * 20) / 100;

    //     // Swap 10% of USDT -> ETH
    //     uint256 ethReceived = swapAndSend(
    //         usdt,
    //         weth,
    //         amounts.secondaryAmount,
    //         address(this),
    //         false,
    //         params.deadline,
    //         true
    //     );
    //     require(ethReceived > 0, "Failed to swap USDT to ETH");

    //     // Split the received ETH: 5% to gasWallet and 5% to scConsumer
    //     amounts.gasWalletShare = ethReceived / 2;
    //     amounts.scConsumerShare = ethReceived - amounts.gasWalletShare;

    //     require(
    //         payable(nodeWallet).send(amounts.gasWalletShare),
    //         "Failed to send ETH to gas wallet"
    //     );

    //     // Call the VRFCoordinator's fundSubscriptionWithNative function
    //     VRFCoordinatorV2Interface(vrfCoordinator).fundSubscriptionWithNative{
    //         value: amounts.scConsumerShare
    //     }(subscriptionId);

    //     // Transfer 20% of USDT to the dev wallet
    //     IERC20(usdt).safeTransfer(devWallet, amounts.devAmount);

    //     // Swap 70% of USDT -> WETH
    //     uint256 wethReceived = swapAndSend(
    //         usdt,
    //         weth,
    //         amounts.swapAmount,
    //         address(this),
    //         false,
    //         params.deadline,
    //         true
    //     );

    //     // Swap WETH -> NECTAR and send to the pool
    //     swapAndSend(
    //         weth,
    //         address(nectarToken),
    //         wethReceived,
    //         params.pool,
    //         true,
    //         params.deadline,
    //         false
    //     );
    // }

    function multiSwapAndSend(MultiSwapParams calldata params)
        external
        onlyAllowed
    {
        require(params.pool != address(0), "Invalid pool address");
        require(params.amountIn > 0, "Invalid amountIn");
        require(block.timestamp <= params.deadline, "Deadline exceeded");

        // Borrow the USDT from the user
        _borrowFromUser(usdt, params.amountIn, params.ogRequester);

        uint256 contractBalance = IERC20(usdt).balanceOf(address(this));
        require(
            contractBalance >= params.amountIn,
            "Contract did not receive USDT!"
        );
        _validateBalanceIncrease(usdt, params.amountIn);

        // Compute amounts
        SwapAmounts memory amounts = _computeSwapAmounts(params.amountIn);

        // Transfer 20% of USDT to the dev wallet
        IERC20(usdt).safeTransfer(devWallet, amounts.devAmount);
        _validateTransfer(usdt, devWallet, amounts.devAmount);

        // Swap 70% of USDT -> WETH in a single swap
        uint256 ethReceivedToBeSwappedForNectar = swapAndSend(
            usdt,
            weth,
            amounts.swapAmount,
            address(this),
            false,
            params.deadline,
            true
        );

        require(
            ethReceivedToBeSwappedForNectar > 0,
            "Failed to swap USDT to ETH"
        );

        // Swap WETH -> NECTAR and send to the pool
        swapAndSend(
            weth,
            address(nectarToken),
            ethReceivedToBeSwappedForNectar,
            params.pool,
            true,
            params.deadline,
            false
        );

        // Handle the 10% for ETH-related operations
        // Swap 10% of USDT -> ETH
        uint256 ethReceivedForGas = swapAndSend(
            usdt,
            weth,
            amounts.secondaryAmount,
            address(this),
            false,
            params.deadline,
            true
        );

        // Distribute ETH (5% each)
        _distributeETH(ethReceivedForGas);
    }

    function internalSwapAndSend(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 deadline,
        bool isETHOut
    ) internal returns (uint256 outputAmount) {
        outputAmount = swapAndSend(
            tokenIn,
            tokenOut,
            amountIn,
            address(this),
            false,
            deadline,
            isETHOut
        );

        return outputAmount;
    }

    function _getRevertReason(bytes memory returnData)
        internal
        pure
        returns (string memory)
    {
        if (returnData.length < 68) return "Unknown error";
        assembly {
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string));
    }

    function _computeSwapAmounts(uint256 amountIn)
        internal
        pure
        returns (SwapAmounts memory)
    {
        SwapAmounts memory amounts;
        amounts.swapAmount = (amountIn * 70) / 100;
        amounts.secondaryAmount = (amountIn * 10) / 100;
        amounts.devAmount = (amountIn * 20) / 100;
        return amounts;
    }

    function _validateBalanceIncrease(address token, uint256 expectedIncrease)
        internal
        view
    {
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter >= expectedIncrease, "USDT transfer failed");
    }

    function _distributeETH(uint256 ethReceived) internal {
        uint256 gasWalletShare = ethReceived / 2;
        uint256 scConsumerShare = ethReceived - gasWalletShare;

        require(
            payable(nodeWallet).send(gasWalletShare),
            "Failed to send ETH to gas wallet"
        );

        require(
            address(vrfCoordinator) != address(0),
            "Invalid VRFCoordinator!"
        );
        require(subscriptionId > 0, "Invalid Subscription ID!");
        require(
            address(this).balance >= scConsumerShare,
            "Not enough ETH for VRF!"
        );

        VRFCoordinatorV2Interface(vrfCoordinator).fundSubscriptionWithNative{
            value: scConsumerShare
        }(subscriptionId);
    }

    function _validateTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal view {
        uint256 balanceAfter = IERC20(token).balanceOf(recipient);
        require(balanceAfter >= amount, "Transfer failed");
    }

    function _finalSwap(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) internal {
        uint256 nectarBalanceBefore = IERC20(tokenOut).balanceOf(recipient);
        swapAndSend(
            tokenIn,
            tokenOut,
            amount,
            recipient,
            true,
            deadline,
            false
        );
        uint256 nectarBalanceAfter = IERC20(tokenOut).balanceOf(recipient);
        require(nectarBalanceAfter > nectarBalanceBefore, "Final swap failed");
    }

    /**
     * @dev Update the PancakeSwap Router address.
     * @param _router New router address.
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        uniswapRouter = _router;
    }
}
