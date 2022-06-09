#!/bin/sh
MAINNET_URL="$1"
POLYGON_URL="$2"

cp ./scripts/networks.template.json ./scripts/networks.mimic.json

sed -i -e "s/{{mainnet}}/${MAINNET_URL}/g" ./scripts/networks.mimic.json
sed -i -e "s/{{polygon}}/${POLYGON_URL}/g" ./scripts/networks.mimic.json

cp ./scripts/networks.mimic.json $HOME/.hardhat/networks.mimic.json
