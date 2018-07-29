const Web3Beta = require('web3');
const web3 = new Web3Beta(global.web3.currentProvider);
const chai = require('chai');

const StandardEvent = artifacts.require('./event/StandardEvent.sol');
const BlockHeightManager = require('../util/block_height_manager');
const ContractHelper = require('../util/contract_helper');
const SolAssert = require('../util/sol_assert');
const Abi = require('../util/abi');
const Utils = require('../util/');

const { assert } = chai;

const getEventParams = (oracle) => {
  const currTime = Utils.getCurrentBlockTime();
  return {
    _oracle: oracle,
    _name: ['Will Apple stock reach $300 by t', 'he end of 2017?'],
    _resultNames: ['A', 'B', 'C'],
    _bettingStartTime: currTime + 1000,
    _bettingEndTime: currTime + 3000,
    _resultSettingStartTime: currTime + 4000,
    _resultSettingEndTime: currTime + 6000,
  };
};

contract('StandardToken', (accounts) => {
  const blockHeightManager = new BlockHeightManager(web3);
  const OWNER = accounts[0];
  const ACCT1 = accounts[1];
  const ACCT2 = accounts[2];
  const ACCT3 = accounts[3];

  let token;
  let event;

  beforeEach(blockHeightManager.snapshot);
  afterEach(blockHeightManager.revert);

  beforeEach(async () => {
    const baseContracts = await ContractHelper.initBaseContracts(OWNER, accounts);
    token = baseContracts.bodhiToken;
    const eventFactory = baseContracts.eventFactory;

    const tx = await eventFactory.createStandardEvent(...Object.values(getEventParams(OWNER)), { from: OWNER });
    SolAssert.assertEvent(tx, 'StandardEventCreated');
    event = await StandardEvent.at(tx.logs[0].args._eventAddress);
  });

  describe.only('tokenFallback()', () => {
    it('calls setResult correctly', async () => {
      const tx = await token.transfer(event.address, Utils.getBigNumberWithDecimals(100, 8), { from: OWNER });
      
      // const contract = new web3.eth.Contract(Abi.BodhiEthereum, token.address);
      // const tx = contract.methods["transfer(address,uint256)"](
      //   event.address,
      //   Utils.getBigNumberWithDecimals(100, 8),
      // );
      // await tx.send({ from: OWNER });

      // const contract = new web3.eth.Contract(Abi.BodhiEthereum, token.address);
      // const tx = contract.methods["transfer(address,uint256,bytes)"](
      //   event.address,
      //   Utils.getBigNumberWithDecimals(100, 8),
      //   '0x65f4ced18151550e91447748765e2eb05397fb5279ba532b6B36FDf89D706035DC97B6Aa4bC84b2418A452f103'
      // );
      // await tx.send({ from: OWNER });
    });
  });
});
