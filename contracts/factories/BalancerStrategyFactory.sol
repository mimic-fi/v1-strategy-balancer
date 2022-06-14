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

import '@mimic-fi/v1-vault/contracts/interfaces/IVault.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import '../balancer/IBalancerVault.sol';
import '../balancer/gauges/IBalancerMinter.sol';
import '../balancer/gauges/IGaugeFactory.sol';
import '../BalancerStrategy.sol';

/**
 * @title BalancerStrategyFactory
 * @dev Factory contract to create BalancerStrategy contracts
 */
abstract contract BalancerStrategyFactory {
    /**
     * @dev Emitted every time a new BalancerStrategy is created
     */
    event StrategyCreated(BalancerStrategy indexed strategy);

    IVault public immutable vault;
    IBalancerVault public immutable balancerVault;
    IBalancerMinter public immutable balancerMinter;
    IGaugeFactory public immutable gaugeFactory;
    IGauge.Type public immutable gaugeType;

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
    ) {
        vault = _vault;
        balancerVault = _balancerVault;
        balancerMinter = _balancerMinter;
        gaugeFactory = _gaugeFactory;
        gaugeType = _gaugeType;
    }

    /**
     * @dev Creates a new BalancerStrategy
     * @param token Token to be used as the strategy entry point
     * @param poolId Id of the Balancer pool to create the strategy for
     * @param slippage Slippage value to be used in order to swap rewards
     * @param metadata Metadata URI associated to the strategy
     */
    function create(IERC20 token, bytes32 poolId, uint256 slippage, string memory metadata)
        external
        returns (BalancerStrategy strategy)
    {
        (address pool, ) = balancerVault.getPool(poolId);
        IGauge gauge = gaugeFactory.getPoolGauge(IERC20(pool));
        require(address(gauge) != address(0), 'MISSING_POOL_GAUGE');

        strategy = _create(token, poolId, gauge, slippage, metadata);
        strategy.transferOwnership(msg.sender);
        emit StrategyCreated(strategy);
    }

    /**
     * @dev Internal method that must be overridden to create a new BalancerStrategy depending on the pool type:
     *      weighted, stable, or boosted
     * @param token Token to be used as the strategy entry point
     * @param poolId Id of the Balancer pool to create the strategy for
     * @param gauge Address of the gauge associated to the pool to be used
     * @param slippage Slippage value to be used in order to swap rewards
     * @param metadata Metadata URI associated to the strategy
     */
    function _create(IERC20 token, bytes32 poolId, IGauge gauge, uint256 slippage, string memory metadata)
        internal
        virtual
        returns (BalancerStrategy);
}
