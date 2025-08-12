// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/security/ReentrancyGuard.sol";

contract NectarFaucet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token; // The ERC20 token distributed by the faucet
    uint256 public tokenAmount = 3 * 10**18; // 3 NECTAR tokens per claim (assumes 18 decimals)
    uint256 public claimCooldown = 24 hours; // 24-hour cooldown between claims

    mapping(address => uint256) public lastClaim; // Tracks the last claim time for each user

    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event FaucetConfigured(address indexed token, uint256 amount, uint256 cooldown);

    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    /**
     * @dev Allows a user to claim tokens if the cooldown has passed.
     */
    function claimTokens() external nonReentrant {
        require(block.timestamp - lastClaim[msg.sender] >= claimCooldown, "Claim cooldown active");

        // Update last claim timestamp
        lastClaim[msg.sender] = block.timestamp;

        // Transfer tokens to the user
        require(token.balanceOf(address(this)) >= tokenAmount, "Faucet: Not enough tokens");
        token.safeTransfer(msg.sender, tokenAmount);

        emit TokensClaimed(msg.sender, tokenAmount, block.timestamp);
    }

    /**
     * @dev Allows the owner to configure the faucet.
     * @param _tokenAmount The amount of tokens distributed per claim.
     * @param _claimCooldown The cooldown period between claims in seconds.
     */
    function configureFaucet(uint256 _tokenAmount, uint256 _claimCooldown) external onlyOwner nonReentrant {
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_claimCooldown > 0, "Cooldown must be greater than 0");

        tokenAmount = _tokenAmount;
        claimCooldown = _claimCooldown;

        emit FaucetConfigured(address(token), tokenAmount, claimCooldown);
    }

    /**
     * @dev Allows the owner to withdraw unused tokens from the faucet.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 _amount) external onlyOwner nonReentrant {
        require(token.balanceOf(address(this)) >= _amount, "Not enough tokens in faucet");
        token.safeTransfer(owner(), _amount);
    }

    /**
     * @dev Returns the remaining cooldown time for a user.
     * @param _user The address of the user.
     */
    function getRemainingCooldown(address _user) external view returns (uint256) {
        if (block.timestamp - lastClaim[_user] >= claimCooldown) {
            return 0;
        }
        return claimCooldown - (block.timestamp - lastClaim[_user]);
    }

    /**
     * @dev Fallback function to prevent accidental ETH deposits.
     */
    receive() external payable {
        revert("Faucet does not accept ETH");
    }
}