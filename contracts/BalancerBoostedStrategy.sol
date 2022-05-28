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

import '@openzeppelin/contracts/utils/math/SafeCast.sol';

import './balancer/IBalancerVault.sol';

import './BalancerStableStrategy.sol';

contract BalancerBoostedStrategy is BalancerStableStrategy {
    using FixedPoint for uint256;

    uint256 private constant TOKEN_INDEX = 0;
    uint256 private constant LINEAR_BPT_INDEX = 1;
    uint256 private constant STABLE_BPT_INDEX = 2;

    bytes32 internal immutable _linearPoolId;
    address internal immutable _linearPoolAddress;

    constructor(
        IVault vault,
        IERC20 token,
        IBalancerVault balancerVault,
        bytes32 poolId,
        bytes32 linearPoolId,
        uint256 slippage,
        string memory metadata
    ) BalancerStableStrategy(vault, token, balancerVault, poolId, slippage, metadata) {
        _linearPoolId = linearPoolId;
        (_linearPoolAddress, ) = balancerVault.getPool(linearPoolId);
    }

    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _joinBalancer(uint256 amount) internal override {
        int256[] memory limits = new int256[](3);
        limits[TOKEN_INDEX] = SafeCast.toInt256(amount);
        limits[STABLE_BPT_INDEX] =
            0 -
            SafeCast.toInt256(_getMinAmountOut(_token, IERC20(_poolAddress), amount, getSlippage()));

        address[] memory assets = _buildAssetsParam();

        IBalancerVault.FundManagement memory funds = _buildFundsParam();

        IBalancerVault.BatchSwapStep[] memory swaps = _buildBatchSwapStepsParam(
            amount,
            _linearPoolId,
            _poolId,
            TOKEN_INDEX,
            LINEAR_BPT_INDEX,
            STABLE_BPT_INDEX
        );

        _token.approve(address(_balancerVault), amount);

        _balancerVault.batchSwap(IBalancerVault.SwapKind.GIVEN_IN, swaps, assets, funds, limits, block.timestamp);
    }

    function _exitBalancer(uint256 ratio, uint256 slippage)
        internal
        override
        returns (uint256 tokenBalance, uint256 bptAmount, uint256 bptBalance)
    {
        bptAmount = SafeMath.div(_getBptBalance().mulDown(ratio), VAULT_EXIT_RATIO_PRECISION);
        uint256 minAmount = _getMinAmountOut(IERC20(_poolAddress), _token, bptAmount, slippage);

        int256[] memory limits = new int256[](3);
        limits[TOKEN_INDEX] = 0 - SafeCast.toInt256(minAmount);
        limits[STABLE_BPT_INDEX] = SafeCast.toInt256(bptAmount);

        address[] memory assets = _buildAssetsParam();

        IBalancerVault.FundManagement memory funds = _buildFundsParam();

        IBalancerVault.BatchSwapStep[] memory swaps = _buildBatchSwapStepsParam(
            bptAmount,
            _poolId,
            _linearPoolId,
            STABLE_BPT_INDEX,
            LINEAR_BPT_INDEX,
            TOKEN_INDEX
        );

        _balancerVault.batchSwap(IBalancerVault.SwapKind.GIVEN_IN, swaps, assets, funds, limits, block.timestamp);

        tokenBalance = _token.balanceOf(address(this));
        bptBalance = _getBptBalance();
    }

    function _buildFundsParam() internal view returns (IBalancerVault.FundManagement memory funds) {
        funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(this),
            toInternalBalance: false
        });
    }

    function _buildAssetsParam() internal view returns (address[] memory assets) {
        assets = new address[](3);
        assets[0] = address(_token);
        assets[1] = _linearPoolAddress;
        assets[2] = _poolAddress;
    }

    function _buildBatchSwapStepsParam(
        uint256 amount,
        bytes32 pool1,
        bytes32 pool2,
        uint256 assetInIndex,
        uint256 assetConnectIndex,
        uint256 assetOutIndex
    ) internal pure returns (IBalancerVault.BatchSwapStep[] memory swaps) {
        swaps = new IBalancerVault.BatchSwapStep[](2);

        swaps[0] = IBalancerVault.BatchSwapStep({
            poolId: pool1,
            assetInIndex: assetInIndex,
            assetOutIndex: assetConnectIndex,
            amount: amount,
            userData: new bytes(0)
        });
        swaps[1] = IBalancerVault.BatchSwapStep({
            poolId: pool2,
            assetInIndex: assetConnectIndex,
            assetOutIndex: assetOutIndex,
            amount: 0,
            userData: new bytes(0)
        });

        return swaps;
    }

    function _getTokenIndex(IERC20) internal pure override returns (uint256) {
        //Does not matter
        return 0;
    }
}
