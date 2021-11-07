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

import './BalancerWeightedStrategy.sol';

contract BalancerWeightedStrategyFactory {
    event StrategyCreated(BalancerWeightedStrategy strategy);

    IVault public vault;
    IBalancerVault public balancerVault;
    IERC20 public balToken;

    constructor(IVault _vault, IBalancerVault _balancerVault, IERC20 _balToken) {
        vault = _vault;
        balancerVault = _balancerVault;
        balToken = _balToken;
    }

    function create(IERC20 token, bytes32 poolId, uint256 slippage, string memory metadata)
        external
        returns (BalancerWeightedStrategy strategy)
    {
        strategy = new BalancerWeightedStrategy(vault, token, balancerVault, poolId, balToken, slippage, metadata);
        emit StrategyCreated(strategy);
    }
}
