// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";

contract MockWETH is IERC20 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping (address => uint) public override balanceOf;
    mapping (address => mapping (address => uint)) public override allowance;
    uint public override totalSupply;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad, "MockWETH: insufficient balance");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
        emit Transfer(msg.sender, address(0), wad);
    }

    function approve(address guy, uint wad) public override returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public override returns (bool) {
        return _transfer(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public override returns (bool) {
        uint allowed = allowance[src][msg.sender];
        if (allowed != type(uint).max) {
            require(allowed >= wad, "MockWETH: allowance exceeded");
            allowance[src][msg.sender] = allowed - wad;
        }
        return _transfer(src, dst, wad);
    }

    function _transfer(address src, address dst, uint wad) internal returns (bool) {
        require(dst != address(0), "MockWETH: transfer to zero address");
        require(balanceOf[src] >= wad, "MockWETH: balance exceeded");
        balanceOf[src] = balanceOf[src] - wad;
        balanceOf[dst] = balanceOf[dst] + wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}
