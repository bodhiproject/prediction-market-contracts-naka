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
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};
