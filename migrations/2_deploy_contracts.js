const BodhiEthereum = artifacts.require("./token/BodhiEthereum.sol");
const AddressManager = artifacts.require("./storage/AddressManager.sol");
const EventFactory = artifacts.require("./event/EventFactory.sol");
const OracleFactory = artifacts.require("./oracle/OracleFactory.sol");

let addressManager;

module.exports = async (deployer) => {
  deployer.deploy(AddressManager).then((addrMgr) => {
    addressManager = addrMgr;
    addressManager.setBodhiTokenAddress('0x970e035e2a013cf4becd67e300d65bc32a56d826');
    return deployer.deploy(EventFactory, AddressManager.address);
  }).then((evtFactory) => {
    addressManager.setEventFactoryAddress(EventFactory.address);
    return deployer.deploy(OracleFactory, AddressManager.address);
  }).then((orcFactory) => {
    addressManager.setOracleFactoryAddress(OracleFactory.address);
    return;
  }).catch((err) => {
    throw err;
  });
};
