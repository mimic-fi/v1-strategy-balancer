#!/bin/sh
MAINNET_URL="$1"
POLYGON_URL="$2"

set -o errexit

echo "
{
  \"networks\": {
    \"mainnet\": {
      \"url\": \"${MAINNET_URL}\"
    },
    \"polygon\": {
      \"url\": \"${POLYGON_URL}\"
    }
  }
}
" > $HOME/.hardhat/networks.mimic.json
