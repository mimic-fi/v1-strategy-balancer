import { deploy, fp, getSigner, impersonate, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { Contract } from 'ethers'

describe('BalancerWeightedStrategy - Deploy', function () {
  let owner: SignerWithAddress, vault: Contract, strategy: Contract, dai: Contract

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  // eslint-disable-next-line no-secrets/no-secrets
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
  const POOL_ID = '0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a'

  before('load signers', async () => {
    owner = await getSigner()
    owner = await impersonate(owner.address, fp(100))
  })

  before('deploy vault', async () => {
    const maxSlippage = fp(0.02)
    const protocolFee = fp(0.00003)
    const priceOracle = owner.address // random address
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
    dai = await instanceAt('IERC20', DAI)
  })

  it('deploy strategy', async () => {
    const slippage = fp(0.01)
    strategy = await deploy('BalancerWeightedStrategy', [
      vault.address,
      dai.address,
      BALANCER_VAULT,
      POOL_ID,
      slippage,
      'metadata:uri',
    ])

    expect(await strategy.getVault()).to.be.equal(vault.address)
    expect(await strategy.getToken()).to.be.equal(dai.address)
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri')
    expect(await strategy.getTotalShares()).to.be.equal(0)
  })

  it('set metadataUri', async () => {
    await strategy.setMetadataURI('metadata:uri:2.0')
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri:2.0')
  })
})
