const BodhiToken = artifacts.require("./token/BodhiToken.sol");

module.exports = function(deployer) {
  deployer.deploy(BodhiToken);
};
