import { bn, deploy, fp, getSigner, impersonate, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

describe('BalancerWeightedStrategy - ETH - Join', function () {
  let owner: SignerWithAddress,
    whale: SignerWithAddress,
    trader: SignerWithAddress,
    vault: Contract,
    strategy: Contract,
    bVault: Contract,
    pool: Contract,
    weth: Contract,
    wbtc: Contract

  const WHALE_WITH_WETH = '0x4a18a50a8328b42773268B4b436254056b7d70CE'

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  const POOL_WBTC_WETH_ID = '0xa6f548df93de924d73be7d25dc02554c6bd66db500020000000000000000000e'
  const POOL_WBTC_WETH_ADDRESS = '0xa6f548df93de924d73be7d25dc02554c6bd66db5'

  // eslint-disable-next-line no-secrets/no-secrets
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
  // eslint-disable-next-line no-secrets/no-secrets
  const WBTC = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'

  // eslint-disable-next-line no-secrets/no-secrets
  const UNISWAP_V2_ROUTER_ADDRESS = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'

  // eslint-disable-next-line no-secrets/no-secrets
  const CHAINLINK_ORACLE_WBTC_ETH = '0xdeb288F737066589598e9214E782fa5A8eD689e8'
  const PRICE_ONE_ORACLE = '0x1111111111111111111111111111111111111111'

  const swap = async (from: SignerWithAddress, amount: BigNumber, assetIn: Contract, assetOut: Contract) => {
    await assetIn.connect(from).approve(bVault.address, amount)

    const singleSwap = {
      poolId: POOL_WBTC_WETH_ID,
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

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
    trader = await getSigner(1)
    whale = await impersonate(WHALE_WITH_WETH, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    const priceOracleTokens: string[] = [WBTC, WETH]
    const priceOracleFeeds: string[] = [CHAINLINK_ORACLE_WBTC_ETH, PRICE_ONE_ORACLE]

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
    pool = await instanceAt('IBalancerPool', POOL_WBTC_WETH_ADDRESS)
    weth = await instanceAt('IERC20', WETH)
    wbtc = await instanceAt('IERC20', WBTC)
  })

  before('deposit to Vault', async () => {
    await weth.connect(whale).approve(vault.address, fp(100))
    await vault.connect(whale).deposit(whale.address, weth.address, fp(100), '0x')
    await weth.connect(whale).transfer(trader.address, fp(2000))
  })

  before('deploy strategy', async () => {
    const slippage = fp(0.01)
    strategy = await deploy('BalancerWeightedStrategy', [
      vault.address,
      weth.address,
      bVault.address,
      POOL_WBTC_WETH_ID,
      slippage,
      'metadata:uri',
    ])
  })

  it('join strategy', async () => {
    const amount = fp(50)

    const previousVaultBalance = await weth.balanceOf(vault.address)

    const previousStrategyBalance = await weth.balanceOf(strategy.address)
    expect(previousStrategyBalance).to.be.equal(0)

    await vault.connect(whale).join(whale.address, strategy.address, amount, '0x')

    const currentVaultBalance = await weth.balanceOf(vault.address)
    expect(currentVaultBalance).to.be.equal(previousVaultBalance.sub(amount))

    const currentStrategyBalance = await weth.balanceOf(strategy.address)
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
      amount = fp(1000)
      await swap(trader, amount, weth, wbtc)
      amount = await wbtc.balanceOf(trader.address)
      await swap(trader, amount, wbtc, weth)
    }

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exit  50% strategy', async () => {
    const exitRatio = fp(0.5)
    const initialAmount = fp(50).mul(exitRatio).div(bn(1e18))
    const initialBalance = await vault.getAccountBalance(whale.address, weth.address)

    const previousInvestment = await vault.getAccountInvestment(whale.address, strategy.address)

    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, '0x')

    const currentBalance = await vault.getAccountBalance(whale.address, weth.address)
    const finalAmount = currentBalance.sub(initialBalance)

    expect(finalAmount.gt(initialAmount)).to.be.true

    const currentStrategyBalance = await weth.balanceOf(strategy.address)
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
    expectWithError(accountValue, strategyShares.mul(strategyShareValue).div(bn(1e18)).add(2))

    //No roundiing issues
    const totalValue = await strategy.getTotalValue()
    const strategyShareValueScaled = totalValue.mul(bn(1e36)).div(strategyShares)
    expectWithError(accountValue, strategyShares.mul(strategyShareValueScaled).div(bn(1e36)))
  })

  it('handle ETH airdrops', async () => {
    const previousValue = await vault.getAccountCurrentValue(whale.address, strategy.address)

    //airdrop 1000
    weth.connect(trader).transfer(strategy.address, fp(100))
    //invest aidrop
    await strategy.invest(weth.address)

    const currentValue = await vault.getAccountCurrentValue(whale.address, strategy.address)
    expect(currentValue).to.be.gt(previousValue)
  })

  it('exit  100% strategy', async () => {
    const exitRatio = fp(1)
    const initialAmount = fp(25)
    const initialBalance = await vault.getAccountBalance(whale.address, weth.address)

    await vault.connect(whale).exit(whale.address, strategy.address, exitRatio, false, '0x')

    const currentBalance = await vault.getAccountBalance(whale.address, weth.address)
    const finalAmount = currentBalance.sub(initialBalance)

    expect(finalAmount.gt(initialAmount)).to.be.true

    const currentStrategyBalance = await weth.balanceOf(strategy.address)
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
