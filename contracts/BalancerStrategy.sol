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

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import './balancer/IBalancerVault.sol';
import './balancer/IBalancerPool.sol';

abstract contract BalancerStrategy is IStrategy, Ownable {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant VAULT_EXIT_RATIO_PRECISION = 1e18;
    uint256 private constant JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT = 1;
    uint256 private constant EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT = 0;

    IVault internal immutable _vault;
    IERC20 internal immutable _token;
    IBalancerVault internal immutable _balancerVault;

    string private _metadataURI;

    uint256 internal immutable _slippage;

    bytes32 internal immutable _poolId;
    address internal immutable _poolAddress;

    uint256 internal immutable _tokenIndex;
    uint256 internal immutable _tokenScale;
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
        uint256 slippage,
        string memory metadataURI
    ) {
        require(slippage <= FixedPoint.ONE, 'SWAP_SLIPPAGE_ABOVE_1');

        _vault = vault;
        _token = token;
        _balancerVault = balancerVault;
        _poolId = poolId;
        _slippage = slippage;

        _setMetadataURI(metadataURI);
        _setTokens(balancerVault, poolId);

        _tokenIndex = _getTokenIndex(token);
        _tokenScale = _getTokenScale(token);

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

    function getSlippage() public view returns (uint256) {
        return _slippage;
    }

    function getPoolAddress() external view returns (address) {
        return _poolAddress;
    }

    function getPoolId() external view returns (bytes32) {
        return _poolId;
    }

    function getTokenIndex() external view returns (uint256) {
        return _tokenIndex;
    }

    function getValueRate() external view override returns (uint256) {
        return getTokenPerBptPrice().divUp(_getBptRate());
    }

    function getTotalValue() external view override returns (uint256) {
        return _getBptBalance().mulDown(_getBptRate());
    }

    function getTokenPerBptPrice() public view virtual returns (uint256);

    function setMetadataURI(string memory metadataURI) external onlyOwner {
        _setMetadataURI(metadataURI);
    }

    function withdraw(IERC20 token, address recipient) external onlyOwner {
        if (token != _token && address(token) != _poolAddress) {
            uint256 balance = token.balanceOf(address(this));
            token.transfer(recipient, balance);
        }
    }

    function onJoin(uint256 amount, bytes memory)
        external
        override
        onlyVault
        returns (uint256 value, uint256 totalValue)
    {
        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 initialBptBalance = _getBptBalance();

        invest(_token);

        uint256 finalBptBalance = _getBptBalance();
        // Handle any potential airdrop that does not correspond to the joining user
        uint256 callerBptAmount = SafeMath.div(
            SafeMath.mul(amount, finalBptBalance.sub(initialBptBalance)),
            initialTokenBalance
        );

        uint256 bptRate = _getBptRate();
        value = callerBptAmount.mulDown(bptRate);
        totalValue = finalBptBalance.mulDown(bptRate);
    }

    function onExit(uint256 ratio, bool emergency, bytes memory data)
        external
        override
        onlyVault
        returns (address token, uint256 amount, uint256 value, uint256 totalValue)
    {
        // Invests before exiting only if it is a normal exit
        if (!emergency) {
            invest(_token);
        }

        // Use custom slippage if an emergency exit was requested
        uint256 slippage = emergency ? abi.decode(data, (uint256)) : getSlippage();
        (uint256 tokenAmount, uint256 bptAmount, uint256 bptBalance) = _exitBalancer(ratio, slippage);
        _token.approve(address(_vault), tokenAmount);

        uint256 bptRate = _getBptRate();
        value = bptAmount.mulDown(bptRate);
        totalValue = bptBalance.mulDown(bptRate);
        return (address(_token), tokenAmount, value, totalValue);
    }

    function invest(IERC20 token) public {
        require(address(token) != address(_poolAddress), 'BALANCER_INTERNAL_TOKEN');

        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            if (token != _token) {
                _swap(token, _token, balance, getSlippage());
            }
            _joinBalancer(_token.balanceOf(address(this)));
        }
    }

    function _joinBalancer(uint256 amount) internal {
        uint256 minimumBpt = _getMinAmountOut(_token, IERC20(_poolAddress), amount, getSlippage());
        (IERC20[] memory tokens, uint256[] memory amountsIn) = _buildBalancerTokensParams(_tokenIndex, amount);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBpt),
            fromInternalBalance: false
        });

        _token.approve(address(_balancerVault), amount);
        _balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    function _exitBalancer(uint256 ratio, uint256 slippage)
        internal
        returns (uint256 tokenBalance, uint256 bptAmount, uint256 bptBalance)
    {
        bptAmount = SafeMath.div(_getBptBalance().mulDown(ratio), VAULT_EXIT_RATIO_PRECISION);
        uint256 minAmount = _getMinAmountOut(IERC20(_poolAddress), _token, bptAmount, slippage);
        (IERC20[] memory tokens, uint256[] memory minAmountsOut) = _buildBalancerTokensParams(_tokenIndex, minAmount);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encodePacked(EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmount, _tokenIndex),
            toInternalBalance: false
        });

        _balancerVault.exitPool(_poolId, address(this), payable(address(this)), request);

        tokenBalance = _token.balanceOf(address(this));
        bptBalance = _getBptBalance();
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 slippage) internal returns (uint256) {
        require(tokenIn != tokenOut, 'SWAP_SAME_TOKEN');

        uint256 minAmountOut = _getMinAmountOut(tokenIn, tokenOut, amountIn, slippage);
        ISwapConnector swapConnector = ISwapConnector(_vault.swapConnector());
        uint256 expectedAmountOut = swapConnector.getAmountOut(address(tokenIn), address(tokenOut), amountIn);
        require(expectedAmountOut >= minAmountOut, 'EXPECTED_SWAP_MIN_AMOUNT');

        if (amountIn > 0) {
            tokenIn.safeTransfer(address(swapConnector), amountIn);
        }

        uint256 preBalanceIn = tokenIn.balanceOf(address(this));
        uint256 preBalanceOut = tokenOut.balanceOf(address(this));
        (uint256 remainingIn, uint256 amountOut) = swapConnector.swap(
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

    function _getMinAmountOut(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 slippage)
        internal
        view
        returns (uint256 minAmountOut)
    {
        uint256 price;
        if (address(tokenIn) == _poolAddress && tokenOut == _token) {
            price = getTokenPerBptPrice();
        } else if (tokenIn == _token && address(tokenOut) == _poolAddress) {
            price = FixedPoint.ONE.divUp(getTokenPerBptPrice());
        } else {
            price = IPriceOracle(_vault.priceOracle()).getTokenPrice(address(tokenOut), address(tokenIn));
        }

        minAmountOut = amountIn.mulUp(price).mulUp(FixedPoint.ONE - slippage);
    }

    function _getBptRate() internal view returns (uint256) {
        return IBalancerPool(_poolAddress).getRate();
    }

    function _getBptBalance() internal view returns (uint256) {
        return IERC20(_poolAddress).balanceOf(address(this));
    }

    function _getTokenScale(IERC20 token) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(address(token)).decimals();
        require(decimals <= 18, 'TOKEN_WORKS_WITH_BIGGER_DECIMALS');
        uint256 diff = 18 - decimals;
        return 10**diff;
    }

    function _getTokenIndex(IERC20 token) internal view returns (uint256) {
        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length; i++) if (_tokens[i] == token) return i;
        revert('TOKEN_DOES_NOT_BELONG_TO_POOL');
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

    function _setMetadataURI(string memory metadataURI) private {
        _metadataURI = metadataURI;
        emit SetMetadataURI(metadataURI);
    }

    function _setTokens(IBalancerVault vault, bytes32 poolId) private {
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _tokens = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) _tokens[i] = tokens[i];
    }
}
