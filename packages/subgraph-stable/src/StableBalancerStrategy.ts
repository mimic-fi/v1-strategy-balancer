import {Address, BigInt, ethereum, log} from '@graphprotocol/graph-ts'

import {
  BalancerStableStrategyFactory as FactoryContract,
  StrategyCreated
} from '../types/BalancerStableStrategyFactory/BalancerStableStrategyFactory'
import {ERC20 as ERC20Contract} from '../types/templates/BalancerStrategy/ERC20'
import {BalancerPool as PoolContract} from '../types/templates/BalancerStrategy/BalancerPool'
import {BalancerStrategy as StrategyTemplate} from '../types/templates'
import {BalancerStrategy as StrategyContract} from '../types/BalancerStableStrategyFactory/BalancerStrategy'
import {Factory as FactoryEntity, Rate as RateEntity, Strategy as StrategyEntity} from '../types/schema'

const FACTORY_ID = 'BALANCER_STABLE'
const ONE = BigInt.fromString('1000000000000000000')

export function handleStrategyCreated(event: StrategyCreated): void {
  let factory = loadOrCreateFactory(event.address)

  let strategies = factory.strategies
  strategies.push(event.params.strategy.toHexString())
  factory.strategies = strategies
  factory.save()

  StrategyTemplate.create(event.params.strategy)
}

export function handleBlock(block: ethereum.Block): void {
  let factory = FactoryEntity.load(FACTORY_ID)
  if (factory !== null && factory.strategies !== null) {
    let strategies = factory.strategies
    for (let i: i32 = 0; i < strategies.length; i++) {
      let strategy = loadOrCreateStrategy(strategies[i], factory.id, factory.address)
      if (strategy !== null) createLastRate(strategy!, block)
    }
  }
}

function loadOrCreateFactory(factoryAddress: Address): FactoryEntity {
  let factory = FactoryEntity.load(FACTORY_ID)

  if (factory === null) {
    factory = new FactoryEntity(FACTORY_ID)
    factory.strategies = []
    factory.address = factoryAddress.toHexString()
    factory.save()
  }

  return factory!
}

function loadOrCreateStrategy(strategyAddress: string, factoryId: string, factoryAddress: string): StrategyEntity {
  let strategy = StrategyEntity.load(strategyAddress)

  if (strategy === null) {
    strategy = new StrategyEntity(strategyAddress)
    strategy.factory = factoryId
    strategy.vault = getFactoryVault(factoryAddress).toHexString()
    strategy.token = getStrategyToken(strategyAddress).toHexString()
    strategy.metadata = getStrategyMetadata(strategyAddress)
    strategy.deposited = BigInt.fromI32(0)
    strategy.shares = BigInt.fromI32(0)
    strategy.save()
  }

  return strategy!
}

function createLastRate(strategy: StrategyEntity, block: ethereum.Block): void {
  let rateId = strategy.id + '-' + block.timestamp.toString()
  let rate = new RateEntity(rateId)
  rate.accumulators = []
  rate.shares = getStrategyShares(strategy.id)
  rate.strategy = strategy.id
  rate.timestamp = block.timestamp
  rate.block = block.number
  rate.save()

  let accumulators = rate.accumulators
  accumulators.push(calculateFeeRate(strategy))
  accumulators.push(calculateLiquidityMiningRate(strategy))
  rate.accumulators = accumulators
  rate.save()

  strategy.lastRate = rateId
  strategy.deposited = calculateDeposited(strategy)
  strategy.save()
}

function calculateFeeRate(strategy: StrategyEntity): BigInt {
  let strategyAddress = Address.fromString(strategy.id)
  let poolAddress = getStrategyPool(strategyAddress)
  return getPoolRate(poolAddress)
}

function calculateLiquidityMiningRate(strategy: StrategyEntity): BigInt {
  let totalShares = getStrategyShares(strategy.id)
  if (totalShares.equals(BigInt.fromI32(0))) {
    return BigInt.fromI32(0)
  }

  let strategyAddress = Address.fromString(strategy.id)
  let poolAddress = getStrategyPool(strategyAddress)
  let bptBalance = getTokenBalance(poolAddress, strategyAddress)
  return bptBalance.div(totalShares)
}

function calculateDeposited(strategy: StrategyEntity): BigInt {
  let totalShares = getStrategyShares(strategy.id)
  if (totalShares.equals(BigInt.fromI32(0))) {
    return BigInt.fromI32(0)
  }

  let strategyAddress = Address.fromString(strategy.id)
  let poolAddress = getStrategyPool(strategyAddress)
  let bptBalance = getTokenBalance(poolAddress, strategyAddress)
  let bptPrice = getStrategyBptPrice(strategyAddress)
  return bptBalance.times(bptPrice).div(ONE)
}

function getFactoryVault(address: string): Address {
  let factoryContract = FactoryContract.bind(Address.fromString(address))
  let vaultCall = factoryContract.try_vault()

  if (!vaultCall.reverted) {
    return vaultCall.value
  }

  log.warning('vault() call reverted for {}', [address])
  return Address.fromString('0x0000000000000000000000000000000000000000')
}

function getStrategyShares(address: string): BigInt {
  let strategyContract = StrategyContract.bind(Address.fromString(address))
  let sharesCall = strategyContract.try_getTotalShares()

  if (!sharesCall.reverted) {
    return sharesCall.value
  }

  log.warning('getTotalShares() call reverted for {}', [address])
  return BigInt.fromI32(0)
}

function getStrategyToken(address: string): Address {
  let strategyContract = StrategyContract.bind(Address.fromString(address))
  let tokenCall = strategyContract.try_getToken()

  if (!tokenCall.reverted) {
    return tokenCall.value
  }

  log.warning('getToken() call reverted for {}', [address])
  return Address.fromString('0x0000000000000000000000000000000000000000')
}

function getStrategyMetadata(address: string): string {
  let strategyContract = StrategyContract.bind(Address.fromString(address))
  let metadataCall = strategyContract.try_getMetadataURI()

  if (!metadataCall.reverted) {
    return metadataCall.value
  }

  log.warning('getMetadataURI() call reverted for {}', [address])
  return 'Unknown'
}

function getStrategyPool(address: Address): Address {
  let strategyContract = StrategyContract.bind(address)
  let poolAddressCall = strategyContract.try_getPoolAddress()

  if (!poolAddressCall.reverted) {
    return poolAddressCall.value
  }

  log.warning('getPoolAddress() call reverted for {}', [address.toHexString()])
  return Address.fromString('0x0000000000000000000000000000000000000000')
}

function getStrategyBptPrice(address: Address): BigInt {
  let strategyContract = StrategyContract.bind(address)
  let bptPriceCall = strategyContract.try_getBptPerTokenPrice()

  if (!bptPriceCall.reverted) {
    return bptPriceCall.value
  }

  log.warning('getBptPerTokenPrice() call reverted for {}', [address.toHexString()])
  return BigInt.fromI32(0)
}

function getPoolRate(address: Address): BigInt {
  let poolContract = PoolContract.bind(address)
  let rateCall = poolContract.try_getRate()

  if (!rateCall.reverted) {
    return rateCall.value
  }

  log.warning('getRate() call reverted for {}', [address.toHexString()])
  return BigInt.fromI32(0)
}

function getTokenBalance(address: Address, account: Address): BigInt {
  let tokenContract = ERC20Contract.bind(address)
  let balanceCall = tokenContract.try_balanceOf(account)

  if (!balanceCall.reverted) {
    return balanceCall.value
  }

  log.warning('balanceOf() call reverted for {}', [address.toHexString()])
  return BigInt.fromI32(0)
}
