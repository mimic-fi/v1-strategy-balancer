import { Address, BigInt, ethereum, log } from '@graphprotocol/graph-ts'

import { StrategyCreated } from '../types/BalancerWeightedStrategyFactory/BalancerWeightedStrategyFactory'
import { BalancerWeightedStrategyFactory as FactoryContract } from '../types/BalancerWeightedStrategyFactory/BalancerWeightedStrategyFactory'
import { Factory as FactoryEntity, Strategy as StrategyEntity } from '../types/schema'
import { createLastRate, getStrategyToken, getStrategyMetadata } from './BalancerStrategy'

const FACTORY_ID = 'BALANCER_WEIGHTED'

export function handleStrategyCreated(event: StrategyCreated): void {
  let factory = loadOrCreateFactory(event.address)
  let strategy = loadOrCreateStrategy(event.params.strategy, event.address)

  let strategies = factory.strategies
  strategies.push(strategy.id)
  factory.strategies = strategies
  factory.save()
}

export function handleBlock(block: ethereum.Block): void {
  let factory = FactoryEntity.load(FACTORY_ID)
  if (factory !== null && factory.strategies !== null) {
    let strategies = factory.strategies
    for (let i: i32 = 0; i < strategies.length; i++) {
      let strategy = StrategyEntity.load(strategies[i])
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

function loadOrCreateStrategy(strategyAddress: Address, factoryAddress: Address): StrategyEntity {
  let id = strategyAddress.toHexString()
  let strategy = StrategyEntity.load(id)

  if (strategy === null) {
    strategy = new StrategyEntity(id)
    strategy.factory = factoryAddress.toHexString()
    strategy.vault = getFactoryVault(factoryAddress)
    strategy.token = ''
    strategy.metadata = ''
    strategy.deposited = BigInt.fromI32(0)
    strategy.shares = BigInt.fromI32(0)
    strategy.save()
  } else if (strategy.metadata == '') {
    strategy.token = getStrategyToken(strategyAddress)
    strategy.metadata = getStrategyMetadata(strategyAddress)
    strategy.save()
  }

  return strategy!
}

function getFactoryVault(address: Address): string {
  let factoryContract = FactoryContract.bind(address)
  let vaultCall = factoryContract.try_vault()

  if (!vaultCall.reverted) {
    return vaultCall.value.toHexString()
  }

  log.warning('vault() call reverted for {}', [address.toHexString()])
  return 'Unknown'
}
