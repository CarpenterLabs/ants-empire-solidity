// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address _owner, address _spender) external view returns (uint);
    function approve(address _spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
}
