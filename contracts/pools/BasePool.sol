// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";

abstract contract BasePool is Ownable {
    using SafeERC20 for IERC20;
    event FundsReceived(address indexed sender, uint256 amount);
    event FundsWithdrawn(address indexed owner, uint256 amount);
    event ETHWithdrawn(address indexed recipient, uint256 amount);
    event EmergencyWithdrawal(
        address indexed owner,
        address indexed recipient,
        uint256 amount
    );
    event FundsSent(address indexed recipient, uint256 amount);

    mapping(address => bool) public allowedContracts;

    IERC20 public nectarToken; // The ERC-20 token this pool works with
    address public nodeWallet;

    constructor(address _nodeWallet, address _nectarAddress) {
        require(_nectarAddress != address(0), "Invalid token address");
        nectarToken = IERC20(_nectarAddress);

        allowedContracts[msg.sender] = true;
        allowedContracts[_nodeWallet] = true;
        nodeWallet = _nodeWallet;
    }

    function approveSpender(address scAddress) external onlyOwner {
        nectarToken.approve(scAddress, type(uint256).max);
    }

    function withdraw(uint256 amount) external onlyOwner {
        uint256 balance = nectarToken.balanceOf(address(this));
        require(amount > 0 && amount <= balance, "Invalid withdrawal amount");

        // Transfer tokens to the owner
        require(nectarToken.transfer(owner(), amount), "Token transfer failed");
        emit FundsWithdrawn(owner(), amount);
    }

    function emergencyWithdraw(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");

        uint256 balance = nectarToken.balanceOf(address(this));
        require(balance > 0, "No funds available for withdrawal");

        // Transfer all tokens to the recipient
        require(
            nectarToken.transfer(recipient, balance),
            "Token transfer failed"
        );
        emit EmergencyWithdrawal(owner(), recipient, balance);
    }

    function getBalance() external view returns (uint256) {
        return nectarToken.balanceOf(address(this));
    }

    modifier onlyAllowed() {
        require(allowedContracts[msg.sender], "Not an allowed contract");
        _;
    }

    function addAllowedContract(address _contract) external onlyOwner {
        allowedContracts[_contract] = true;
    }

    /// @notice Receive function to accept ETH sent to the contract
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    /**
     * @notice (Optional) Withdraw all ETH to the owner in one call.
     */
    function withdrawAllETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ETH transfer failed");

        emit ETHWithdrawn(owner(), balance);
    }

    /**
     * @notice Allows the owner to update the address of the nectarToken (ERC20 token).
     * @param _newToken Address of the new token contract.
     */
    function updateNectarToken(address _newToken) external onlyOwner {
        require(_newToken != address(0), "Invalid token address");
        nectarToken = IERC20(_newToken);
    }

    /**
     * @notice Allows the owner to update the nodeWallet address.
     * @param _newNodeWallet Address of the new node wallet.
     */
    function updateNodeWallet(address _newNodeWallet) external onlyOwner {
        require(_newNodeWallet != address(0), "Invalid node wallet address");
        allowedContracts[_newNodeWallet] = true; // Optionally add to allowed contracts
        nodeWallet = _newNodeWallet;
    }
}
