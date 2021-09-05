// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "@mimic-fi/v1-core/contracts/interfaces/IStrategy.sol";
import "@mimic-fi/v1-core/contracts/interfaces/ISwapConnector.sol";
import "@mimic-fi/v1-core/contracts/interfaces/IPriceOracle.sol";
import "@mimic-fi/v1-core/contracts/interfaces/IVault.sol";
import "@mimic-fi/v1-core/contracts/libraries/FixedPoint.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IBalancerVault.sol";

abstract contract BalancerStrategy is IStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _SLIPPAGE = 1e16; // 1%

    uint256 private constant JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT = 1;
    uint256 private constant EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT =
        0;

    IVault internal immutable _vault;
    IERC20 internal immutable _token;

    IBalancerVault internal immutable _balancerVault;
    bytes32 internal immutable _poolId;
    address internal immutable _poolAddress;
    uint256 internal immutable _tokenIndex;
    IERC20 internal immutable _balToken;

    uint256 internal _totalShares;
    string internal _metadataURI;

    modifier onlyVault() {
        require(address(_vault) == msg.sender, "CALLER_IS_NOT_VAULT");
        _;
    }

    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        uint256 tokenIndex,
        IERC20 balToken,
        string memory metadata
    ) {
        _vault = vault;
        _token = token;

        _balancerVault = balancerVault;
        _poolId = poolId;
        _tokenIndex = tokenIndex;
        _balToken = balToken;

        _metadataURI = metadata;

        (_poolAddress, ) = balancerVault.getPool(poolId);

        token.approve(address(vault), FixedPoint.MAX_UINT256);
        token.approve(address(balancerVault), FixedPoint.MAX_UINT256);
    }

    function getVault() external view returns (address) {
        return address(_vault);
    }

    function getToken() external view override returns (address) {
        return address(_token);
    }

    function getMetadataURI() external view override returns (string memory) {
        return _metadataURI;
    }

    function getTokenBalance() external view override returns (uint256) {
        uint256 bptTokenBalance = IERC20(_poolAddress).balanceOf(address(this));

        uint256 price = _getTokenPerBPTPrice();

        uint256 unscaledBalance = FixedPoint.mul(bptTokenBalance, price);
        return unscaledBalance;
    }

    function getTotalShares() external view override returns (uint256) {
        return _totalShares;
    }

    function onJoin(uint256 amount, bytes memory)
        external
        override
        onlyVault
        returns (uint256)
    {
        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 initialBPTBalance = IERC20(_poolAddress).balanceOf(
            address(this)
        );

        claim();
        invest(_token);

        uint256 finalBPTBalance = IERC20(_poolAddress).balanceOf(address(this));

        uint256 callerBPTAmount = amount
        .mul(finalBPTBalance.sub(initialBPTBalance))
        .div(initialTokenBalance);

        uint256 shares = _totalShares == 0
            ? callerBPTAmount
            : _totalShares.mul(callerBPTAmount).div(
                finalBPTBalance.sub(callerBPTAmount)
            );

        _totalShares = _totalShares.add(shares);

        return shares;
    }

    function onExit(uint256 shares, bytes memory)
        external
        override
        onlyVault
        returns (address, uint256)
    {
        claim();
        invest(_token);

        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 initialBPTBalance = IERC20(_poolAddress).balanceOf(
            address(this)
        );

        uint256 bptAmount = shares.mul(initialBPTBalance).div(_totalShares);

        _exit(bptAmount);

        uint256 finalTokenAmount = _token.balanceOf(address(this));
        uint256 amount = finalTokenAmount.sub(initialTokenBalance);

        _totalShares = _totalShares.sub(shares);

        return (address(_token), amount);
    }

    function approveVault(IERC20 token) external {
        //BPT and BAL protected
        require(
            address(token) != address(_poolAddress),
            "BALANCER_INTERNAL_TOKEN"
        );
        require(
            address(token) != address(_balToken),
            "BALANCER_INTERNAL_TOKEN"
        );

        token.approve(address(_vault), FixedPoint.MAX_UINT256);
    }

    function invest(IERC20 token) public {
        require(
            address(token) != address(_poolAddress),
            "BALANCER_INTERNAL_TOKEN"
        );

        uint256 tokenBalance = token.balanceOf(address(this));

        if (token != _token) {
            _swap(token, _token, tokenBalance);
            tokenBalance = _token.balanceOf(address(this));
        }

        _join(tokenBalance);
    }

    function claim() public {
        //TODO: claim and invest BAL
        //swap BAL for token
    }

    //Internal

    function _getTokenPerBPTPrice() internal view virtual returns (uint256);

    //Private

    function _join(uint256 amount) private {
        (IERC20[] memory tokens, , ) = _balancerVault.getPoolTokens(_poolId);

        uint256[] memory amountsIn = new uint256[](tokens.length);
        amountsIn[_tokenIndex] = amount;

        uint256 minimumBPT = _getMinAmountOut(
            _token,
            IERC20(_poolAddress),
            amount
        );

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault
        .JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(
                JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsIn,
                minimumBPT
            ),
            fromInternalBalance: false
        });

        _balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    function _exit(uint256 bptAmount) private {
        (IERC20[] memory tokens, , ) = _balancerVault.getPoolTokens(_poolId);

        uint256 minAmountOut = _getMinAmountOut(
            IERC20(_poolAddress),
            _token,
            bptAmount
        );

        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[_tokenIndex] = minAmountOut;

        //Exit
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault
        .ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encodePacked(
                EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                bptAmount,
                _tokenIndex
            ),
            toInternalBalance: false
        });
        _balancerVault.exitPool(
            _poolId,
            address(this),
            payable(address(this)),
            request
        );
    }

    function _swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn
    ) private returns (uint256) {
        require(tokenIn != tokenOut, "SWAP_SAME_TOKEN");

        address swapConnector = _vault.swapConnector();

        uint256 minAmountOut = _getMinAmountOut(tokenIn, tokenOut, amountIn);

        require(
            ISwapConnector(swapConnector).getAmountOut(
                address(tokenIn),
                address(tokenOut),
                amountIn
            ) >= minAmountOut,
            "EXPECTED_SWAP_MIN_AMOUNT"
        );

        _safeTransfer(tokenIn, swapConnector, amountIn);

        uint256 preBalanceIn = tokenIn.balanceOf(address(this));
        uint256 preBalanceOut = tokenOut.balanceOf(address(this));
        (uint256 remainingIn, uint256 amountOut) = ISwapConnector(swapConnector)
        .swap(
            address(tokenIn),
            address(tokenOut),
            amountIn,
            minAmountOut,
            block.timestamp,
            ""
        );

        require(amountOut >= minAmountOut, "SWAP_MIN_AMOUNT");

        uint256 postBalanceIn = tokenIn.balanceOf(address(this));
        // require(
        //     postBalanceIn.sub(preBalanceIn) >= remainingIn,
        //     "SWAP_INVALID_REMAINING_IN"
        // );

        uint256 postBalanceOut = tokenOut.balanceOf(address(this));
        require(
            postBalanceOut.sub(preBalanceOut) >= amountOut,
            "SWAP_INVALID_AMOUNT_OUT"
        );

        return amountOut;
    }

    function _getMinAmountOut(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn
    ) private view returns (uint256 minAmountOut) {
        address priceOracle = _vault.priceOracle();

        uint256 price;
        if (address(tokenIn) == _poolAddress) {
            price = _getTokenPerBPTPrice();
        } else if (address(tokenOut) == _poolAddress) {
            price = FixedPoint.div(FixedPoint.ONE, _getTokenPerBPTPrice());
        } else {
            price = IPriceOracle(priceOracle).getTokenPrice(
                address(tokenOut),
                address(tokenIn)
            );
        }

        minAmountOut = FixedPoint.mulUp(
            FixedPoint.mulUp(amountIn, price),
            FixedPoint.ONE - _SLIPPAGE
        );
    }

    function _safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) private {
        if (amount > 0) {
            token.safeTransfer(to, amount);
        }
    }
}
