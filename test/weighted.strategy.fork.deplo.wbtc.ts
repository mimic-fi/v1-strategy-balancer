import { deploy, fp, getSigner, impersonate, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { Contract } from 'ethers'

describe('BalancerWeightedStrategy - Deploy', function () {
  let owner: SignerWithAddress, vault: Contract, strategy: Contract, wbtc: Contract

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  // eslint-disable-next-line no-secrets/no-secrets
  const WBTC = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'
  const POOL_ID = '0xa6f548df93de924d73be7d25dc02554c6bd66db500020000000000000000000e'

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const priceOracle = '0x8d2185c92f567b6a6e41b691953f12269c259971'
    const swapConnector = owner.address // random address
    const whitelistedTokens: string[] = []
    const whitelistedStrategies: string[] = []

    vault = await deploy('@mimic-fi/v1-vault/artifacts/contracts/Vault.sol/Vault', [
      maxSlippage,
      protocolFee,
      priceOracle,
      swapConnector,
      whitelistedTokens,
      whitelistedStrategies,
    ])
  })

  before('load tokens', async () => {
    wbtc = await instanceAt('IERC20', WBTC)
  })

  it('deploy strategy', async () => {
    const slippage = fp(0.01)
    strategy = await deploy('BalancerWeightedStrategy', [
      vault.address,
      wbtc.address,
      BALANCER_VAULT,
      POOL_ID,
      slippage,
      'metadata:uri',
    ])

    expect(await strategy.getVault()).to.be.equal(vault.address)
    expect(await strategy.getToken()).to.be.equal(wbtc.address)
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri')
    expect(await strategy.getTotalShares()).to.be.equal(0)
  })

  it('set metadataUri', async () => {
    await strategy.setMetadataURI('metadata:uri:2.0')
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri:2.0')
  })
})
