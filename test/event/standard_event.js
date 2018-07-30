const Web3Beta = require('web3');
const web3 = new Web3Beta(global.web3.currentProvider);
const chai = require('chai');
const { each } = require('lodash');
const Qweb3Utils = require('qweb3').Utils;
const Encoder = require('qweb3').Encoder;

const StandardEvent = artifacts.require('./event/StandardEvent.sol');
const CentralizedOracle = artifacts.require('./oracle/CentralizedOracle.sol');
const DecentralizedOracle = artifacts.require('./oracle/DecentralizedOracle.sol');
const ContractHelper = require('../util/contract_helper');
const SolAssert = require('../util/sol_assert');
const TimeMachine = require('../util/time_machine');
const Abi = require('../util/abi');
const { EventHash, EventStatus } = require('../util/constants');
const Utils = require('../util/');

const { assert } = chai;

const getEventParams = (oracle) => {
  const currTime = Utils.currentBlockTime();
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

contract('StandardEvent', (accounts) => {
  const timeMachine = new TimeMachine(web3);
  const OWNER = accounts[0];
  const ACCT1 = accounts[1];

  let tokenDecimals;
  let thresholdIncrease;
  let token;
  let tokenWeb3Contract;
  let eventParams;
  let event;
  let cOracle;

  beforeEach(async () => {
    await timeMachine.mine();
    await timeMachine.snapshot();

    const baseContracts = await ContractHelper.initBaseContracts(OWNER, accounts);

    token = baseContracts.bodhiToken;
    tokenWeb3Contract = new web3.eth.Contract(Abi.BodhiEthereum, token.address);
    
    const addressManager = baseContracts.addressManager;
    tokenDecimals = await addressManager.tokenDecimals.call();
    thresholdIncrease = await addressManager.thresholdPercentIncrease.call();
    
    const eventFactory = baseContracts.eventFactory;
    eventParams = getEventParams(OWNER);
    const tx = await eventFactory.createStandardEvent(...Object.values(eventParams), { from: OWNER });
    SolAssert.assertEvent(tx, 'StandardEventCreated');

    let eventAddress;
    let cOracleAddress;
    each(tx.receipt.logs, (log) => {
      if (log.topics[0] === EventHash.STANDARD_EVENT_CREATED) {
        eventAddress = Utils.paddedHexToAddress(log.topics[2]);
      } else if (log.topics[0] === EventHash.CENTRALIZED_ORACLE_CREATED) {
        cOracleAddress = Utils.paddedHexToAddress(log.topics[2]);
      }
    });

    event = await StandardEvent.at(eventAddress);
    assert.isDefined(event);

    cOracle = await CentralizedOracle.at(cOracleAddress);
    assert.isDefined(cOracle);
  });

  afterEach(async () => {
    await timeMachine.revert();
  });

  describe('tokenFallback()', () => {
    describe('setResult()', () => {
      let threshold;

      beforeEach(async () => {
        threshold = await cOracle.consensusThreshold.call();

        // Advance to result setting start time
        await timeMachine.increaseTime(eventParams._resultSettingStartTime - Utils.currentBlockTime());
        assert.isAtLeast(Utils.currentBlockTime(), eventParams._resultSettingStartTime);
        assert.isBelow(Utils.currentBlockTime(), eventParams._resultSettingEndTime);
      });

      it('calls setResult() correctly', async () => {
        // Call ERC223 transfer method
        const resultIndex = 3;
        const data = '0x65f4ced1'
          + Qweb3Utils.trimHexPrefix(cOracle.address)
          + Qweb3Utils.trimHexPrefix(OWNER)
          + Encoder.uintToHex(resultIndex);
        const tx = await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
          .send({ from: OWNER, gas: 5000000 });
        
        // Validate event
        assert.equal(await event.status.call(), EventStatus.ORACLE_VOTING);
        assert.equal(await event.resultIndex.call(), resultIndex);
        SolAssert.assertBNEqual((await event.getTotalVotes())[resultIndex], threshold);
        SolAssert.assertBNEqual((await event.getVoteBalances({ from: OWNER }))[resultIndex], threshold);
        SolAssert.assertBNEqual(await event.totalArbitrationTokens.call(), threshold);

        // Validate cOracle
        assert.isTrue(await cOracle.finished.call());
        assert.equal(await cOracle.resultIndex.call(), resultIndex);
        SolAssert.assertBNEqual((await cOracle.getTotalVotes())[resultIndex], threshold);
        SolAssert.assertBNEqual((await cOracle.getVoteBalances({ from: OWNER }))[resultIndex], threshold);

        // Validate dOracle created
        const dOracleAddress = Utils.paddedHexToAddress(tx.events['2'].raw.topics[2]);
        const dOracle = await DecentralizedOracle.at(dOracleAddress);
        assert.equal(await dOracle.eventAddress.call(), event.address);
        assert.equal(await dOracle.lastResultIndex.call(), resultIndex);
        SolAssert.assertBNEqual(await dOracle.consensusThreshold.call(),
          Utils.percentIncrease(threshold, thresholdIncrease));
      });

      it('throws if the data length is not 76 bytes', async () => {
        const resultIndex = 3;
        let data = '0x65f4ced1'
          + Qweb3Utils.trimHexPrefix(cOracle.address)
          + Qweb3Utils.trimHexPrefix(OWNER)
          + Encoder.uintToHex(resultIndex);
        assert.equal(data.length, 154);
        data = data.slice(0, 152);
        assert.equal(data.length, 152);

        try {
          await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
            .send({ from: OWNER, gas: 5000000 });
          assert.fail();
        } catch (e) {
          SolAssert.assertRevert(e);
        }
      });

      it('throws if the event status is not betting', async () => {
        // Call ERC223 transfer method
        let resultIndex = 3;
        let data = '0x65f4ced1'
          + Qweb3Utils.trimHexPrefix(cOracle.address)
          + Qweb3Utils.trimHexPrefix(OWNER)
          + Encoder.uintToHex(resultIndex);
        await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
          .send({ from: OWNER, gas: 5000000 });
        assert.equal(await event.status.call(), EventStatus.ORACLE_VOTING);

        // Try to set the result again
        try {
          await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
            .send({ from: OWNER, gas: 5000000 });
          assert.fail();
        } catch (e) {
          SolAssert.assertRevert(e);
        }
      });
    });

    describe('vote()', () => {
      let dOracle;

      beforeEach(async () => {
        const threshold = await cOracle.consensusThreshold.call();

        // Advance to result setting start time
        await timeMachine.increaseTime(eventParams._resultSettingStartTime - Utils.currentBlockTime());
        assert.isAtLeast(Utils.currentBlockTime(), eventParams._resultSettingStartTime);
        assert.isBelow(Utils.currentBlockTime(), eventParams._resultSettingEndTime);

        // Set the result
        const setResultIndex = 3;
        const data = '0x65f4ced1'
          + Qweb3Utils.trimHexPrefix(cOracle.address)
          + Qweb3Utils.trimHexPrefix(OWNER)
          + Encoder.uintToHex(setResultIndex);
        const tx = await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
          .send({ from: OWNER, gas: 5000000 });

        // Get dOracle
        const dOracleAddress = Utils.paddedHexToAddress(tx.events['2'].raw.topics[2]);
        dOracle = await DecentralizedOracle.at(dOracleAddress);
        assert.equal(await dOracle.lastResultIndex.call(), setResultIndex);
      });

      it('calls vote() correctly and sets the result when hitting the threshold', async () => {
        // Vote
        const threshold = await dOracle.consensusThreshold.call();
        const voteIndex = 1;
        const data = '0x6f02d1fb'
          + Qweb3Utils.trimHexPrefix(dOracle.address)
          + Qweb3Utils.trimHexPrefix(ACCT1)
          + Encoder.uintToHex(voteIndex);
        const tx = await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, threshold, data)
          .send({ from: ACCT1, gas: 5000000 });

        // Validate event
        assert.equal(await event.status.call(), EventStatus.ORACLE_VOTING);
        assert.equal(await event.resultIndex.call(), voteIndex);

        // Validate dOracle1
        SolAssert.assertBNEqual((await dOracle.getTotalVotes())[voteIndex], threshold);
        SolAssert.assertBNEqual((await dOracle.getVoteBalances({ from: ACCT1 }))[voteIndex], threshold);
        assert.isTrue(await dOracle.finished.call());
        assert.equal(await dOracle.resultIndex.call(), voteIndex);

        // Validate dOracle2
        const dOracle2Address = Utils.paddedHexToAddress(tx.events['2'].raw.topics[2]);
        const dOracle2 = await DecentralizedOracle.at(dOracle2Address);
        assert.equal(await dOracle2.lastResultIndex.call(), voteIndex);
        SolAssert.assertBNEqual(await dOracle2.consensusThreshold.call(),
          Utils.percentIncrease(threshold, thresholdIncrease));
      });

      it('throws if the data length is not 76 bytes', async () => {
        const voteAmount = Utils.toDenomination(50, tokenDecimals);
        const voteIndex = 1;
        let data = '0x6f02d1fb'
          + Qweb3Utils.trimHexPrefix(dOracle.address)
          + Qweb3Utils.trimHexPrefix(ACCT1)
          + Encoder.uintToHex(voteIndex);
        assert.equal(data.length, 154);
        data = data.slice(0, 152);
        assert.equal(data.length, 152);

        try {
          await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, voteAmount, data)
            .send({ from: ACCT1, gas: 5000000 });
          assert.fail();
        } catch (e) {
          SolAssert.assertRevert(e);
        }
      });
    });

    it('throws if trying to call an unhandled function', async () => {
      try {
        await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](
          event.address,
          Utils.toDenomination(1, tokenDecimals),
          '0xabcdef01'
        ).send({ from: OWNER, gas: 5000000 });
        assert.fail();
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });
  });
});
