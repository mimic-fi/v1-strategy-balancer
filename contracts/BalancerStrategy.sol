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

import '@mimic-fi/v1-vault/contracts/interfaces/IStrategy.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/ISwapConnector.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/IPriceOracle.sol';
import '@mimic-fi/v1-vault/contracts/interfaces/IVault.sol';
import '@mimic-fi/v1-vault/contracts/libraries/FixedPoint.sol';
import '@mimic-fi/v1-portfolios/contracts/helpers/PortfoliosData.sol';

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import './balancer/IBalancerVault.sol';
import './balancer/pools/IBalancerPool.sol';
import './balancer/gauges/IBalancerMinter.sol';
import './balancer/gauges/ILiquidityGauge.sol';
import './balancer/gauges/IRewardOnlyGauge.sol';

/**
 * @title BalancerStrategy
 * @dev This strategy provides liquidity in Balancer pools, obtaining rewards distributed through the Balancer gauges.
 */
abstract contract BalancerStrategy is IStrategy, Ownable {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using PortfoliosData for bytes;

    // Max value in order to cap the slippage config: 10%
    uint256 private constant MAX_SLIPPAGE = 10e16;

    // Min value in order to limit the amount of token rewards to be swapped in the strategy: 10 wei
    uint256 private constant SWAP_THRESHOLD = 10;

    // Precision value used by Mimic's Vault to avoid rounding errors
    uint256 internal constant VAULT_EXIT_RATIO_PRECISION = 1e18;

    /**
     * @dev Emitted every time a new slippage value is set
     */
    event SetSlippage(uint256 slippage);

    // Mimic Vault reference
    IVault internal immutable _vault;

    // Strategy metadata URI
    string private _metadataURI;

    // Slippage to be used to swap and re-invest rewards
    uint256 internal _slippage;

    // Balancer V2 Vault reference
    IBalancerVault internal immutable _balancerVault;

    // Balancer token
    IERC20 internal immutable _balancerToken;

    // Balancer Minter reference
    IBalancerMinter internal immutable _balancerMinter;

    // Gauge associated to the Balancer pool
    IGauge internal immutable _gauge;

    // Gauge type of the pool
    IGauge.Type internal immutable _gaugeType;

    // Balancer V2's internal identifier for the Balancer pool
    bytes32 internal immutable _poolId;

    // Address of the Balancer pool contract
    IERC20 internal immutable _pool;

    // List of tokens composing the Balancer pool
    IERC20[] internal _tokens;

    // Pool token that will be used as the strategy entry point
    IERC20 internal immutable _token;

    // Scaling factor of the entry point token
    uint256 internal immutable _tokenScale;

    /**
     * @dev Used to mark functions that can only be called by the protocol vault
     */
    modifier onlyVault() {
        require(address(_vault) == msg.sender, 'CALLER_IS_NOT_VAULT');
        _;
    }

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
    ) {
        (address poolAddress, ) = balancerVault.getPool(poolId);
        require(poolAddress != address(0), 'MISSING_BALANCER_POOL');
        _pool = IERC20(poolAddress);

        _vault = vault;
        _balancerVault = balancerVault;
        _balancerMinter = balancerMinter;
        _balancerToken = address(balancerMinter) == address(0) ? IERC20(address(0)) : balancerMinter.getBalancerToken();
        _token = token;
        _poolId = poolId;
        _gauge = gauge;
        _gaugeType = gaugeType;
        _setSlippage(slippage);
        _setMetadataURI(metadataURI);
        _setTokens(balancerVault, poolId);
        _tokenScale = _getTokenScale(token);
    }

    /**
     * @dev Tells the address of the Mimic Vault
     */
    function getVault() external view returns (address) {
        return address(_vault);
    }

    /**
     * @dev Tell the metadata URI associated to the strategy
     */
    function getMetadataURI() external view override returns (string memory) {
        return _metadataURI;
    }

    /**
     * @dev Tell the slippage used to swap rewards
     */
    function getSlippage() external view returns (uint256) {
        return _slippage;
    }

    /**
     * @dev Tells the address of the Balancer Vault
     */
    function getBalancerVault() external view returns (address) {
        return address(_balancerVault);
    }

    /**
     * @dev Tells the address of the liquidity gauge associated to the Balancer pool
     */
    function getGauge() external view returns (address) {
        return address(_gauge);
    }

    /**
     * @dev Tells the Balancer identifier of the Balancer pool associated to the strategy
     */
    function getPoolId() external view returns (bytes32) {
        return _poolId;
    }

    /**
     * @dev Tells the address of the Balancer pool associated to the strategy
     */
    function getPool() external view returns (address) {
        return address(_pool);
    }

    /**
     * @dev Tells the token that will be used as the strategy entry point
     */
    function getToken() external view override returns (address) {
        return address(_token);
    }

    /**
     * @dev Tells the scaling factor of the entry point token
     */
    function getTokenScale() external view returns (uint256) {
        return _tokenScale;
    }

    /**
     * @dev Tells how much value the strategy has over time.
     * For example, if a strategy has a value of 100 in T0, and then it has a value of 120 in T1,
     * It means it gained a 20% between T0 and T1 due to swap fees and liquidity mining (re-investments).
     * Note: This function only tells the total value until the last rewards claim
     */
    function getTotalValue() public view override returns (uint256) {
        uint256 bptRate = IBalancerPool(address(_pool)).getRate();
        uint256 bptBalance = _pool.balanceOf(address(this));
        uint256 stakedBalance = _gauge.balanceOf(address(this));
        return bptBalance.add(stakedBalance).mulDown(bptRate);
    }

    /**
     * @dev Tells how much a value unit means expressed in the strategy token.
     * For example, if a strategy has a value of 100 in T0, and then it has a value of 120 in T1,
     * and the value rate is 1.5, it means the strategy has earned 30 strategy tokens between T0 and T1.
     */
    function getValueRate() external view override returns (uint256) {
        uint256 bptRate = IBalancerPool(address(_pool)).getRate();
        return getTokenPerBptPrice().divUp(bptRate);
    }

    /**
     * @dev Tells the exchange rate for a BPT expressed in the strategy token
     */
    function getTokenPerBptPrice() public view virtual returns (uint256);

    /**
     * @dev Setter to override the existing metadata URI
     * @param metadataURI New metadata to be set
     */
    function setMetadataURI(string memory metadataURI) external onlyOwner {
        _setMetadataURI(metadataURI);
    }

    /**
     * @dev Setter to update the slippage
     * @param slippage New slippage to be set
     */
    function setSlippage(uint256 slippage) external onlyOwner {
        _setSlippage(slippage);
    }

    /**
     * @dev Strategy onJoin hook
     * @param amount Amount of strategy tokens to invest
     * @param data Extra data to be used as the encoded slippage to join the Balancer pool
     */
    function onJoin(uint256 amount, bytes memory data)
        external
        override
        onlyVault
        returns (uint256 value, uint256 totalValue)
    {
        claim();

        // Pick the minimum slippage since the user is also investing the accrued rewards
        uint256 slippage = Math.min(data.decodeSlippage(), _slippage);
        uint256 initialTokenBalance = _token.balanceOf(address(this));
        uint256 investedBptAmount = invest(_token, slippage);

        // Handle any potential airdrop that does not correspond to the joining user
        uint256 callerBptAmount = SafeMath.div(SafeMath.mul(amount, investedBptAmount), initialTokenBalance);

        uint256 bptRate = IBalancerPool(address(_pool)).getRate();
        value = callerBptAmount.mulDown(bptRate);

        uint256 totalStakedBpt = _gauge.balanceOf(address(this));
        totalValue = totalStakedBpt.mulDown(bptRate);
    }

    /**
     * @dev Strategy onExit hook
     * @param ratio Ratio of the invested position to exit
     * @param emergency Tells if the exit call is an emergency or not, if it is then no investments are made, simply exit
     * @param data Extra data to be used as the encoded slippage to exit the Balancer pool
     */
    function onExit(uint256 ratio, bool emergency, bytes memory data)
        external
        override
        onlyVault
        returns (address token, uint256 amount, uint256 value, uint256 totalValue)
    {
        // Claims before exiting only if it is a non-emergency exit
        if (!emergency) {
            claim();
            invest(_token, _slippage);
        }

        (uint256 tokenAmount, uint256 bptAmount, uint256 bptBalance) = _exitBalancer(ratio, data.decodeSlippage());
        _token.approve(address(_vault), tokenAmount);

        uint256 bptRate = IBalancerPool(address(_pool)).getRate();
        value = bptAmount.mulDown(bptRate);
        totalValue = bptBalance.mulDown(bptRate);
        return (address(_token), tokenAmount, value, totalValue);
    }

    /**
     * @dev Claims Balancer rewards. All the given rewards that are not the strategy token are swapped for it.
     * After swapping all the rewards for the strategy token, it joins the Balancer pool with the final amount.
     */
    function claim() public {
        // Claim BAL rewards through Balancer Minter if it was set
        if (_balancerMinter != IBalancerMinter(address(0))) {
            uint256 balAmount = _balancerMinter.mint(address(_gauge));
            _swap(_balancerToken, _token, balAmount);
        }

        // Fetch rewards count based on gauge type
        uint256 rewards;
        if (_gaugeType == IGauge.Type.Liquidity) {
            rewards = ILiquidityGauge(address(_gauge)).reward_count();
        } else {
            IRewardOnlyContract rewardContract = IRewardOnlyGauge(address(_gauge)).reward_contract();
            rewards = rewardContract.reward_count();
            rewardContract.get_reward();
        }

        // Claim other token rewards
        _gauge.claim_rewards();
        for (uint256 i = 0; i < rewards; i++) {
            IERC20 rewardsToken = _gauge.reward_tokens(i);
            if (rewardsToken != _token && rewardsToken != _pool) {
                uint256 balance = rewardsToken.balanceOf(address(this));
                _swap(rewardsToken, _token, balance);
            }
        }
    }

    /**
     * @dev Invest all the balance of a token in the strategy into the associated Balancer pool.
     * If the requested token is not the same token as the strategy token it will be swapped before joining the pool.
     * This method is marked as public so it can be used externally by anyone in case of an airdrop.
     * @param token Token to invest all its balance, it cannot be the BPT associated to the strategy
     * @param suggestedSlippage Slippage to be used in order to swap the given token, the minimum between this value
     *        and the one configured for the strategy will be used
     */
    function invest(IERC20 token, uint256 suggestedSlippage) public returns (uint256 bptBalance) {
        require(token != _pool, 'BALANCER_INTERNAL_TOKEN');

        if (token != _token) {
            uint256 amountIn = token.balanceOf(address(this));
            _swap(token, _token, amountIn);
        }

        uint256 slippage = Math.min(suggestedSlippage, _slippage);
        return _joinBalancer(_token.balanceOf(address(this)), slippage);
    }

    /**
     * @dev Claims and invest rewards.
     * @return Current total value after investing all accrued rewards.
     */
    function claimAndInvest() external returns (uint256) {
        claim();
        invest(_token, _slippage);
        return getTotalValue();
    }

    /**
     * @dev Internal function to join the Balancer pool
     * @param amount Amount of strategy tokens to invest
     * @param slippage Slippage to be used to join the Balancer pool
     */
    function _joinBalancer(uint256 amount, uint256 slippage) internal virtual returns (uint256 bptBalance);

    /**
     * @dev Internal function to exit the Balancer pool
     * @param ratio Ratio of the invested position to exit
     * @param slippage Slippage to be used to exit the Balancer pool
     */
    function _exitBalancer(uint256 ratio, uint256 slippage)
        internal
        virtual
        returns (uint256 tokenBalance, uint256 bptAmount, uint256 bptBalance);

    /**
     * @dev Internal function to swap a pair of tokens using the Vault's swap connector
     * @param tokenIn Token to be sent
     * @param tokenOut Token to received
     * @param amountIn Amount of tokenIn being swapped
     */
    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) return;
        require(tokenIn != tokenOut, 'SWAP_SAME_TOKEN');

        uint256 minAmountOut = _getMinAmountOut(tokenIn, tokenOut, amountIn, _slippage);
        if (minAmountOut < SWAP_THRESHOLD) return;

        address swapConnector = _vault.swapConnector();
        tokenIn.safeTransfer(swapConnector, amountIn);

        uint256 preBalanceIn = tokenIn.balanceOf(address(this));
        uint256 preBalanceOut = tokenOut.balanceOf(address(this));
        (uint256 remainingIn, uint256 amountOut) = ISwapConnector(swapConnector).swap(
            address(tokenIn),
            address(tokenOut),
            amountIn,
            minAmountOut,
            block.timestamp,
            new bytes(0)
        );

        require(amountOut >= minAmountOut, 'SWAP_MIN_AMOUNT');
        uint256 postBalanceIn = tokenIn.balanceOf(address(this));
        require(postBalanceIn >= preBalanceIn.add(remainingIn), 'SWAP_INVALID_REMAINING_IN');
        uint256 postBalanceOut = tokenOut.balanceOf(address(this));
        require(postBalanceOut >= preBalanceOut.add(amountOut), 'SWAP_INVALID_AMOUNT_OUT');
    }

    /**
     * @dev Tells the expected min amount for a swap using the price oracle or the pool itself for joins and exits
     * @param tokenIn Token to be sent
     * @param tokenOut Token to received
     * @param amountIn Amount of tokenIn being swapped
     * @param slippage Slippage to be used to compute the min amount out
     */
    function _getMinAmountOut(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 slippage)
        internal
        view
        returns (uint256 minAmountOut)
    {
        uint256 price;
        if (tokenIn == _token && tokenOut == _pool) {
            price = FixedPoint.ONE.divUp(getTokenPerBptPrice());
        } else if (tokenIn == _pool && tokenOut == _token) {
            price = getTokenPerBptPrice();
        } else {
            price = IPriceOracle(_vault.priceOracle()).getTokenPrice(address(tokenOut), address(tokenIn));
        }

        minAmountOut = amountIn.mulUp(price).mulUp(FixedPoint.ONE - slippage);
    }

    /**
     * @dev Tells the scaling factor to be used for the strategy token.
     * This strategy does not support working with tokens that use more than 18 decimals.
     * @param token Address of the token to be queried
     */
    function _getTokenScale(IERC20 token) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(address(token)).decimals();
        require(decimals <= 18, 'TOKEN_WORKS_WITH_BIGGER_DECIMALS');
        uint256 diff = 18 - decimals;
        return 10**diff;
    }

    /**
     * @dev Internal function to set the metadata URI
     * @param metadataURI New metadata to be set
     */
    function _setMetadataURI(string memory metadataURI) private {
        _metadataURI = metadataURI;
        emit SetMetadataURI(metadataURI);
    }

    /**
     * @dev Internal function to set the slippage
     * @param slippage New slippage to be set
     */
    function _setSlippage(uint256 slippage) private {
        require(slippage <= MAX_SLIPPAGE, 'SLIPPAGE_ABOVE_MAX');
        _slippage = slippage;
        emit SetSlippage(slippage);
    }

    /**
     * @dev Internal function to cache the Balancer pool tokens. Used only by the constructor.
     * @param vault Balancer V2 Vault reference
     * @param poolId Balancer V2's internal identifier for the Balancer pool
     */
    function _setTokens(IBalancerVault vault, bytes32 poolId) private {
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _tokens = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) _tokens[i] = tokens[i];
    }
}
