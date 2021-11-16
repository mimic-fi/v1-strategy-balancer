#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

# Factory addresses
factory_localhost=0x0000000000000000000000000000000000000001
factory_kovan=0x9076432C409A9a04E1130f5439723F293CbA9ed9
factory_rinkeby=0x0000000000000000000000000000000000000001
factory_mainnet=0x0000000000000000000000000000000000000001

# Deployment block numbers
start_block_kovan=28398451
start_block_rinkeby=
start_block_mainnet=

# Validate network
networks=(localhost kovan rinkeby mainnet)
if [[ -z $NETWORK || ! " ${networks[@]} " =~ " ${NETWORK} " ]]; then
  echo 'Please make sure the network provided is either localhost, kovan, rinkeby, or mainnet.'
  exit 1
fi

# Use mainnet network in case of local deployment
if [[ "$NETWORK" = "localhost" ]]; then
  ENV='mainnet'
else
  ENV=${NETWORK}
fi

# Load start block
if [[ -z $START_BLOCK ]]; then
  START_BLOCK_VAR=start_block_$NETWORK
  START_BLOCK=${!START_BLOCK_VAR}
fi
if [[ -z $START_BLOCK ]]; then
  START_BLOCK=0
fi

# Try loading factory address if missing
if [[ -z $FACTORY ]]; then
  FACTORY_VAR=factory_$NETWORK
  FACTORY=${!FACTORY_VAR}
fi

# Validate factory address
if [[ -z $FACTORY ]]; then
  echo 'Please make sure a factory address is provided'
  exit 1
fi

# Remove previous manifest if there is any
if [ -f subgraph.yaml ]; then
  echo 'Removing previous subgraph manifest...'
  rm subgraph.yaml
fi

# Build subgraph manifest for requested variables
echo "Preparing new subgraph manifest for factory address ${FACTORY} and network ${NETWORK}"
cp subgraph.template.yaml subgraph.yaml
sed -i -e "s/{{network}}/${ENV}/g" subgraph.yaml
sed -i -e "s/{{factory}}/${FACTORY}/g" subgraph.yaml
sed -i -e "s/{{startBlock}}/${START_BLOCK}/g" subgraph.yaml
rm -f subgraph.yaml-e

# Run codegen and build
rm -rf ./types && yarn graph codegen -o types
yarn graph build
