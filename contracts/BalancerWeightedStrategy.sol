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

import "./BalancerStrategy.sol";
import "./LogExpMath.sol";
import "./IWeightedPool.sol";

contract BalancerWeightedStrategy is BalancerStrategy, LogExpMath {
    using FixedPoint for uint256;

    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        uint256 tokenIndex,
        IERC20 balToken,
        uint256 slippage,
        string memory metadata
    )
        BalancerStrategy(
            vault,
            token,
            balancerVault,
            poolId,
            tokenIndex,
            balToken,
            slippage,
            metadata
        )
    {}

    function _getTokenPerBPTPrice() internal view override returns (uint256) {
        (IERC20[] memory tokens, uint256[] memory balances, ) = _balancerVault
        .getPoolTokens(_poolId);

        IWeightedPool weightedPool = IWeightedPool(_poolAddress);

        uint256[] memory weigths = weightedPool.getNormalizedWeights();

        uint256 invariant = _calculateInvariant(weigths, balances);
        uint256 totalSupply = IERC20(_poolAddress).totalSupply();

        address priceOracle = _vault.priceOracle();

        uint256 sumPrices;
        uint256 divider = FixedPoint.ONE;
        for (uint256 i; i < tokens.length; i++) {
            uint256 price;
            if (tokens[i] == _token) {
                price = FixedPoint.ONE;
            } else {
                price = IPriceOracle(priceOracle).getTokenPrice(
                    address(_token),
                    address(tokens[i])
                );
            }

            sumPrices = sumPrices.add(pow(price, weigths[i]));
            divider = divider.mul(pow(weigths[i], weigths[i]));
        }

        return invariant.mul(sumPrices).divUp(totalSupply).divUp(divider);
    }

    //TODO: or use upscaled getIInvariant?
    function _calculateInvariant(
        uint256[] memory normalizedWeights,
        uint256[] memory balances
    ) private pure returns (uint256 invariant) {
        invariant = FixedPoint.ONE;
        for (uint256 i = 0; i < normalizedWeights.length; i++) {
            invariant = invariant.mul(pow(balances[i], normalizedWeights[i]));
        }
    }
}
