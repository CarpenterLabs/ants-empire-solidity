// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./BasePool.sol";

contract RewardPool is BasePool {
    using SafeERC20 for IERC20;
    event NectarAdded(address indexed contributor, uint256 nectarAmount);
    event NectarSent(address indexed contributor, uint256 nectarAmount);

    constructor(address _nodeWallet, address _nectarAddress)
        BasePool(_nodeWallet, _nectarAddress)
    {}

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
        //require(IERC20(nectarToken).safeTransfer(recipient, amount), "Token transfer failed");

        emit FundsSent(recipient, amount);
    }
}
