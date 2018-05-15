require('dotenv').config();
const Web3 = require("web3");
const WalletProvider = require("truffle-wallet-provider");
const Wallet = require('ethereumjs-wallet');

const web3 = new Web3();
const mainnetPrivKey = new Buffer(process.env['MEW_MAINNET_KEY'], 'hex');
const mainnetWallet = Wallet.fromPrivateKey(mainnetPrivKey);
const mainnetProvider = new WalletProvider(mainnetWallet, "https://mainnet.infura.io/jf36VtmNV1eWuSHOMvMT");

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    localhost: {
      host: "localhost", 
      port: 8546,
      network_id: "*",
    },
    ropsten:  {
      host: "localhost",
      port: 8545,
      network_id: 3,
      from: "0xd5d087daabc73fc6cc5d9c1131b93acbd53a2428",
      gas: 4600000,
    },
    mainnet: {
      network_id: 1,
      provider: mainnetProvider,
      gas: 4600000,
      gasPrice: web3.toWei("20", "gwei"),
    },
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};
