const BodhiToken = artifacts.require("./tokens/BodhiToken.sol");
const SafeMath = artifacts.require("./libs/SafeMath.sol");

module.exports = function(deployer) {
    deployer.deploy(BodhiToken);
};
