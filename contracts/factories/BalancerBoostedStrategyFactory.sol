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

import './BalancerStrategyFactory.sol';
import '../BalancerStrategy.sol';
import '../BalancerBoostedStrategy.sol';
import '../balancer/pools/IBalancerLinearPool.sol';

/**
 * @title BalancerBoostedStrategyFactory
 * @dev Factory contract to create BalancerBoostedStrategy contracts
 */
contract BalancerBoostedStrategyFactory is BalancerStrategyFactory {
    /**
     * @dev Initializes the factory contract
     * @param _vault Protocol vault reference
     * @param _balancerVault Balancer V2 Vault reference
     * @param _balancerMinter Balancer Minter reference
     * @param _gaugeFactory Gauge factory to fetch pool gauges
     * @param _gaugeType Type of the gauges created by the associated factory: liquidity or rewards only
     */
    constructor(
        IVault _vault,
        IBalancerVault _balancerVault,
        IBalancerMinter _balancerMinter,
        IGaugeFactory _gaugeFactory,
        IGauge.Type _gaugeType
    ) BalancerStrategyFactory(_vault, _balancerVault, _balancerMinter, _gaugeFactory, _gaugeType) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Internal method to create a new BalancerBoostedStrategy
     * @param token Token to be used as the strategy entry point
     * @param poolId Id of the Balancer pool to create the strategy for
     * @param gauge Address of the gauge associated to the pool to be used
     * @param slippage Slippage value to be used in order to swap rewards
     * @param metadata Metadata URI associated to the strategy
     */
    function _create(IERC20 token, bytes32 poolId, IGauge gauge, uint256 slippage, string memory metadata)
        internal
        override
        returns (BalancerStrategy)
    {
        bytes32 linearPoolId = _getLinearPoolId(poolId, token);
        return
            new BalancerBoostedStrategy(
                vault,
                balancerVault,
                balancerMinter,
                token,
                poolId,
                linearPoolId,
                gauge,
                gaugeType,
                slippage,
                metadata
            );
    }

    function _getLinearPoolId(bytes32 poolId, IERC20 token) private view returns (bytes32) {
        (address pool, ) = balancerVault.getPool(poolId);
        require(pool != address(0), 'INVALID_BALANCER_POOL_ID');
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) != pool) {
                IBalancerLinearPool linearPool = IBalancerLinearPool(address(tokens[i]));
                if (linearPool.getMainToken() == address(token)) {
                    return linearPool.getPoolId();
                }
            }
        }
        revert('LINEAR_POOL_ID_NOT_FOUND');
    }
}
