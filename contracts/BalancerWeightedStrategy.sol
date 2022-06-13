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
import './balancer/pools/LogExpMath.sol';
import './balancer/pools/IWeightedPool.sol';

/**
 * @title BalancerWeightedStrategy
 * @dev This strategy provides liquidity in Balancer weighted pools through joins.
 */
contract BalancerWeightedStrategy is BalancerSingleStrategy {
    using FixedPoint for uint256;

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
     * @dev Tells the exchange rate for a BPT expressed in the strategy token.
     *      It computes the BPT price in the strategy token by calculating the total balance in the strategy token
     *      of the strategy itself, querying the prices in an external price oracle, and then dividing it by the
     *      total supply. Note that doing it this way, the BPT price cannot be manipulated.
     */
    function getTokenPerBptPrice() public view override returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(_vault.priceOracle());
        IWeightedPool weightedPool = IWeightedPool(address(_pool));
        uint256[] memory weights = weightedPool.getNormalizedWeights();
        (IERC20[] memory tokens, , ) = _balancerVault.getPoolTokens(_poolId);

        uint256 mul = FixedPoint.ONE;
        for (uint256 i; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            uint256 weight = weights[i];
            uint256 price = token == _token
                ? FixedPoint.ONE
                : ((priceOracle.getTokenPrice(address(_token), address(token)) * _tokenScale) / _getTokenScale(token));

            mul = mul.mulDown(LogExpMath.pow(price.divDown(weight), weight));
        }

        uint256 invariant = weightedPool.getInvariant();
        uint256 totalSupply = _pool.totalSupply();
        return SafeMath.div(SafeMath.mul(invariant, mul), totalSupply) / _tokenScale;
    }
}
