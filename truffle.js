require('dotenv').config();
const Web3 = require('web3');
const WalletProvider = require('truffle-wallet-provider');
const Wallet = require('ethereumjs-wallet');

const web3 = new Web3();

// See <http://truffleframework.com/docs/advanced/configuration>
// to customize your Truffle configuration!
const config = {
  networks: {
    localhost: {
      host: "localhost", 
      port: 8546,
      network_id: "*",
    },
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};

/*
* Add mainnet/testnet configs if a private key is supplied in .env
* 1. Create .env file locally in the directory root
* 2. Add private key of the address you will use
* 3. Reference the .env key here
*/
if (process.env.hasOwnProperty('MEW_PRIV_KEY')) {
  const privKey = new Buffer(process.env['MEW_PRIV_KEY'], 'hex');
  const wallet = Wallet.fromPrivateKey(privKey);

  // Add Ropsten testnet config
  config.networks.ropsten = {
    network_id: 3,
    provider: new WalletProvider(wallet, "https://ropsten.infura.io/jf36VtmNV1eWuSHOMvMT"),
    gas: 4600000,
    gasPrice: web3.toWei("20", "gwei"),
  };

  // Add mainnet config
  config.networks.mainnet = {
    network_id: 1,
    provider: new WalletProvider(wallet, "https://mainnet.infura.io/jf36VtmNV1eWuSHOMvMT"),
    gas: 4600000,
    gasPrice: web3.toWei("20", "gwei"),
  };
}

module.exports = config;
