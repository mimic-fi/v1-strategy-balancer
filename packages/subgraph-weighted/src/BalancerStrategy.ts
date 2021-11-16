import {Address, BigInt, ethereum, log} from '@graphprotocol/graph-ts'

import { ERC20 as ERC20Contract } from '../types/templates/BalancerStrategy/ERC20'
import { BalancerPool as PoolContract } from '../types/templates/BalancerStrategy/BalancerPool'
import { BalancerStrategy as StrategyContract } from '../types/BalancerWeightedStrategyFactory/BalancerStrategy'
import { Rate as RateEntity, Strategy as StrategyEntity } from '../types/schema'

let ONE = BigInt.fromString('1000000000000000000')

export function createLastRate(strategy: StrategyEntity, block: ethereum.Block): void {
  let strategyAddress = Address.fromString(strategy.id)
  let rateId = strategy.id + '-' + block.timestamp.toString()
  let rate = new RateEntity(rateId)
  rate.feeRate = calculateFeeRate(strategy)
  rate.liquidityMiningRate = calculateLiquidityMiningRate(strategy)
  rate.shares = getStrategyShares(strategyAddress)
  rate.strategy = strategy.id
  rate.timestamp = block.timestamp
  rate.block = block.number
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
  let strategyAddress = Address.fromString(strategy.id)
  let totalShares = getStrategyShares(strategyAddress)
  if (totalShares.equals(BigInt.fromI32(0))) {
    return BigInt.fromI32(0)
  }

  let poolAddress = getStrategyPool(strategyAddress)
  let bptBalance = getTokenBalance(poolAddress, strategyAddress)
  return bptBalance.div(totalShares)
}

function calculateDeposited(strategy: StrategyEntity): BigInt {
  let strategyAddress = Address.fromString(strategy.id)
  let totalShares = getStrategyShares(strategyAddress)
  if (totalShares.equals(BigInt.fromI32(0))) {
    return BigInt.fromI32(0)
  }

  let poolAddress = getStrategyPool(strategyAddress)
  let bptBalance = getTokenBalance(poolAddress, strategyAddress)
  let bptPrice = getStrategyBptPrice(strategyAddress)
  return bptBalance.times(bptPrice).div(ONE)
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

export function getPoolRate(address: Address): BigInt {
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
