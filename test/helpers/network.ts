import { ethers } from 'hardhat'

export const incrementBlock = async (n: number): Promise<void> => {
  const promises = []

  for (let i = 0; i < n; i++) {
    promises.push(ethers.provider.send('evm_mine', []))
  }

  await Promise.all(promises)
}
