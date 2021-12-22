import { deploy, fp, getSigner, impersonate, impersonateWhale, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

describe.only('BalancerWeightedStrategy - USDC - Join', function () {
  let owner: SignerWithAddress,
    whale: SignerWithAddress,
    whaleWeth: SignerWithAddress,
    trader: SignerWithAddress,
    vault: Contract,
    strategy: Contract,
    bVault: Contract,
    bpt: Contract,
    weth: Contract,
    usdc: Contract,
    wbtc: Contract

  const WHALE_WITH_WETH = '0x4a18a50a8328b42773268B4b436254056b7d70CE'

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  const POOL_WBTC_WETH_ID = '0xa6f548df93de924d73be7d25dc02554c6bd66db500020000000000000000000e'
  const POOL_WBTC_WETH_ADDRESS = '0xa6f548df93de924d73be7d25dc02554c6bd66db5'

  // eslint-disable-next-line no-secrets/no-secrets
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
  const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
  // eslint-disable-next-line no-secrets/no-secrets
  const WBTC = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'

  const USDC_SCALING_FACTOR = 1e12

  // eslint-disable-next-line no-secrets/no-secrets
  const UNISWAP_V2_ROUTER_ADDRESS = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'

  // eslint-disable-next-line no-secrets/no-secrets
  const CHAINLINK_ORACLE_USDC_ETH = '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4'
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

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
    trader = await getSigner(1)
    whale = await impersonateWhale(fp(100))
    whaleWeth = await impersonate(WHALE_WITH_WETH, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    const priceOracleTokens: string[] = [WBTC, WETH, USDC]
    const priceOracleFeeds: string[] = [CHAINLINK_ORACLE_WBTC_ETH, PRICE_ONE_ORACLE, CHAINLINK_ORACLE_USDC_ETH]

    const priceOracle = await deploy('ChainLinkPriceOracle', [priceOracleTokens, priceOracleFeeds])
    const swapConnector = await deploy('UniswapConnector', [UNISWAP_V2_ROUTER_ADDRESS])

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
    bpt = await instanceAt('IERC20', POOL_WBTC_WETH_ADDRESS)
    weth = await instanceAt('IERC20', WETH)
    usdc = await instanceAt('IERC20', USDC)
    wbtc = await instanceAt('IERC20', WBTC)
  })

  before('deposit to Vault', async () => {
    await usdc.connect(whale).approve(vault.address, fp(100).div(USDC_SCALING_FACTOR))
    await vault.connect(whale).deposit(whale.address, usdc.address, fp(100).div(USDC_SCALING_FACTOR))
    await usdc.connect(whale).transfer(trader.address, fp(1000000).div(USDC_SCALING_FACTOR))
  })

  before('deploy strategy', async () => {
    const slippage = fp(0.01)
    strategy = await deploy('BalancerWeightedStrategy', [
      vault.address,
      usdc.address,
      bVault.address,
      POOL_WBTC_WETH_ID,
      weth.address,
      slippage,
      'metadata:uri',
    ])
  })

  it('join strategy', async () => {
    const amount = fp(50).div(USDC_SCALING_FACTOR)

    const previousVaultBalance = await usdc.balanceOf(vault.address)

    const previousStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(previousStrategyBalance).to.be.equal(0)

    await vault.connect(whale).join(whale.address, strategy.address, amount, '0x')

    const currentVaultBalance = await usdc.balanceOf(vault.address)
    expect(currentVaultBalance).to.be.equal(previousVaultBalance.sub(amount))

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(previousStrategyBalance)

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)
    expect(currentInvestment[0]).to.be.equal(amount)
    expect(currentInvestment[1].gt(0)).to.be.true

    const bptBalance = await bpt.balanceOf(strategy.address)
    const totalShares = await strategy.getTotalShares()
    expect(totalShares).to.be.equal(bptBalance)
  })

  it('more gains to recover lost in single token join slipage', async () => {
    let amount: BigNumber
    for (let index = 0; index < 200; index++) {
      amount = fp(1000)
      await swap(whaleWeth, amount, weth, wbtc)
      amount = await wbtc.balanceOf(whaleWeth.address)
      await swap(whaleWeth, amount, wbtc, weth)
    }
  })

  it('exit strategy', async () => {
    const initialAmount = fp(50).div(USDC_SCALING_FACTOR)
    const initialBalance = await vault.getAccountBalance(whale.address, usdc.address)

    await vault.connect(whale).exit(whale.address, strategy.address, fp(1), false, '0x')

    const currentBalance = await vault.getAccountBalance(whale.address, usdc.address)
    const finalAmount = currentBalance.sub(initialBalance)

    expect(finalAmount.gt(initialAmount)).to.be.true

    const currentStrategyBalance = await usdc.balanceOf(strategy.address)
    expect(currentStrategyBalance).to.be.equal(0)

    const currentInvestment = await vault.getAccountInvestment(whale.address, strategy.address)

    expect(currentInvestment[0]).to.be.equal(0)
    expect(currentInvestment[1]).to.be.equal(0)

    const bptBalance = await bpt.balanceOf(strategy.address)
    expect(bptBalance).to.be.equal(0)

    const totalShares = await strategy.getTotalShares()
    expect(totalShares).to.be.equal(0)
  })

  // it('handle WBTC airdrops', async () => {
  //   //airdrop 1000
  //   usdc.connect(whale).transfer(strategy.address, fp(1000).div(USDC_SCALING_FACTOR))

  //   //total shares = bpt
  //   const initialBptBalance = await bpt.balanceOf(strategy.address)
  //   const initialShares = await strategy.getTotalShares()

  //   expect(initialShares).to.be.equal(initialBptBalance)

  //   //invest aidrop
  //   await strategy.invest(usdc.address)

  //   //total shares < bpt
  //   const finalBptBalance = await bpt.balanceOf(strategy.address)
  //   const finalShares = await strategy.getTotalShares()

  //   expect(initialBptBalance.lt(finalBptBalance)).to.be.true
  //   expect(initialShares).to.be.equal(finalShares)
  // })

  // it('handle USDC airdrops + Join', async () => {
  //   const joinAmount = fp(50).div(USDC_SCALING_FACTOR)

  //   //Make it so there are some previous shares
  //   await vault.connect(whale).join(whale.address, strategy.address, joinAmount, '0x')

  //   const initialShares = await strategy.getTotalShares()

  //   //All usdc invested
  //   const usdcBalance = await usdc.balanceOf(strategy.address)
  //   expect(usdcBalance).to.be.equal(0)

  //   //airdrop 1000
  //   const aidrop = fp(100000).div(USDC_SCALING_FACTOR)
  //   await usdc.connect(whale).transfer(strategy.address, aidrop)

  //   //whale2 joins
  //   const depositAmount = joinAmount.mul(2)
  //   await usdc.connect(whale).transfer(whale2.address, depositAmount)
  //   await usdc.connect(whale2).approve(vault.address, depositAmount)
  //   await vault.connect(whale2).deposit(whale2.address, usdc.address, depositAmount)
  //   await vault.connect(whale2).join(whale2.address, strategy.address, joinAmount, '0x')

  //   //Final token balance includes 100k airdrop + joinAmount
  //   const finalShares = await strategy.getTotalShares()

  //   //shares obtained by the whale should be close to how much usdc it adds and not the airdropped one
  //   expect(
  //     finalShares
  //       .sub(initialShares)
  //       .mul(fp(1))
  //       .div(initialShares)
  //       .lte(joinAmount.mul(fp(1)).div(joinAmount.add(aidrop)))
  //   ).to.be.true
  // })
})
