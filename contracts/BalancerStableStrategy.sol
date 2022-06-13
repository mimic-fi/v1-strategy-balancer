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

import './BalancerSingleStrategy.sol';

/**
 * @title BalancerStableStrategy
 * @dev This strategy provides liquidity in Balancer stable pools through joins.
 */
contract BalancerStableStrategy is BalancerSingleStrategy {
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
    )
        BalancerSingleStrategy(
            vault,
            balancerVault,
            balancerMinter,
            token,
            poolId,
            gauge,
            gaugeType,
            slippage,
            metadataURI
        )
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Tells the exchange rate for a BPT expressed in the strategy token. Since here we are working with stable
     *      pools, it can be simply computed using the pool rate.
     */
    function getTokenPerBptPrice() public view override returns (uint256) {
        uint256 rate = IBalancerPool(address(_pool)).getRate();
        return rate / _tokenScale;
    }
}
