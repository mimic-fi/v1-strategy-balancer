import path from 'path'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@mimic-fi/v1-helpers/dist/tests'
import 'hardhat-local-networks-config-plugin'

import { homedir } from 'os'

export default {
  solidity: '0.8.0',
  localNetworksConfig: path.join(homedir(), '/.hardhat/networks.mimic.json'),
  mocha: {
    timeout: 40000,
  },
}
