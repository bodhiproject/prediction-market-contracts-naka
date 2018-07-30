const AddressManager = artifacts.require('./storage/AddressManager.sol');
const BodhiEthereum = artifacts.require('./token/BodhiEthereum.sol');
const EventFactory = artifacts.require('./event/EventFactory.sol');
const OracleFactory = artifacts.require('./oracle/OracleFactory.sol');

const Utils = require('.');

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
};
