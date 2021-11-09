import { Address, BigInt, ethereum, log } from '@graphprotocol/graph-ts'

import { Strategy as StrategyEntity, Rate as RateEntity } from '../types/schema'
import { BalancerStrategy as StrategyContract } from '../types/BalancerStableStrategyFactory/BalancerStrategy'

let ONE = BigInt.fromString('1000000000000000000')

export function createLastRate(strategy: StrategyEntity, block: ethereum.Block): void {
  let currentRate = calculateRate()

  if (strategy.lastRate === null) {
    storeLastRate(strategy, currentRate, BigInt.fromI32(0), block)
  } else {
    let lastRate = RateEntity.load(strategy.lastRate)!
    if (lastRate.value.notEqual(currentRate)) {
      let elapsed = block.number.minus(lastRate.block)
      let accumulated = lastRate.accumulated.plus(lastRate.value.times(elapsed))
      storeLastRate(strategy, currentRate, accumulated, block)
    }
  }
}

function storeLastRate(strategy: StrategyEntity, currentRate: BigInt, accumulated: BigInt, block: ethereum.Block): void {
  let shares = getStrategyShares(Address.fromString(strategy.id))
  let rateId = strategy.id + '-' + block.timestamp.toString()
  let rate = new RateEntity(rateId)
  rate.value = currentRate
  rate.accumulated = accumulated
  rate.shares = shares
  rate.strategy = strategy.id
  rate.timestamp = block.timestamp
  rate.block = block.number
  rate.save()

  strategy.lastRate = rateId
  strategy.deposited = shares.isZero() ? BigInt.fromI32(0) : shares.times(currentRate).div(ONE)
  strategy.save()
}

function calculateRate(): BigInt {
  // TODO: implement
  return BigInt.fromI32(0)
}

export function getStrategyShares(address: Address): BigInt {
  let strategyContract = StrategyContract.bind(address)
  let sharesCall = strategyContract.try_getTotalShares()

  if (!sharesCall.reverted) {
    return sharesCall.value
  }

  log.warning('getTotalShares() call reverted for {}', [address.toHexString()])
  return BigInt.fromI32(0)
}

export function getStrategyToken(address: Address): string {
  let strategyContract = StrategyContract.bind(address)
  let tokenCall = strategyContract.try_getToken()

  if (!tokenCall.reverted) {
    return tokenCall.value.toHexString()
  }

  log.warning('getToken() call reverted for {}', [address.toHexString()])
  return 'Unknown'
}

export function getStrategyMetadata(address: Address): string {
  let strategyContract = StrategyContract.bind(address)
  let metadataCall = strategyContract.try_getMetadataURI()

  if (!metadataCall.reverted) {
    return metadataCall.value
  }

  log.warning('getMetadataURI() call reverted for {}', [address.toHexString()])
  return 'Unknown'
}
