import { bn, deploy, fp, getSigner, impersonate, impersonateWhale, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'

describe('BalancerWeightedStrategy - USDC - Join', function () {
  let owner: SignerWithAddress,
    whale: SignerWithAddress,
    whale2: SignerWithAddress,
    trader: SignerWithAddress,
    vault: Contract,
    strategy: Contract,
    bal: Contract,
    bVault: Contract,
    bpt: Contract,
    weth: Contract,
    usdc: Contract

  const WHALE_WITH_BAL = '0x967159C42568A54D11a4761fC86a6089eD42B7ba'

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  const POOL_USDC_WETH_ID = '0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019'
  const POOL_USDC_WETH_ADDRESS = '0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8'
  const TOKEN_INDEX = 0

  // eslint-disable-next-line no-secrets/no-secrets
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
  const BAL = '0xba100000625a3754423978a60c9317c58a424e3D'
  // eslint-disable-next-line no-secrets/no-secrets
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
  const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'

  const USDC_SCALING_FACTOR = 1e12

  // eslint-disable-next-line no-secrets/no-secrets
  const UNISWAP_V2_ROUTER_ADDRESS = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'

  const CHAINLINK_ORACLE_DAI_ETH = '0x773616E4d11A78F511299002da57A0a94577F1f4'
  // eslint-disable-next-line no-secrets/no-secrets
  const CHAINLINK_ORACLE_USDC_ETH = '0x986b5E1e1755e3C2440e960477f25201B0a8bbD4'
  const PRICE_ONE_ORACLE = '0x1111111111111111111111111111111111111111'

  const MAX_UINT_256 = bn(2).pow(256).sub(1)

  const swap = async (amount: BigNumber, assetIn: Contract, assetOut: Contract) => {
    await assetIn.connect(trader).approve(bVault.address, amount)

    const singleSwap = {
      poolId: POOL_USDC_WETH_ID,
      kind: 0, //GIVEN_IN
      assetIn: assetIn.address,
      assetOut: assetOut.address,
      amount,
      userData: '0x',
    }

    const funds = {
      sender: trader.address,
      fromInternalBalance: false,
      recipient: trader.address,
      toInternalBalance: false,
    }
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20

    await bVault.connect(trader).swap(singleSwap, funds, 0, deadline)
  }

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
    trader = await getSigner(1)
    whale = await impersonateWhale(fp(100))
    whale2 = await impersonate(WHALE_WITH_BAL, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    const priceOracleTokens: string[] = [DAI, WETH, USDC]
    const priceOracleFeeds: string[] = [CHAINLINK_ORACLE_DAI_ETH, PRICE_ONE_ORACLE, CHAINLINK_ORACLE_USDC_ETH]

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
    bpt = await instanceAt('IERC20', POOL_USDC_WETH_ADDRESS)
    bal = await instanceAt('IERC20', BAL)
    weth = await instanceAt('IERC20', WETH)
    usdc = await instanceAt('IERC20', USDC)
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
      POOL_USDC_WETH_ID,
      TOKEN_INDEX,
      bal.address,
      slippage,
      'metadata:uri',
    ])
  })

  it('vault has max USDC allowance', async () => {
    const allowance = await usdc.allowance(strategy.address, vault.address)
    expect(allowance).to.be.equal(MAX_UINT_256)
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
    for (let index = 0; index < 100; index++) {
      amount = await usdc.balanceOf(trader.address)
      await swap(amount, usdc, weth)
      amount = await weth.balanceOf(trader.address)
      await swap(amount, weth, usdc)
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

  it('can give token allowance to vault and ctoken', async () => {
    await strategy.approveTokenSpenders()

    const vaultAllowance = await usdc.allowance(strategy.address, vault.address)
    expect(vaultAllowance).to.be.equal(MAX_UINT_256)

    const balancerVaultAllowance = await usdc.allowance(strategy.address, BALANCER_VAULT)
    expect(balancerVaultAllowance).to.be.equal(MAX_UINT_256)
  })

  it('handle USDC airdrops', async () => {
    //airdrop 1000
    usdc.connect(whale).transfer(strategy.address, fp(1000).div(USDC_SCALING_FACTOR))

    //total shares = bpt
    const initialBptBalance = await bpt.balanceOf(strategy.address)
    const initialShares = await strategy.getTotalShares()

    expect(initialShares).to.be.equal(initialBptBalance)

    //invest aidrop
    await strategy.invest(usdc.address)

    //total shares < bpt
    const finalBptBalance = await bpt.balanceOf(strategy.address)
    const finalShares = await strategy.getTotalShares()

    expect(initialBptBalance.lt(finalBptBalance)).to.be.true
    expect(initialShares).to.be.equal(finalShares)
  })

  it('handle USDC airdrops + Join', async () => {
    const joinAmount = fp(50).div(USDC_SCALING_FACTOR)

    //Make it so there are some previous shares
    await vault.connect(whale).join(whale.address, strategy.address, joinAmount, '0x')

    const initialShares = await strategy.getTotalShares()

    //All usdc invested
    const usdcBalance = await usdc.balanceOf(strategy.address)
    expect(usdcBalance).to.be.equal(0)

    //airdrop 1000
    const aidrop = fp(100000).div(USDC_SCALING_FACTOR)
    await usdc.connect(whale).transfer(strategy.address, aidrop)

    //whale2 joins
    const depositAmount = joinAmount.mul(2)
    await usdc.connect(whale).transfer(whale2.address, depositAmount)
    await usdc.connect(whale2).approve(vault.address, depositAmount)
    await vault.connect(whale2).deposit(whale2.address, usdc.address, depositAmount)
    await vault.connect(whale2).join(whale2.address, strategy.address, joinAmount, '0x')

    //Final token balance includes 100k airdrop + joinAmount
    const finalShares = await strategy.getTotalShares()

    //shares obtained by the whale should be close to how much usdc it adds and not the airdropped one
    expect(
      finalShares
        .sub(initialShares)
        .mul(fp(1))
        .div(initialShares)
        .lte(joinAmount.mul(fp(1)).div(joinAmount.add(aidrop)))
    ).to.be.true
  })
})
