const BodhiEthereum = artifacts.require("./token/BodhiEthereum.sol");
const AddressManager = artifacts.require("./storage/AddressManager.sol");
const EventFactory = artifacts.require("./event/EventFactory.sol");
const OracleFactory = artifacts.require("./oracle/OracleFactory.sol");

let addressManager;

module.exports = function(deployer) {
  deployer.deploy(AddressManager).then((instance) => addressManager = instance);
  deployer.deploy(BodhiEthereum).then(() => addressManager.setBodhiTokenAddress(BodhiEthereum.address));
  deployer.deploy(EventFactory, addressManager.address).then(() => {
    addressManager.setEventFactoryAddress(EventFactory.address)
  });
  deployer.deploy(OracleFactory, addressManager.address).then(() => {
    addressManager.setOracleFactoryAddress(OracleFactory.address)
  });
};
