const Web3Beta = require('web3');
const Qweb3Utils = require('qweb3').Utils;
const Encoder = require('qweb3').Encoder;

const AddressManager = artifacts.require('./storage/AddressManager.sol');
const BodhiEthereum = artifacts.require('./token/BodhiEthereum.sol');
const EventFactory = artifacts.require('./event/EventFactory.sol');
const OracleFactory = artifacts.require('./oracle/OracleFactory.sol');

const Utils = require('.');
const Abi = require('./abi');

const web3 = new Web3Beta(global.web3.currentProvider);

const BOT_DECIMALS = 8;
const BODHI_TOKENS_BALANCE = Utils.toDenomination(100000, BOT_DECIMALS);

module.exports = class ContractHelper {
  static async initBaseContracts(admin, accounts) {
    const addressManager = await AddressManager.deployed({ from: admin });

    const bodhiToken = await ContractHelper.mintBodhiTokens(admin, accounts);
    await addressManager.setBodhiTokenAddress(bodhiToken.address, { from: admin });
    assert.equal(await addressManager.bodhiTokenAddress.call(), bodhiToken.address);

    const eventFactory = await EventFactory.deployed(addressManager.address, { from: admin });
    await addressManager.setEventFactoryAddress(eventFactory.address, { from: admin });
    assert.equal(await addressManager.eventFactoryVersionToAddress.call(0), eventFactory.address);

    const oracleFactory = await OracleFactory.deployed(addressManager.address, { from: admin });
    await addressManager.setOracleFactoryAddress(oracleFactory.address, { from: admin });
    assert.equal(await addressManager.oracleFactoryVersionToAddress.call(0), oracleFactory.address);

    return {
      addressManager,
      bodhiToken,
      eventFactory,
      oracleFactory,
    };
  }

  static async mintBodhiTokens(admin, accounts) {
    const token = await BodhiEthereum.deployed({ from: admin });
    const expectedBalance = BODHI_TOKENS_BALANCE.toString();

    await token.mint(accounts[0], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[0])).toString(), expectedBalance);

    await token.mint(accounts[1], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[1])).toString(), expectedBalance);

    await token.mint(accounts[2], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[2])).toString(), expectedBalance);

    await token.mint(accounts[3], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[3])).toString(), expectedBalance);

    await token.mint(accounts[4], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[4])).toString(), expectedBalance);

    await token.mint(accounts[5], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[5])).toString(), expectedBalance);

    await token.mint(accounts[6], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[6])).toString(), expectedBalance);

    await token.mint(accounts[7], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[7])).toString(), expectedBalance);

    await token.mint(accounts[8], BODHI_TOKENS_BALANCE, { from: admin });
    assert.equal((await token.balanceOf(accounts[8])).toString(), expectedBalance);

    return token;
  }

  static async approve(tokenContract, sender, to, amount) {
    await tokenContract.approve(to, amount, { from: sender });
    assert.equal((await tokenContract.allowance(sender, to)).toString(), amount.toString());
  }

  static async transferSetResult(token, event, cOracle, resultSetter, resultIndex, amount) {
    const data = '0x65f4ced1'
      + Qweb3Utils.trimHexPrefix(cOracle.address)
      + Qweb3Utils.trimHexPrefix(resultSetter)
      + Encoder.uintToHex(resultIndex);

    const tokenWeb3Contract = new web3.eth.Contract(Abi.BodhiEthereum, token.address);
    return await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, amount, data)
      .send({ from: resultSetter, gas: 5000000 });
  }

  static async transferVote(token, event, dOracle, voter, resultIndex, amount) {
    const data = '0x6f02d1fb'
      + Qweb3Utils.trimHexPrefix(dOracle.address)
      + Qweb3Utils.trimHexPrefix(voter)
      + Encoder.uintToHex(resultIndex);

    const tokenWeb3Contract = new web3.eth.Contract(Abi.BodhiEthereum, token.address);
    return await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, amount, data)
      .send({ from: voter, gas: 5000000 });
  }
};
