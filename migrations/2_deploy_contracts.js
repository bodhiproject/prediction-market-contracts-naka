const BodhiEthereum = artifacts.require("./token/BodhiEthereum.sol");

module.exports = function(deployer) {
  deployer.deploy(BodhiEthereum);
};
