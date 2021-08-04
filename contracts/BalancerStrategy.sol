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

import "@mimic-fi/v1-core/contracts/interfaces/IStrategy.sol";
import "@mimic-fi/v1-core/contracts/interfaces/ISwapConnector.sol";
import "@mimic-fi/v1-core/contracts/interfaces/IVault.sol";
import "@mimic-fi/v1-core/contracts/helpers/FixedPoint.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IBalancerVault.sol";

import "hardhat/console.sol";


contract BalancerStrategy is IStrategy {
    using FixedPoint for uint256;

    uint256 private constant JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT = 1;
    uint256 private constant EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT = 0;

    IVault public immutable vault;
    IERC20 public immutable token;
    IBalancerVault public immutable balancerVault;
    bytes32 public immutable poolId;
    address public immutable poolAddress;
    uint256 public immutable tokenIndex;
    IERC20 public immutable balToken;

    uint256 private _totalShares;
    string private _metadataURI;

    modifier onlyVault() {
        require(address(vault) == msg.sender, "CALLER_IS_NOT_VAULT");
        _;
    }

    constructor(IVault _vault, IERC20 _token, IBalancerVault _balancerVault, bytes32 _poolId, uint256 _tokenIndex, IERC20 _balToken, string memory _metadata) {
        token = _token;
        balancerVault = _balancerVault;
        vault = _vault; 

        poolId = _poolId;
        tokenIndex = _tokenIndex;
        _metadataURI = _metadata;
        balToken = _balToken;

        (poolAddress,) = _balancerVault.getPool(_poolId);

        _token.approve(address(_vault), FixedPoint.MAX_UINT256);
        _token.approve(address(_balancerVault), FixedPoint.MAX_UINT256);
    }

    function getToken() external view override returns (address) {
        return address(token);
    }

    function getMetadataURI() external view override returns (string memory) {
        return _metadataURI;
    }

    function getTokenBalance() external view override returns (uint256) {
        //TODO: USE ORACLE!!! needs to to be manipulable
        (,uint256[] memory balances,) = balancerVault.getPoolTokens(poolId);
        uint256 totalSupply = IERC20(poolAddress).totalSupply();

        //TODO: hardcoded weight because of we will use oracle
        uint256 daiPerBPT = balances[0].div(400000000000000000).div(totalSupply);
        uint256 bPTAmount = IERC20(poolAddress).balanceOf(address(this));

        return bPTAmount.mul(daiPerBPT);
    }

    function getTotalShares() external view override returns (uint256) {
        return _totalShares;
    }

    function onJoin(uint256 amount, bytes memory) external override onlyVault returns (uint256) {
        uint256 initialTokenBalance = token.balanceOf(address(this));
        uint256 initialBPTAmount = IERC20(poolAddress).balanceOf(address(this));

        claimAndInvest();

        uint256 finalBPTAmount = IERC20(poolAddress).balanceOf(address(this));
        uint256 callerBPTAmount = amount.mul(finalBPTAmount.sub(initialBPTAmount)).div(initialTokenBalance);

        uint256 rate = _totalShares == 0? FixedPoint.ONE: _totalShares.div(finalBPTAmount);
        uint256 shares = callerBPTAmount.mul(rate);
        _totalShares = _totalShares.add(shares);
        return shares;
    }

    function onExit(uint256 shares, bytes memory) external override onlyVault returns (address, uint256) {
        claimAndInvest();

        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);

        uint256 initialTokenAmount = token.balanceOf(address(this));
        uint256 initialBPTAmount = IERC20(poolAddress).balanceOf(address(this));
        
        uint256 bptAmount = SafeMath.div(SafeMath.mul(shares, initialBPTAmount), _totalShares);

        //TODO: use oracle?
        uint256[] memory minAmountsOut = new uint256[](tokens.length);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: tokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encodePacked(EXIT_WEIGHTED_POOL_EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmount, tokenIndex),
            toInternalBalance: false
        });

        balancerVault.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            request
        );

        uint256 finalTokenAmount = token.balanceOf(address(this));
        uint256 amount = finalTokenAmount.sub(initialTokenAmount);
        _totalShares = _totalShares.sub(shares);
        return (address(token), amount);
    }

    function approveVault(IERC20 _token) external {
        //BPT and BAL protected
        require(address(_token) != address(poolAddress), "BALANCER_INTERNAL_TOKEN");
        require(address(_token) != address(balToken), "BALANCER_INTERNAL_TOKEN");

        _token.approve(address(vault), FixedPoint.MAX_UINT256);
    }

    function investAllDAI() public {
        uint256 tokenBalance = token.balanceOf(address(this));
        if(tokenBalance > 0) {
            _investDAI(tokenBalance);
        }
    }

    function tradeForDAI(IERC20 _tokenIn) public {
        require(address(_tokenIn) != address(poolAddress), "BALANCER_INTERNAL_TOKEN");
        require(address(_tokenIn) != address(token), "BALANCER_INTERNAL_TOKEN");
        //TODO any other?

        uint256 tokenInBalance = _tokenIn.balanceOf(address(this));

        if(tokenInBalance > 0) {
            uint256 deadline = block.timestamp + 5 minutes; //TODO, also optional

            address swapConnector = vault.swapConnector();
            
            _tokenIn.transfer(swapConnector, tokenInBalance);

            ISwapConnector(swapConnector).swap(
                address(_tokenIn),
                address(token),
                tokenInBalance,
                0, //TODO: should be check by connector using oracle
                deadline,
                ""
            );
        }
    }

    function tradeAndInvest(IERC20 _token) public {
        tradeForDAI(_token);
        investAllDAI();
    }

    function claimAndInvest() public {
        //TODO: claim BAL
        tradeAndInvest(balToken);
    }


    //Internal

    function _investDAI(uint256 amount) internal {
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);

        uint256[] memory amountsIn = new uint256[](tokens.length);
        amountsIn[tokenIndex] = amount;

        //TODO: use oracle for BPT price?
        uint256 minimumBPT = 0;

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(JOIN_WEIGHTED_POOL_EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT),
            fromInternalBalance: false
        });

        balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            request
        );
    }
}
