#!/bin/sh
MAINNET_URL="$1"
POLYGON_URL="$2"

cp ./networks.template.json ./networks.mimic.json

sed -i -e "s/{{mainnet}}/${MAINNET_URL}/g" ./networks.mimic.json
sed -i -e "s/{{polygon}}/${POLYGON_URL}/g" ./networks.mimic.json

cp ./networks.mimic.json $HOME/.hardhat/networks.mimic.json
