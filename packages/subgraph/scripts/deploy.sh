#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

# Run graph build
yarn build:$NETWORK

# Select IPFS and The Graph nodes
if [[ "$NETWORK" = "localhost" ]]; then
  IPFS_NODE="http://localhost:5001"
  GRAPH_NODE="http://127.0.0.1:8020"
else
  # Require $GRAPHKEY to be set
  if [[ -z "${GRAPHKEY}" ]]; then
    echo "Please set \$GRAPHKEY to your The Graph deploy key to run this command."
    exit 1
  fi

  IPFS_NODE="https://api.thegraph.com/ipfs/"
  GRAPH_NODE="https://api.thegraph.com/deploy/"
fi

# Create subgraph if missing
{
  graph create mimic-fi/${NETWORK} --node ${GRAPH_NODE}
} || {
  echo 'Subgraph was already created'
}

# Deploy subgraph
graph deploy mimic-fi/${NETWORK} \
  --ipfs ${IPFS_NODE} \
  --node ${GRAPH_NODE} \
  --access-token "$GRAPHKEY"
