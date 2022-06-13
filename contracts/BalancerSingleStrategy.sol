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

import './BalancerStrategy.sol';

/**
 * @title BalancerSingleStrategy
 * @dev This strategy provides liquidity in Balancer pools through joins.
 */
abstract contract BalancerSingleStrategy is BalancerStrategy {
    using FixedPoint for uint256;

    // ID of the action type used internally by Balancer in order to join a Balancer pool
    uint256 private constant JOIN_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

    // ID of the action type used internally by Balancer in order to exit a Balancer pool
    uint256 private constant EXIT_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT = 0;

    // Index of the entry point token in the list of tokens of the Balancer pool
    uint256 internal immutable _tokenIndex;

    /**
     * @dev Initializes the Balancer strategy contract
     * @param vault Protocol vault reference
     * @param balancerVault Balancer V2 Vault reference
     * @param balancerMinter Balancer Minter reference
     * @param token Token to be used as the strategy entry point
     * @param poolId Id of the Balancer pool to create the strategy for
     * @param gauge Address of the gauge associated to the pool to be used
     * @param gaugeType Type of the gauges created by the associated factory: liquidity or rewards only
     * @param slippage Slippage value to be used in order to swap rewards
     * @param metadataURI Metadata URI associated to the strategy
     */
    constructor(
        IVault vault,
        IBalancerVault balancerVault,
        IBalancerMinter balancerMinter,
        IERC20 token,
        bytes32 poolId,
        IGauge gauge,
        IGauge.Type gaugeType,
        uint256 slippage,
        string memory metadataURI
    ) BalancerStrategy(vault, balancerVault, balancerMinter, token, poolId, gauge, gaugeType, slippage, metadataURI) {
        _tokenIndex = _getTokenIndex(token);
    }

    /**
     * @dev Tells the index of the entry point token in the list of tokens of the Balancer pool
     */
    function getTokenIndex() external view returns (uint256) {
        return _tokenIndex;
    }

    /**
     * @dev Internal function to join the Balancer pool
     * @param amount Amount of strategy tokens to invest
     * @param slippage Slippage to be used to join the Balancer pool
     */
    function _joinBalancer(uint256 amount, uint256 slippage) internal override returns (uint256 bptBalance) {
        if (amount == 0) return 0;

        // Estimate how much BPT the strategy will get after joining with `amount` tokens
        uint256 minimumBpt = _getMinAmountOut(_token, _pool, amount, slippage);

        // Build the Balancer join data using the strategy token as the only entry point, which will result in
        // a join-swap, and ask the minimum BPT based on what was estimated right before
        (IERC20[] memory tokens, uint256[] memory amountsIn) = _buildBalancerTokensParams(amount);
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(JOIN_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBpt),
            fromInternalBalance: false
        });

        // Approve tokens and join the Balancer pool
        _token.approve(address(_balancerVault), amount);
        _balancerVault.joinPool(_poolId, address(this), address(this), request);

        // Approve and stake the total BPT in the corresponding gauge
        bptBalance = _pool.balanceOf(address(this));
        _pool.approve(address(_gauge), bptBalance);
        _gauge.deposit(bptBalance);
    }

    /**
     * @dev Internal function to exit the Balancer pool
     * @param ratio Ratio of the invested position to exit
     * @param slippage Slippage to be used to exit the Balancer pool
     */
    function _exitBalancer(uint256 ratio, uint256 slippage)
        internal
        override
        returns (uint256 tokenBalance, uint256 bptAmount, uint256 bptBalance)
    {
        // Compute the amount of BPT to exit from the Balancer pool based on the given ratio and unstake it from the gauge
        uint256 initialStakedBptBalance = _gauge.balanceOf(address(this));
        bptAmount = SafeMath.div(initialStakedBptBalance.mulDown(ratio), VAULT_EXIT_RATIO_PRECISION);
        _gauge.withdraw(bptAmount);

        // Estimate the expected amount out Compute the amount of BPT to exit from the Balancer pool based on the given ratio
        // The user is exiting the requested ratio, no other investments are affected
        uint256 minAmount = _getMinAmountOut(_pool, _token, bptAmount, slippage);

        // Build the Balancer exit data using the strategy token as the only entry point, which will result in
        // an exit-swap, and ask the minimum amount out based on what was estimated right before
        (IERC20[] memory tokens, uint256[] memory minAmountsOut) = _buildBalancerTokensParams(minAmount);
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encodePacked(EXIT_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmount, _tokenIndex),
            toInternalBalance: false
        });

        // Exit Balancer pool
        _balancerVault.exitPool(_poolId, address(this), payable(address(this)), request);
        tokenBalance = _token.balanceOf(address(this));
        bptBalance = initialStakedBptBalance.sub(bptAmount);
    }

    /**
     * @dev Builds the params list required to interact with a Balancer pool.
     * @param amount Amount of strategy tokens to join or exit
     */
    function _buildBalancerTokensParams(uint256 amount)
        private
        view
        returns (IERC20[] memory tokens, uint256[] memory amounts)
    {
        tokens = new IERC20[](_tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) tokens[i] = _tokens[i];
        amounts = new uint256[](tokens.length);
        amounts[_tokenIndex] = amount;
    }

    /**
     * @dev Tells the index of the strategy token in the list of tokens associated to the Balancer pool.
     * @param token Address of the token being queried
     */
    function _getTokenIndex(IERC20 token) private view returns (uint256) {
        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length; i++) if (_tokens[i] == token) return i;
        revert('TOKEN_DOES_NOT_BELONG_TO_POOL');
    }
}
