import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@mimic-fi/v1-helpers/dist/tests'
import 'hardhat-local-networks-config-plugin'

import { overrideFunctions } from '@mimic-fi/v1-helpers'
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names'
import { task } from 'hardhat/config'
import { homedir } from 'os'
import path from 'path'

task(TASK_COMPILE).setAction(overrideFunctions(['claimable_tokens']))

export default {
  localNetworksConfig: path.join(homedir(), '/.hardhat/networks.mimic.json'),
  solidity: {
    version: '0.8.0',
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000,
      },
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
  },
  mocha: {
    timeout: 40000,
  },
}
