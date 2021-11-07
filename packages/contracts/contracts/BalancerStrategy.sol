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

import '@mimic-fi/v1-vault/contracts/interfaces/IStrategy.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/ISwapConnector.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/IPriceOracle.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/IVault.sol';
import '@mimic-fi/v1-vault/contracts/libraries/FixedPoint.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './balancer/IBalancerVault.sol';

abstract contract BalancerStrategy is IStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _MAX_SLIPPAGE = 1e18; // 100%

    uint256 private constant JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT = 1;
    uint256 private constant EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT = 0;

    IVault internal immutable _vault;
    IERC20 internal immutable _token;
    IERC20 internal immutable _balToken;
    IBalancerVault internal immutable _balancerVault;

    string private _metadataURI;
    uint256 internal _totalShares;

    uint256 internal immutable _slippage;
    uint256 internal immutable _tokenScale;

    bytes32 internal immutable _poolId;
    address internal immutable _poolAddress;
    uint256 internal immutable _tokenIndex;
    IERC20[] internal _tokens;

    modifier onlyVault() {
        require(address(_vault) == msg.sender, 'CALLER_IS_NOT_VAULT');
        _;
    }

    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        IERC20 balToken,
        uint256 slippage,
        string memory metadata
    ) {
        require(slippage <= _MAX_SLIPPAGE, 'SWAP_MAX_SLIPPAGE');

        _vault = vault;
        _token = token;
        _balancerVault = balancerVault;
        _poolId = poolId;
        _balToken = balToken;
        _slippage = slippage;
        _metadataURI = metadata;

        _setTokens(balancerVault, poolId);
        _tokenScale = _getTokenScale(token);
        _tokenIndex = _getTokenIndex(token);
        (_poolAddress, ) = balancerVault.getPool(poolId);
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

    function getTotalShares() external view override returns (uint256) {
        return _totalShares;
    }

    function getRate() external view override returns (uint256) {
        // TODO: delete function
        return 0;
    }

    function getTokenPerBPTPrice() public view virtual returns (uint256);

    function onJoin(uint256 amount, bytes memory) external override onlyVault returns (uint256) {
        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 initialBPTBalance = IERC20(_poolAddress).balanceOf(address(this));

        invest(_token);

        uint256 finalBPTBalance = IERC20(_poolAddress).balanceOf(address(this));
        uint256 callerBPTAmount = amount.mul(finalBPTBalance.sub(initialBPTBalance)).div(initialTokenBalance);

        uint256 shares = _totalShares == 0
            ? callerBPTAmount
            : _totalShares.mul(callerBPTAmount).div(finalBPTBalance.sub(callerBPTAmount));

        _totalShares = _totalShares.add(shares);

        return shares;
    }

    function onExit(uint256 shares, bool, bytes memory) external override onlyVault returns (address, uint256) {
        invest(_token);

        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 initialBPTBalance = IERC20(_poolAddress).balanceOf(address(this));

        uint256 bptAmount = shares.mul(initialBPTBalance).div(_totalShares);

        _exit(bptAmount);

        uint256 finalTokenAmount = _token.balanceOf(address(this));
        uint256 amount = finalTokenAmount.sub(initialTokenBalance);

        _totalShares = _totalShares.sub(shares);

        _token.approve(address(_vault), amount);
        return (address(_token), amount);
    }

    function invest(IERC20 token) public {
        require(address(token) != address(_poolAddress), 'BALANCER_INTERNAL_TOKEN');

        uint256 tokenBalance = token.balanceOf(address(this));

        if (token != _token) {
            if (tokenBalance > 0) {
                _swap(token, _token, tokenBalance);
            }
            tokenBalance = _token.balanceOf(address(this));
        }

        if (tokenBalance > 0) {
            _join(tokenBalance);
        }
    }

    function _join(uint256 amount) internal {
        uint256 minimumBPT = _getMinAmountOut(_token, IERC20(_poolAddress), amount);
        (IERC20[] memory tokens, uint256[] memory amountsIn) = _buildBalancerTokensParams(_tokenIndex, amount);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT),
            fromInternalBalance: false
        });

        _token.approve(address(_balancerVault), amount);
        _balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    function _exit(uint256 bptAmount) internal {
        uint256 minAmount = _getMinAmountOut(IERC20(_poolAddress), _token, bptAmount);
        (IERC20[] memory tokens, uint256[] memory minAmountsOut) = _buildBalancerTokensParams(_tokenIndex, minAmount);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encodePacked(EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmount, _tokenIndex),
            toInternalBalance: false
        });

        _balancerVault.exitPool(_poolId, address(this), payable(address(this)), request);
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) internal returns (uint256) {
        require(tokenIn != tokenOut, 'SWAP_SAME_TOKEN');

        uint256 minAmountOut = _getMinAmountOut(tokenIn, tokenOut, amountIn);
        ISwapConnector swapConnector = ISwapConnector(_vault.swapConnector());
        uint256 expectedAmountOut = swapConnector.getAmountOut(address(tokenIn), address(tokenOut), amountIn);
        require(expectedAmountOut >= minAmountOut, 'EXPECTED_SWAP_MIN_AMOUNT');

        if (amountIn > 0) {
            tokenIn.safeTransfer(address(swapConnector), amountIn);
        }

        uint256 preBalanceIn = tokenIn.balanceOf(address(this));
        uint256 preBalanceOut = tokenOut.balanceOf(address(this));
        (uint256 remainingIn, uint256 amountOut) = ISwapConnector(swapConnector).swap(
            address(tokenIn),
            address(tokenOut),
            amountIn,
            minAmountOut,
            block.timestamp,
            new bytes(0)
        );

        require(amountOut >= minAmountOut, 'SWAP_MIN_AMOUNT');
        uint256 postBalanceIn = tokenIn.balanceOf(address(this));
        require(postBalanceIn >= preBalanceIn.add(remainingIn), 'SWAP_INVALID_REMAINING_IN');
        uint256 postBalanceOut = tokenOut.balanceOf(address(this));
        require(postBalanceOut >= preBalanceOut.add(amountOut), 'SWAP_INVALID_AMOUNT_OUT');

        return amountOut;
    }

    function _getMinAmountOut(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256 minAmountOut)
    {
        uint256 price;
        if (address(tokenIn) == _poolAddress) {
            price = getTokenPerBPTPrice();
        } else if (address(tokenOut) == _poolAddress) {
            price = FixedPoint.div(FixedPoint.ONE, getTokenPerBPTPrice());
        } else {
            address priceOracle = _vault.priceOracle();
            price = IPriceOracle(priceOracle).getTokenPrice(address(tokenOut), address(tokenIn));
        }

        minAmountOut = FixedPoint.mulUp(FixedPoint.mulUp(amountIn, price), FixedPoint.ONE - _slippage);
    }

    function _getTokenScale(IERC20 token) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(address(token)).decimals();
        require(decimals > 18, 'TOKEN_WORKS_WITH_BIGGER_DECIMALS');
        uint256 diff = 18 - decimals;
        return 10**diff;
    }

    function _getTokenIndex(IERC20 token) internal view returns (uint256) {
        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length; i++) if (_tokens[i] == token) return i;
        revert('TOKEN_DOES_NOT_BELONG_TO_POOL');
    }

    function _setTokens(IBalancerVault vault, bytes32 poolId) internal {
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _tokens = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) _tokens[i] = tokens[i];
    }

    function _buildBalancerTokensParams(uint256 index, uint256 amount)
        internal
        view
        returns (IERC20[] memory tokens, uint256[] memory amounts)
    {
        tokens = new IERC20[](_tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) tokens[i] = _tokens[i];
        amounts = new uint256[](tokens.length);
        amounts[index] = amount;
    }
}
