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

const BAL = '0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3'
const USDC = '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'
const WETH = '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619'
const WMATIC = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270'
const WHALE = '0x9bdB521a97E95177BF252C253E256A60C3e14447'

const LIQUIDITY_GAUGE = 1
const GAUGE_FACTORY = '0x3b8cA519122CdD8efb272b0D3085453404B25bD0'
const BALANCER_MINTER = '0x0000000000000000000000000000000000000000'

const POOL_ID = '0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002'

const UNISWAP_V2_ROUTER = '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff'
const UNISWAP_V3_ROUTER = '0xE592427A0AEce92De3Edee1F18E0157C05861564'
const BALANCER_V2_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'

const PRICE_ONE_ORACLE = '0x1111111111111111111111111111111111111111'
const CHAINLINK_ORACLE_BAL_ETH = '0x03CD157746c61F44597dD54C6f6702105258C722'
const CHAINLINK_ORACLE_USDC_ETH = '0xefb7e6be8356cCc6827799B6A7348eE674A80EaE'
const CHAINLINK_ORACLE_WMATIC_ETH = '0x327e23A4855b6F663a28c5161541d69Af8973302'

describe('BalancerWeightedStrategy - WMATIC/USDC/WETH/BAL (polygon)', function () {
  let vault: Contract, strategy: Contract
  let owner: SignerWithAddress, whale: SignerWithAddress, trader: SignerWithAddress
  let balancerVault: Contract, pool: Contract, gauge: Contract, weth: Contract, usdc: Contract

  const toUSDC = (amount: number) => fp(amount).div(1e12)

  const SLIPPAGE = fp(0.03)
  const JOIN_AMOUNT = toUSDC(50)

  const expectWithError = (actual: BigNumber, expected: BigNumber) => {
    expect(actual).to.be.at.least(bn(expected).sub(1))
    expect(actual).to.be.at.most(bn(expected).add(1))
  }

  before('load signers', async () => {
    // eslint-disable-next-line prettier/prettier
    [, owner, trader] = await getSigners()
    owner = await impersonate(owner.address, fp(100))
    whale = await impersonate(WHALE, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    const priceOracleTokens: string[] = [BAL, USDC, WMATIC, WETH]
    const priceOracleFeeds: string[] = [
      CHAINLINK_ORACLE_BAL_ETH,
      CHAINLINK_ORACLE_USDC_ETH,
      CHAINLINK_ORACLE_WMATIC_ETH,
      PRICE_ONE_ORACLE,
    ]

    const priceOracle = await deploy(
      '@mimic-fi/v1-chainlink-price-oracle/artifacts/contracts/ChainLinkPriceOracle.sol/ChainLinkPriceOracle',
      [priceOracleTokens, priceOracleFeeds]
    )

    const swapConnector = await deploy(
      '@mimic-fi/v1-swap-connector/artifacts/contracts/SwapConnector.sol/SwapConnector',
      [priceOracle.address, UNISWAP_V3_ROUTER, UNISWAP_V2_ROUTER, BALANCER_V2_VAULT]
    )

    await swapConnector.setBalancerV2Path([BAL, USDC], [POOL_ID])

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
    const args = [vault.address, BALANCER_V2_VAULT, BALANCER_MINTER, GAUGE_FACTORY, LIQUIDITY_GAUGE]
    const libraries = { LogExpMath: (await deploy('LogExpMath')).address }
    const factory = await deploy('BalancerWeightedStrategyFactory', args, whale, libraries)

    const createTx = await factory.connect(owner).create(USDC, POOL_ID, SLIPPAGE, 'metadata:uri')
    const event = await assertEvent(createTx, 'StrategyCreated')
    strategy = await instanceAt('BalancerWeightedStrategy', event.args.strategy)
  })

  before('load dependencies', async () => {
    weth = await instanceAt('IERC20', WETH)
    usdc = await instanceAt('IERC20', USDC)
    pool = await instanceAt('IBalancerPool', await strategy.getPool())
    gauge = await instanceAt('IRewardOnlyGauge', await strategy.getGauge())
    balancerVault = await instanceAt('IBalancerVault', BALANCER_V2_VAULT)
  })

  before('deposit tokens', async () => {
    await usdc.connect(whale).approve(vault.address, toUSDC(100))
    await vault.connect(whale).deposit(WHALE, USDC, toUSDC(100), '0x')
  })

  it('deploys the strategy correctly', async () => {
    expect(await strategy.getVault()).to.be.equal(vault.address)
    expect(await strategy.getToken()).to.be.equal(USDC)
    expect(await strategy.getTokenScale()).to.be.equal(bn(1e12))
    expect(await strategy.getGauge()).to.be.equal(gauge.address)
    expect(await strategy.getPool()).to.be.equal(pool.address)
    expect(await strategy.getPoolId()).to.be.equal(POOL_ID)
    expect(await strategy.getBalancerVault()).to.be.equal(BALANCER_V2_VAULT)
    expect(await strategy.getSlippage()).to.be.equal(SLIPPAGE)
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri')
    expect(await strategy.getTotalValue()).to.be.equal(0)
    expect(await strategy.getValueRate()).to.be.gt(0)
    expect(await strategy.owner()).to.be.equal(owner.address)
  })

  it('allows the owner to set a new metadata', async () => {
    const newMetadata = 'metadata:uri:2.0'

    await strategy.connect(owner).setMetadataURI(newMetadata)
    expect(await strategy.getMetadataURI()).to.be.equal(newMetadata)

    await expect(strategy.setMetadataURI(newMetadata)).to.be.revertedWith('Ownable: caller is not the owner')
  })

  it('allows the owner to set a new slippage', async () => {
    const currentSlippage = await strategy.getSlippage()
    const newSlippage = currentSlippage.add(1)

    await strategy.connect(owner).setSlippage(newSlippage)
    expect(await strategy.getSlippage()).to.be.equal(newSlippage)

    await expect(strategy.setSlippage(newSlippage)).to.be.revertedWith('Ownable: caller is not the owner')
  })

  it('joins strategy', async () => {
    const previousVaultBalance = await usdc.balanceOf(vault.address)
    expect(previousVaultBalance).to.be.equal(toUSDC(100))

    const previousStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(previousStrategyBalance).to.be.equal(0)

    const encodedSlippage = encodeSlippage(fp(0.01))
    await vault.connect(whale).join(WHALE, strategy.address, JOIN_AMOUNT, encodedSlippage)

    const currentVaultBalance = await usdc.balanceOf(vault.address)
    expect(currentVaultBalance).to.be.equal(previousVaultBalance.sub(JOIN_AMOUNT))

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(previousStrategyBalance)

    const strategyBptBalance = await pool.balanceOf(strategy.address)
    expect(strategyBptBalance).to.be.equal(0)

    const rate = await pool.getRate()
    const stakedBptBalance = await gauge.balanceOf(strategy.address)
    const expectedValue = stakedBptBalance.mul(rate).div(fp(1))

    const { invested, shares } = await vault.getAccountInvestment(WHALE, strategy.address)
    expectWithError(invested, expectedValue)
    expectWithError(shares, expectedValue)

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expect(strategyShares).to.be.equal(shares)

    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const accountValue = await vault.getAccountCurrentValue(WHALE, strategy.address)
    expectWithError(accountValue, strategyShares.mul(strategyShareValue).div(fp(1)))
  })

  it('accrues BAL earnings over time', async () => {
    const initialBalEarnings = await gauge.claimable_reward_write(strategy.address, BAL)
    expect(initialBalEarnings).to.be.lt(100)

    await advanceTime(MONTH)

    const currentBalEarnings = await gauge.claimable_reward_write(strategy.address, BAL)
    expect(currentBalEarnings).to.be.gt(initialBalEarnings)
  })

  it('gains swap fees from another trader account', async () => {
    const swap = async (from: SignerWithAddress, amount: BigNumber, assetIn: Contract, assetOut: Contract) => {
      await assetIn.connect(from).approve(balancerVault.address, amount)

      const singleSwap = {
        poolId: POOL_ID,
        kind: 0, // GIVEN_IN
        assetIn: assetIn.address,
        assetOut: assetOut.address,
        amount,
        userData: '0x',
      }

      const funds = {
        sender: from.address,
        fromInternalBalance: false,
        recipient: from.address,
        toInternalBalance: false,
      }

      await balancerVault.connect(from).swap(singleSwap, funds, 0, MAX_UINT256)
    }

    await usdc.connect(whale).transfer(trader.address, toUSDC(1000))
    const previousValue = await vault.getAccountCurrentValue(WHALE, strategy.address)

    let amount: BigNumber
    for (let index = 0; index < 100; index++) {
      amount = toUSDC(100)
      await swap(trader, amount, usdc, weth)
      amount = await weth.balanceOf(trader.address)
      await swap(trader, amount, weth, usdc)
    }

    const currentValue = await vault.getAccountCurrentValue(WHALE, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exits with a 50%', async () => {
    const previousBalance = await vault.getAccountBalance(WHALE, USDC)
    const previousInvestment = await vault.getAccountInvestment(WHALE, strategy.address)

    const exitRatio = fp(0.5)
    const encodedSlippage = encodeSlippage(fp(0.02))
    await vault.connect(whale).exit(WHALE, strategy.address, exitRatio, false, encodedSlippage)

    // The user should at least have some gains
    const currentBalance = await vault.getAccountBalance(WHALE, USDC)
    expect(currentBalance).to.be.gt(previousBalance)

    // There should not be any remaining tokens in the strategy
    const strategyUsdcBalance = await usdc.balanceOf(strategy.address)
    expect(strategyUsdcBalance).to.be.equal(0)

    const rate = await pool.getRate()
    const currentStakedBptBalance = await gauge.balanceOf(strategy.address)
    const expectedValue = currentStakedBptBalance.mul(rate).div(fp(1))
    const currentInvestment = await vault.getAccountInvestment(WHALE, strategy.address)
    expectWithError(currentInvestment.invested, expectedValue)

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(currentInvestment.shares, strategyShares)
    expectWithError(currentInvestment.shares, previousInvestment.shares.mul(exitRatio).div(fp(1)))

    // TODO: Review rounding issue
    const accountValue = await vault.getAccountCurrentValue(WHALE, strategy.address)
    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const expectedAccountValue = strategyShares.mul(strategyShareValue).div(fp(1))
    expect(accountValue).to.be.at.least(bn(expectedAccountValue).sub(50))
    expect(accountValue).to.be.at.most(bn(expectedAccountValue).add(50))

    // No rounding issues
    const totalValue = await strategy.getTotalValue()
    const strategyShareValueScaled = totalValue.mul(bn(1e36)).div(strategyShares)
    expectWithError(accountValue, strategyShares.mul(strategyShareValueScaled).div(bn(1e36)))
  })

  it('handles WETH airdrops', async () => {
    const previousValue = await vault.getAccountCurrentValue(WHALE, strategy.address)

    // Airdrop 1 wETH and invest
    await weth.connect(whale).transfer(strategy.address, fp(1))
    await strategy.invest(WETH, SLIPPAGE)

    const currentValue = await vault.getAccountCurrentValue(WHALE, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exits with a 100%', async () => {
    const previousBalance = await vault.getAccountBalance(WHALE, USDC)

    const exitRatio = fp(1)
    const encodedSlippage = encodeSlippage(fp(0.02))
    await vault.connect(whale).exit(WHALE, strategy.address, exitRatio, false, encodedSlippage)

    // The user should at least have some gains
    const currentBalance = await vault.getAccountBalance(WHALE, USDC)
    expect(currentBalance).to.be.gt(previousBalance)

    // There should not be any remaining tokens in the strategy
    const strategyUsdcBalance = await usdc.balanceOf(strategy.address)
    expect(strategyUsdcBalance).to.be.equal(0)

    const currentInvestment = await vault.getAccountInvestment(WHALE, strategy.address)
    expectWithError(currentInvestment.invested, bn(0))
    expectWithError(currentInvestment.shares, bn(0))

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(strategyShares, bn(0))

    const accountValue = await vault.getAccountCurrentValue(WHALE, strategy.address)
    expectWithError(accountValue, bn(0))
  })
})
