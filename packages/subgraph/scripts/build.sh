#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

# Weighted strategy factory addresses
weighted_factory_localhost=0x0000000000000000000000000000000000000001
weighted_factory_kovan=0x0000000000000000000000000000000000000001
weighted_factory_rinkeby=0x0000000000000000000000000000000000000001
weighted_factory_mainnet=0x0000000000000000000000000000000000000001

# Weighted deployment block numbers
weighted_start_block_kovan=
weighted_start_block_rinkeby=
weighted_start_block_mainnet=

# Stable strategy factory addresses
stable_factory_localhost=0x0000000000000000000000000000000000000001
stable_factory_kovan=0x0000000000000000000000000000000000000001
stable_factory_rinkeby=0x0000000000000000000000000000000000000001
stable_factory_mainnet=0x0000000000000000000000000000000000000001

# Stable deployment block numbers
stable_start_block_kovan=
stable_start_block_rinkeby=
stable_start_block_mainnet=

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

# Load weighted start block
if [[ -z $WEIGHTED_START_BLOCK ]]; then
  WEIGHTED_START_BLOCK_VAR=weighted_start_block_$NETWORK
  WEIGHTED_START_BLOCK=${!WEIGHTED_START_BLOCK_VAR}
fi
if [[ -z $WEIGHTED_START_BLOCK ]]; then
  WEIGHTED_START_BLOCK=0
fi

# Try loading weighted factory address if missing
if [[ -z $WEIGHTED_FACTORY ]]; then
  WEIGHTED_FACTORY_VAR=weighted_factory_$NETWORK
  WEIGHTED_FACTORY=${!WEIGHTED_FACTORY_VAR}
fi

# Validate strategy address
if [[ -z $WEIGHTED_FACTORY ]]; then
  echo 'Please make sure an address for the weighted factory is provided'
  exit 1
fi

# Load stable start block
if [[ -z $STABLE_START_BLOCK ]]; then
  STABLE_START_BLOCK_VAR=stable_start_block_$NETWORK
  STABLE_START_BLOCK=${!STABLE_START_BLOCK_VAR}
fi
if [[ -z $STABLE_START_BLOCK ]]; then
  STABLE_START_BLOCK=0
fi

# Try loading stable factory address if missing
if [[ -z $STABLE_FACTORY ]]; then
  STABLE_FACTORY_VAR=stable_factory_$NETWORK
  STABLE_FACTORY=${!STABLE_FACTORY_VAR}
fi

# Validate strategy address
if [[ -z $STABLE_FACTORY ]]; then
  echo 'Please make sure an address for the stable factory is provided'
  exit 1
fi

# Remove previous manifest if there is any
if [ -f subgraph.yaml ]; then
  echo 'Removing previous subgraph manifest...'
  rm subgraph.yaml
fi

# Build subgraph manifest for requested variables
echo "Preparing new subgraph manifest for Strategy address ${STRATEGY} and network ${NETWORK}"
cp subgraph.template.yaml subgraph.yaml
sed -i -e "s/{{network}}/${ENV}/g" subgraph.yaml
sed -i -e "s/{{weightedFactory}}/${WEIGHTED_FACTORY}/g" subgraph.yaml
sed -i -e "s/{{weightedStartBlock}}/${WEIGHTED_START_BLOCK}/g" subgraph.yaml
sed -i -e "s/{{stableFactory}}/${STABLE_FACTORY}/g" subgraph.yaml
sed -i -e "s/{{stableStartBlock}}/${STABLE_START_BLOCK}/g" subgraph.yaml
rm -f subgraph.yaml-e

# Run codegen and build
rm -rf ./types && yarn graph codegen -o types
yarn graph build
