#!/bin/bash

echo 'Compiling BodhiEthereum.sol into /build'
solc ..=.. --optimize --bin --abi --hashes --allow-paths contracts/lib,contracts/token -o build/contracts --overwrite contracts/token/BodhiEthereum.sol

echo 'Compiling AddressManager.sol into /build'
solc ..=.. --optimize --bin --abi --hashes --allow-paths contracts/lib,contracts/storage -o build/contracts --overwrite contracts/storage/AddressManager.sol

echo 'Compiling EventFactory.sol into /build'
solc ..=.. --optimize --bin --abi --hashes --allow-paths contracts/storage,installed_contracts/bytes/contracts -o build/contracts --overwrite contracts/event/EventFactory.sol

echo 'Compiling OracleFactory.sol into /build'
solc ..=.. --optimize --bin --abi --hashes --allow-paths contracts/storage -o build/contracts --overwrite contracts/oracle/OracleFactory.sol
