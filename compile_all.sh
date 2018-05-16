#!/bin/bash

echo 'Compiling BodhiEthereum.sol into /build'
solc ..=.. --optimize --bin --abi --hashes --allow-paths contracts/lib,contracts/token -o build/contracts --overwrite contracts/token/BodhiEthereum.sol
