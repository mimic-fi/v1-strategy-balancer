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
import '../balancer/gauges/IGaugeAdder.sol';
import '../BalancerStrategy.sol';

abstract contract BalancerStrategyFactory {
    event StrategyCreated(BalancerStrategy indexed strategy);

    IVault public immutable vault;
    IBalancerVault public immutable balancerVault;
    IGaugeAdder public immutable gaugeAdder;
    IBalancerMinter public immutable balancerMinter;
    IGaugeController public immutable gaugeController;

    constructor(IVault _vault, IBalancerVault _balancerVault, IBalancerMinter _balancerMinter, IGaugeAdder _gaugeAdder)
    {
        require(_gaugeAdder.getVault() == address(_balancerVault), 'ERR_WRONG_GAUGE_ADDER');
        require(_gaugeAdder.getGaugeController() == _balancerMinter.getGaugeController(), 'ERR_WRONG_BALANCER_MINTER');

        vault = _vault;
        balancerVault = _balancerVault;
        balancerMinter = _balancerMinter;
        gaugeAdder = _gaugeAdder;
        gaugeController = _gaugeAdder.getGaugeController();
    }

    function create(IERC20 token, bytes32[] memory poolIds, uint256 slippage, string memory metadata)
        external
        returns (BalancerStrategy strategy)
    {
        require(poolIds.length > 0, 'NO_POOL_ID');

        (address pool, ) = balancerVault.getPool(poolIds[0]);
        ILiquidityGauge gauge = gaugeAdder.getPoolGauge(IERC20(pool));
        require(gaugeController.gauge_exists(address(gauge)), 'ERR_MISSING_POOL_GAUGE');

        strategy = _create(token, gauge, poolIds, slippage, metadata);
        strategy.transferOwnership(msg.sender);
        emit StrategyCreated(strategy);
    }

    function _create(
        IERC20 token,
        ILiquidityGauge gauge,
        bytes32[] memory poolIds,
        uint256 slippage,
        string memory metadata
    ) internal virtual returns (BalancerStrategy);
}
