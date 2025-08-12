// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./IUniswapV2ERC20.sol";
import "./SafeMath.sol";

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;

    string public constant override name = "Uniswap V2";
    string public constant override symbol = "UNI-V2";
    uint8 public constant override decimals = 18;
    uint  public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    bytes32 public override DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint value,uint nonce,uint deadline)");
    bytes32 public constant override PERMIT_TYPEHASH = 
        0xd505accf2f3c8d6c4f16f5879dbf1f7f293a5ac837c2a96c01d04e50e7c37bdc;
    mapping(address => uint) public override nonces;

    constructor() {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        uint allowed = allowance[from][msg.sender];
        if (allowed != type(uint).max) {
            _approve(from, msg.sender, allowed.sub(value));
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(
        address owner, 
        address spender, 
        uint value, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "UniswapV2ERC20: EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "UniswapV2ERC20: INVALID_SIGNATURE"
        );
        _approve(owner, spender, value);
    }
}
