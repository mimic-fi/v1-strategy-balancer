import { expect } from 'chai'
import { Contract } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { deploy, fp, getSigner, instanceAt } from '@mimic-fi/v1-helpers'

describe('BalancerStrategy - Deploy', function () {
  let owner: SignerWithAddress, vault: Contract, strategy: Contract, dai: Contract, bal: Contract

  const BALANCER_VAULT = '0xBA12222222228d8Ba445958a75a0704d566BF2C8'
  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
  const POOL_ID = '0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a'
  const TOKEN_INDEX = 0
  const BAL = '0xba100000625a3754423978a60c9317c58a424e3D'

  before('load signers', async () => {
    owner = await getSigner()
  })

  before('deploy vault', async () => {
    const protocolFee = fp(0.00003)
    const swapConnector = owner.address // random address
    const whitelistedStrategies: string[] = []
    vault = await deploy('Vault', [protocolFee, swapConnector, whitelistedStrategies])
  })

  before('load tokens', async () => {
    dai = await instanceAt('IERC20', DAI)
    bal = await instanceAt('IERC20', BAL)
  })

  it('deploy strategy', async () => {
    strategy = await deploy('BalancerStrategy', [vault.address, dai.address, BALANCER_VAULT, POOL_ID, TOKEN_INDEX, bal.address, 'metadata:uri'])

    expect(await strategy.vault()).to.be.equal(vault.address)
    expect(await strategy.token()).to.be.equal(dai.address)
    expect(await strategy.poolId()).to.be.equal(POOL_ID)
    expect(await strategy.balancerVault()).to.be.equal(BALANCER_VAULT)
    expect(await strategy.tokenIndex()).to.be.equal(TOKEN_INDEX)
    expect(await strategy.balToken()).to.be.equal(bal.address)

    expect(await strategy.getToken()).to.be.equal(dai.address)
    expect(await strategy.getMetadataURI()).to.be.equal('metadata:uri')

    expect(await strategy.getTotalShares()).to.be.equal(0)
    expect(await strategy.getTokenBalance()).to.be.equal(0)
  })
})
