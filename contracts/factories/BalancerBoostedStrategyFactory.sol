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
import '../BalancerBoostedStrategy.sol';

contract BalancerBoostedStrategyFactory is BalancerStrategyFactory {
    constructor(IVault _vault, IBalancerVault _balancerVault, IBalancerMinter _balancerMinter, IGaugeAdder _gaugeAdder)
        BalancerStrategyFactory(_vault, _balancerVault, _balancerMinter, _gaugeAdder)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _create(
        IERC20 token,
        ILiquidityGauge gauge,
        bytes32[] memory poolIds,
        uint256 slippage,
        string memory data
    ) internal override returns (BalancerStrategy) {
        require(poolIds.length == 2, 'INVALID_POOL_IDS_LENGTH');

        return
            new BalancerBoostedStrategy(
                vault,
                token,
                balancerVault,
                balancerMinter,
                gauge,
                poolIds[0],
                poolIds[1],
                slippage,
                data
            );
    }
}
