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

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import './balancer/LogExpMath.sol';
import './balancer/IWeightedPool.sol';

import './BalancerStrategy.sol';

contract BalancerWeightedStrategy is BalancerStrategy, LogExpMath {
    using FixedPoint for uint256;

    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        uint256 slippage,
        string memory metadata
    ) BalancerStrategy(vault, token, balancerVault, poolId, slippage, metadata) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getTokenPerBptPrice() public view override returns (uint256) {
        (IERC20[] memory tokens, , ) = _balancerVault.getPoolTokens(_poolId);

        IWeightedPool weightedPool = IWeightedPool(_poolAddress);

        uint256[] memory weights = weightedPool.getNormalizedWeights();
        uint256 invariant = weightedPool.getInvariant();
        uint256 totalSupply = IERC20(_poolAddress).totalSupply();

        address priceOracle = _vault.priceOracle();

        uint256 mul = FixedPoint.ONE;

        for (uint256 i; i < tokens.length; i++) {
            uint256 price = tokens[i] == _token
                ? FixedPoint.ONE
                : ((IPriceOracle(priceOracle).getTokenPrice(address(_token), address(tokens[i])) * _tokenScale) /
                    _getTokenScale(tokens[i]));

            mul = mul.mul(pow(price.div(weights[i]), weights[i]));
        }

        return SafeMath.div(SafeMath.mul(invariant, mul), totalSupply) / _tokenScale;
    }
}
