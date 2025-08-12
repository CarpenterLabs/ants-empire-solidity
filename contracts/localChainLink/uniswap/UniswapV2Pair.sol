// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./UniswapV2ERC20.sol";
import "./Math.sol";
import "./UQ112x112.sol";
import "./IERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Callee.sol";

contract UniswapV2Pair is UniswapV2ERC20 {
    using SafeMath for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;          
    uint112 private reserve1;          
    uint32  private blockTimestampLast; 

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // reentrancy guard
    uint private _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1, "UniswapV2Pair: LOCKED");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Swap(
        address indexed sender, 
        uint amount0In, 
        uint amount1In, 
        uint amount0Out, 
        uint amount1Out, 
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    function getReserves() public view returns (
        uint112 _reserve0, 
        uint112 _reserve1, 
        uint32 _blockTimestampLast
    ) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "UniswapV2Pair: TRANSFER_FAILED");
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2Pair: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves
    function _update(
        uint balance0, 
        uint balance1, 
        uint112 _reserve0, 
        uint112 _reserve1
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2Pair: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _updateK(uint _reserve0, uint _reserve1) private {
        kLast = uint(_reserve0).mul(_reserve1);
    }

    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = false; 
        // For a local minimal environment, we can skip feeTo logic or keep it as is:
        address feeTo = IUniswapV2Factory(factory).feeTo();
        if (feeTo != address(0)) {
            feeOn = true;
        }
        uint _kLast = kLast; 

        if (_kLast == 0) {
            _updateK(_reserve0, _reserve1);
        }

        if (totalSupply == 0) {
            liquidity = Math.sqrt(uint(amount0).mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY
        } else {
            liquidity = Math.min(
                amount0.mul(totalSupply) / _reserve0, 
                amount1.mul(totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, "UniswapV2Pair: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) {
            _updateK(reserve0, reserve1);
        }
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0; 
        address _token1 = token1; 
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = false; 
        address feeTo = IUniswapV2Factory(factory).feeTo();
        if (feeTo != address(0)) {
            feeOn = true;
        }
        uint _totalSupply = totalSupply; // gas savings
        // using balances ensures pro-rata distribution
        amount0 = liquidity.mul(balance0) / _totalSupply; 
        amount1 = liquidity.mul(balance1) / _totalSupply; 
        require(amount0 > 0 && amount1 > 0, "UniswapV2Pair: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) {
            _updateK(reserve0, reserve1);
        }
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint amount0Out, 
        uint amount1Out, 
        address to, 
        bytes calldata data
    ) external lock {
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2Pair: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2Pair: INSUFFICIENT_LIQUIDITY");

        uint balance0;
        uint balance1;
        {
            address _token0 = token0; 
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2Pair: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            if (data.length > 0) {
                IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            }
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out 
            ? balance0 - (_reserve0 - amount0Out) 
            : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out 
            ? balance1 - (_reserve1 - amount1Out) 
            : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2Pair: INSUFFICIENT_INPUT_AMOUNT");

        // The core swap fee = 0.3%. 
        // Check that (balance0 * balance1) >= (reserve0 * reserve1)
        {
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(
                balance0Adjusted.mul(balance1Adjusted) >= 
                uint(_reserve0).mul(_reserve1).mul(1000**2),
                "UniswapV2Pair: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(
            msg.sender, 
            amount0In, 
            amount1In, 
            amount0Out, 
            amount1Out, 
            to
        );
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; 
        address _token1 = token1; 
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        _safeTransfer(_token0, to, balance0.sub(reserve0));
        _safeTransfer(_token1, to, balance1.sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1, reserve0, reserve1);
    }
}
