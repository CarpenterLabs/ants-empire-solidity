// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @dev Minimal SafeMath library that replicates the older 0.6.x style usage.
 * Solidity 0.8+ has built-in overflow checks, so this is mostly for legacy compatibility.
 */
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x, "SafeMath: addition overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require(y <= x, "SafeMath: subtraction underflow");
        z = x - y;
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        // Gas optimization: this is cheaper than requiring 'x' not being zero, but the benefit is lost
        // if 'y' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (x == 0) {
            return 0;
        }
        z = x * y;
        require(z / x == y, "SafeMath: multiplication overflow");
    }
}
