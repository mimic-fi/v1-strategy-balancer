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

import './balancer/IStablePool.sol';

import './BalancerStrategy.sol';

contract BalancerStableStrategy is BalancerStrategy {
    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        uint256 tokenIndex,
        IERC20 balToken,
        uint256 slippage,
        string memory metadata
    ) BalancerStrategy(vault, token, balancerVault, poolId, tokenIndex, balToken, slippage, metadata) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getBptPerTokenPrice() public view override returns (uint256) {
        IStablePool stablePool = IStablePool(_poolAddress);
        uint256 rate = stablePool.getRate();
        return rate / _tokenScale;
    }
}
