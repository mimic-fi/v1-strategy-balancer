import {
  advanceTime,
  assertEvent,
  bn,
  deploy,
  fp,
  getSigners,
  impersonate,
  instanceAt,
  MAX_UINT256,
  MONTH,
} from '@mimic-fi/v1-helpers'
import { encodeSlippage } from '@mimic-fi/v1-portfolios/dist/helpers/encoding'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

/* eslint-disable no-secrets/no-secrets */

const BAL = '0xba100000625a3754423978a60c9317c58a424e3d'
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const WHALE_WITH_USDC = '0x55fe002aeff02f77364de339a1292923a15844b8'

const GAUGE_ADDER = '0xed5ba579bb5d516263ff6e1c10fcac1040075fe2'
const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
const BALANCER_MINTER = '0x239e55F427D44C3cc793f49bFB507ebe76638a2b'

const POOL_BAL_WETH_ID = '0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014'
const POOL_DAI_WETH_ID = '0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a'
const POOL_DAI_USDC_ID = '0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063'
const POOL_DAI_USDC_USDT_ID = '0x7b50775383d3d6f0215a8f290f2c9e2eebbeceb20000000000000000000000fe'
const LINEAR_POOL_USDC_ID = '0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc'

const UNISWAP_V2_ROUTER = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
const UNISWAP_V3_ROUTER = '0xE592427A0AEce92De3Edee1F18E0157C05861564'
const BALANCER_V2_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'

const CHAINLINK_ORACLE_BAL_ETH = '0xc1438aa3823a6ba0c159cfa8d98df5a994ba120b'
const CHAINLINK_ORACLE_USDC_ETH = '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4'

const USDC_SCALING_FACTOR = 1e12

