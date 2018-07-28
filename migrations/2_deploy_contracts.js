const BodhiEthereum = artifacts.require("./token/BodhiEthereum.sol");
const AddressManager = artifacts.require("./storage/AddressManager.sol");
const EventFactory = artifacts.require("./event/EventFactory.sol");
const OracleFactory = artifacts.require("./oracle/OracleFactory.sol");

let addressManager;

module.exports = async (deployer) => {
  deployer.deploy(AddressManager).then((addrMgr) => {
    addressManager = addrMgr;
    return deployer.deploy(BodhiEthereum);
  }).then((bodhiEth) => {
    console.log('     addressManager.setBodhiTokenAddress:');
    addressManager.setBodhiTokenAddress(BodhiEthereum.address);
    return deployer.deploy(EventFactory, AddressManager.address);
  }).then((evtFactory) => {
    console.log('    addressManager.setEventFactoryAddress:');
    addressManager.setEventFactoryAddress(EventFactory.address);
    return deployer.deploy(OracleFactory, AddressManager.address);
  }).then((orcFactory) => {
    console.log('    addressManager.setOracleFactoryAddress:');
    addressManager.setOracleFactoryAddress(OracleFactory.address);
    return;
  }).catch((err) => {
    throw err;
  });
};
