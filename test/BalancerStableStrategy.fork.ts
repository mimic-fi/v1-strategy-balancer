import { bn, deploy, fp, getSigner, impersonate, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

describe('BalancerStableStrategy - USDC - Join', function () {
  let owner: SignerWithAddress,
    whale: SignerWithAddress,
    trader: SignerWithAddress,
    vault: Contract,
    strategy: Contract,
    bVault: Contract,
    pool: Contract,
    usdc: Contract,
    dai: Contract

  // eslint-disable-next-line no-secrets/no-secrets
  const WHALE_WITH_USDC = '0x55FE002aefF02F77364de339a1292923A15844B8'

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  const POOL_DAI_USDC_USDT_ID = '0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063'
  const POOL_DAI_USDC_USDT_ADDRESS = '0x06df3b2bbb68adc8b0e302443692037ed9f91b42'

  // eslint-disable-next-line no-secrets/no-secrets
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
  // eslint-disable-next-line no-secrets/no-secrets
  const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
  // eslint-disable-next-line no-secrets/no-secrets
  const USDT = '0xdAC17F958D2ee523a2206206994597C13D831ec7'

  const USDC_SCALING_FACTOR = 1e12

  // eslint-disable-next-line no-secrets/no-secrets
  const UNISWAP_V2_ROUTER_ADDRESS = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'

  const CHAINLINK_ORACLE_DAI_ETH = '0x773616E4d11A78F511299002da57A0a94577F1f4'
  // eslint-disable-next-line no-secrets/no-secrets
  const CHAINLINK_ORACLE_USDC_ETH = '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4'
  // eslint-disable-next-line no-secrets/no-secrets
  const CHAINLINK_ORACLE_USDT_ETH = '0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46'

  const swap = async (from: SignerWithAddress, amount: BigNumber, assetIn: Contract, assetOut: Contract) => {
    await assetIn.connect(from).approve(bVault.address, amount)

    const singleSwap = {
      poolId: POOL_DAI_USDC_USDT_ID,
      kind: 0, //GIVEN_IN
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
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20

    await bVault.connect(from).swap(singleSwap, funds, 0, deadline)
  }

  const expectWithError = (actual: BigNumber, expected: BigNumber) => {
    expect(actual).to.be.at.least(bn(expected).sub(1))
    expect(actual).to.be.at.most(bn(expected).add(1))
  }

  const toUSDC = (amount: number) => {
    return fp(amount).div(USDC_SCALING_FACTOR)
  }

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
    trader = await getSigner(1)
    whale = await impersonate(WHALE_WITH_USDC, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    const priceOracleTokens: string[] = [DAI, USDC, USDT]
    const priceOracleFeeds: string[] = [CHAINLINK_ORACLE_DAI_ETH, CHAINLINK_ORACLE_USDC_ETH, CHAINLINK_ORACLE_USDT_ETH]

    const priceOracle = await deploy(
      '@mimic-fi/v1-chainlink-price-oracle/artifacts/contracts/ChainLinkPriceOracle.sol/ChainLinkPriceOracle',
      [priceOracleTokens, priceOracleFeeds]
    )

    const swapConnector = await deploy(
      '@mimic-fi/v1-uniswap-connector/artifacts/contracts/UniswapConnector.sol/UniswapConnector',
      [UNISWAP_V2_ROUTER_ADDRESS]
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

  before('load tokens', async () => {
    bVault = await instanceAt('IBalancerVault', BALANCER_VAULT)
    pool = await instanceAt('IBalancerPool', POOL_DAI_USDC_USDT_ADDRESS)
    usdc = await instanceAt('IERC20', USDC)
    dai = await instanceAt('IERC20', DAI)
  })

  before('deposit to Vault', async () => {
    await usdc.connect(whale).approve(vault.address, toUSDC(100))
    await vault.connect(whale).deposit(whale.address, usdc.address, toUSDC(100))
    await usdc.connect(whale).transfer(trader.address, toUSDC(2500000))
  })

  before('deploy strategy', async () => {
    const slippage = fp(0.01)
    strategy = await deploy('BalancerStableStrategy', [
      vault.address,
      usdc.address,
      bVault.address,
      POOL_DAI_USDC_USDT_ID,
      slippage,
      'metadata:uri',
    ])
  })

  it('join strategy', async () => {
    const amount = toUSDC(50)

    const previousVaultBalance = await usdc.balanceOf(vault.address)

    const previousStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(previousStrategyBalance).to.be.equal(0)

    await vault.connect(whale).join(whale.address, strategy.address, amount, '0x')

    const currentVaultBalance = await usdc.balanceOf(vault.address)
    expect(currentVaultBalance).to.be.equal(previousVaultBalance.sub(amount))

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(previousStrategyBalance)

    const strategyBptBalance = await pool.balanceOf(strategy.address)
    const rate = await pool.getRate()
    const expectedValue = strategyBptBalance.mul(rate).div(bn(1e18))

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(currentInvestment[0], expectedValue)
    expectWithError(currentInvestment[1], expectedValue)

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(currentInvestment[1], strategyShares)

    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expectWithError(accountValue, strategyShares.mul(strategyShareValue).div(bn(1e18)))
  })

  it('more gains to recover lost in single token join slipage', async () => {
    const previousValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    let amount: BigNumber
    for (let index = 0; index < 100; index++) {
      amount = toUSDC(2000000)
      await swap(trader, amount, usdc, dai)
      amount = await dai.balanceOf(trader.address)
      await swap(trader, amount, dai, usdc)
    }

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exit  50% strategy', async () => {
    const exitRatio = fp(0.5)
    const initialAmount = toUSDC(50).mul(exitRatio).div(bn(1e18))
    const initialBalance = await vault.getAccountBalance(whale.address, usdc.address)

    const previousInvestment = await vault.getAccountInvestment(whale.address, strategy.address)

    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, '0x')

    const currentBalance = await vault.getAccountBalance(whale.address, usdc.address)
    const finalAmount = currentBalance.sub(initialBalance)

    expect(finalAmount.gt(initialAmount)).to.be.true

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(0)

    const strategyBptBalance = await pool.balanceOf(strategy.address)
    const rate = await pool.getRate()
    const expectedValue = strategyBptBalance.mul(rate).div(bn(1e18))

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(currentInvestment[0], expectedValue)
    expectWithError(currentInvestment[1], previousInvestment[1].sub(previousInvestment[1].mul(exitRatio).div(bn(1e18))))

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(currentInvestment[1], strategyShares)

    const strategyShareValue = await vault.getStrategyShareValue(strategy.address)
    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    //rounding issue
    expectWithError(accountValue, strategyShares.mul(strategyShareValue).div(bn(1e18)).add(12))

    //No roundiing issues
    const totalValue = await strategy.getTotalValue()
    const strategyShareValueScaled = totalValue.mul(bn(1e36)).div(strategyShares)
    expectWithError(accountValue, strategyShares.mul(strategyShareValueScaled).div(bn(1e36)))
  })

  it('handle ETH airdrops', async () => {
    const previousValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    //airdrop 1000
    usdc.connect(trader).transfer(strategy.address, toUSDC(100))
    //invest aidrop
    await strategy.invest(usdc.address)

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exit  100% strategy', async () => {
    const exitRatio = fp(1)
    const initialAmount = toUSDC(25)
    const initialBalance = await vault.getAccountBalance(whale.address, usdc.address)

    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, '0x')

    const currentBalance = await vault.getAccountBalance(whale.address, usdc.address)
    const finalAmount = currentBalance.sub(initialBalance)

    expect(finalAmount.gt(initialAmount)).to.be.true

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(0)

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expectWithError(currentInvestment[0], bn(0))
    expectWithError(currentInvestment[1], bn(0))

    const strategyShares = await vault.getStrategyShares(strategy.address)
    expectWithError(strategyShares, bn(0))

    const accountValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expectWithError(accountValue, bn(0))
  })
})