describe('BalancerBoostedStrategy - bb-a-USDT bb-a-DAI bb-a-USDC', function () {
  let vault: Contract, strategy: Contract
  let owner: SignerWithAddress, whale: SignerWithAddress, trader: SignerWithAddress
  let balancerVault: Contract, pool: Contract, linearPool: Contract, gauge: Contract, usdc: Contract

  const toUSDC = (amount: number) => {
    return fp(amount).div(USDC_SCALING_FACTOR)
  }

  const SLIPPAGE = fp(0.03)
  const JOIN_AMOUNT = toUSDC(50)

  const expectWithError = (actual: BigNumber, expected: BigNumber) => {
    expect(actual).to.be.at.least(bn(expected).sub(1))
    expect(actual).to.be.at.most(bn(expected).add(1))
  }

  before('load signers', async () => {
    // eslint-disable-next-line prettier/prettier
    [owner, trader] = await getSigners(2)
    owner = await impersonate(owner.address, fp(100))
    whale = await impersonate(WHALE_WITH_USDC, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []
    const priceOracleTokens: string[] = [BAL, USDC]
    const priceOracleFeeds: string[] = [CHAINLINK_ORACLE_BAL_ETH, CHAINLINK_ORACLE_USDC_ETH]

    const priceOracle = await deploy(
      '@mimic-fi/v1-chainlink-price-oracle/artifacts/contracts/ChainLinkPriceOracle.sol/ChainLinkPriceOracle',
      [priceOracleTokens, priceOracleFeeds]
    )

    const swapConnector = await deploy(
      '@mimic-fi/v1-swap-connector/artifacts/contracts/SwapConnector.sol/SwapConnector',
      [priceOracle.address, UNISWAP_V3_ROUTER, UNISWAP_V2_ROUTER, BALANCER_V2_VAULT]
    )

    await swapConnector.setBalancerV2Path(
      [BAL, WETH, DAI, USDC],
      [POOL_BAL_WETH_ID, POOL_DAI_WETH_ID, POOL_DAI_USDC_ID]
    )

    vault = await deploy('@mimic-fi/v1-vault/artifacts/contracts/Vault.sol/Vault', [
      maxSlippage,
      protocolFee,
      priceOracle.address,
      swapConnector.address,
      whitelistedTokens,
      whitelistedStrategies,
    ])
  })

  before('deploy strategy', async () => {
    const factory = await deploy('BalancerBoostedStrategyFactory', [
      vault.address,
      BALANCER_VAULT,
      BALANCER_MINTER,
      GAUGE_ADDER,
    ])
    const createTx = await factory.connect(owner).create(USDC, POOL_DAI_USDC_USDT_ID, SLIPPAGE, 'metadata')
    const { args } = await assertEvent(createTx, 'StrategyCreated')
    strategy = await instanceAt('BalancerBoostedStrategy', args.strategy)
  })

  before('load dependencies', async () => {
    usdc = await instanceAt('IERC20', USDC)
    pool = await instanceAt('IBalancerPool', await strategy.getPool())
    linearPool = await instanceAt('IBalancerPool', await strategy.getLinearPool())
    gauge = await instanceAt('ILiquidityGauge', await strategy.getGauge())
    balancerVault = await instanceAt('IBalancerVault', BALANCER_VAULT)
  })

  before('deposit tokens', async () => {
    await usdc.connect(whale).approve(vault.address, toUSDC(100))
    await vault.connect(whale).deposit(whale.address, usdc.address, toUSDC(100), '0x')
  })

  it('has the correct owner', async () => {
    expect(await strategy.owner()).to.be.equal(owner.address)
  })

  it('joins strategy', async () => {
    const previousVaultBalance = await usdc.balanceOf(vault.address)
    expect(previousVaultBalance).to.be.equal(toUSDC(100))

    const previousStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(previousStrategyBalance).to.be.equal(0)

    const encodedSlippage = encodeSlippage(fp(0.01))
    await vault.connect(whale).join(whale.address, strategy.address, JOIN_AMOUNT, encodedSlippage)

    const currentVaultBalance = await usdc.balanceOf(vault.address)
    expect(currentVaultBalance).to.be.equal(previousVaultBalance.sub(JOIN_AMOUNT))

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(previousStrategyBalance)

    const strategyBptBalance = await pool.balanceOf(strategy.address)
    expect(strategyBptBalance).to.be.equal(0)

    const rate = await pool.getRate()
    const stakedBptBalance = await gauge.balanceOf(strategy.address)
    const expectedValue = stakedBptBalance.mul(rate).div(bn(1e18))

    const { invested, shares } = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(invested, expectedValue)
    expectWithError(shares, expectedValue)

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expect(strategyShares).to.be.equal(shares)

    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expectWithError(accountValue, strategyShares.mul(strategyShareValue).div(bn(1e18)))
  })

  it('accrues BAL earnings over time', async () => {
    const initialBalEarnings = await gauge.claimable_tokens(strategy.address)
    expect(initialBalEarnings).to.be.lt(100)

    await advanceTime(MONTH)

    const currentBalEarnings = await gauge.claimable_tokens(strategy.address)
    expect(currentBalEarnings).to.be.gt(initialBalEarnings)
  })

  it('gains swap fees from another trader account', async () => {
    const batchSwap = async (
      from: SignerWithAddress,
      poolId1: string,
      poolId2: string,
      amount: BigNumber,
      assetInIndex: number,
      assetConnectIndex: number,
      assetOutIndex: number,
      assets: Contract[]
    ) => {
      await assets[assetInIndex].connect(from).approve(balancerVault.address, amount)

      const swaps = [
        {
          poolId: poolId1,
          assetInIndex: assetInIndex,
          assetOutIndex: assetConnectIndex,
          amount: amount,
          userData: '0x',
        },
        {
          poolId: poolId2,
          assetInIndex: assetConnectIndex,
          assetOutIndex: assetOutIndex,
          amount: 0,
          userData: '0x',
        },
      ]

      const limits = []
      limits[assetInIndex] = amount
      limits[assetConnectIndex] = 0
      limits[assetOutIndex] = 0

      const funds = {
        sender: from.address,
        fromInternalBalance: false,
        recipient: from.address,
        toInternalBalance: false,
      }

      await balancerVault.connect(from).batchSwap(
        0, //GIVEN_IN
        swaps,
        assets.map((asset) => asset.address),
        funds,
        limits,
        MAX_UINT256
      )
    }

    let amount = toUSDC(2000000)
    await usdc.connect(whale).transfer(trader.address, amount)
    const previousValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    const assets = [pool, linearPool, usdc]

    for (let index = 0; index < 100; index++) {
      await batchSwap(trader, LINEAR_POOL_USDC_ID, POOL_DAI_USDC_USDT_ID, amount, 2, 1, 0, assets)
      amount = await pool.balanceOf(trader.address)
      await batchSwap(trader, POOL_DAI_USDC_USDT_ID, LINEAR_POOL_USDC_ID, amount, 0, 1, 2, assets)
      amount = await usdc.balanceOf(trader.address)
    }

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exits with a 50%', async () => {
    const previousBalance = await vault.getAccountBalance(whale.address, usdc.address)
    const previousInvestment = await vault.getAccountInvestment(whale.address, strategy.address)

    const exitRatio = fp(0.5)
    const encodedSlippage = encodeSlippage(fp(0.02))
    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, encodedSlippage)

    // The user should at least have some gains
    const currentBalance = await vault.getAccountBalance(whale.address, usdc.address)
    expect(currentBalance).to.be.gt(previousBalance)

    // There should not be any remaining tokens in the strategy
    const strategyUsdcBalance = await usdc.balanceOf(strategy.address)
    expect(strategyUsdcBalance).to.be.equal(0)

    const rate = await pool.getRate()
    const currentStakedBptBalance = await gauge.balanceOf(strategy.address)
    const expectedValue = currentStakedBptBalance.mul(rate).div(bn(1e18))
    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(currentInvestment.invested, expectedValue)

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(currentInvestment.shares, strategyShares)
    expectWithError(currentInvestment.shares, previousInvestment.shares.mul(exitRatio).div(fp(1)))

    // TODO: Review rounding issue
    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const expectedAccountValue = strategyShares.mul(strategyShareValue).div(fp(1))
    expect(accountValue).to.be.at.least(bn(expectedAccountValue).sub(50))
    expect(accountValue).to.be.at.most(bn(expectedAccountValue).add(50))

    // No rounding issues
    const totalValue = await strategy.getTotalValue()
    const strategyShareValueScaled = totalValue.mul(bn(1e36)).div(strategyShares)
    expectWithError(accountValue, strategyShares.mul(strategyShareValueScaled).div(bn(1e36)))
  })

  it('handles USDC airdrops', async () => {
    const previousValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    // Airdrop 1000 USDC and invest
    usdc.connect(trader).transfer(strategy.address, toUSDC(100))
    await strategy.invest(usdc.address, SLIPPAGE)

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exits with a 100%', async () => {
    const previousBalance = await vault.getAccountBalance(whale.address, usdc.address)

    const exitRatio = fp(1)
    const encodedSlippage = encodeSlippage(fp(0.02))
    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, encodedSlippage)

    // The user should at least have some gains
    const currentBalance = await vault.getAccountBalance(whale.address, usdc.address)
    expect(currentBalance).to.be.gt(previousBalance)

    // There should not be any remaining tokens in the strategy
    const strategyUsdcBalance = await usdc.balanceOf(strategy.address)
    expect(strategyUsdcBalance).to.be.equal(0)

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(currentInvestment.invested, bn(0))
    expectWithError(currentInvestment.shares, bn(0))

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(strategyShares, bn(0))

    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expectWithError(accountValue, bn(0))
  })
})
