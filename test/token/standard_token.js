const assert = require('chai').assert;
const web3 = global.web3;

const StandardTokenMock = artifacts.require('./mock/StandardTokenMock.sol');
const ERC223ReceiverMock = artifacts.require('./mock/ERC223ReceiverMock.sol');
const NonReceiverMock = artifacts.require('./mock/NonReceiverMock.sol');
const BlockHeightManager = require('../util/block_height_manager');
const SolAssert = require('../util/sol_assert');

contract('StandardToken', (accounts) => {
  const blockHeightManager = new BlockHeightManager(web3);
  const OWNER = accounts[0];
  const ACCT1 = accounts[1];
  const ACCT2 = accounts[2];
  const ACCT3 = accounts[3];
  const tokenParams = {
    _initialAccount: OWNER,
    _initialBalance: 10000000,
  };

  let token;
  let erc223Receiver;
  let nonReceiver;

  beforeEach(blockHeightManager.snapshot);
  afterEach(blockHeightManager.revert);

  beforeEach(async () => {
    token = await StandardTokenMock.new(...Object.values(tokenParams), { from: OWNER });
    erc223Receiver = await ERC223ReceiverMock.new({ from: OWNER });
    nonReceiver = await NonReceiverMock.new({ from: OWNER });
  });

  describe('constructor', async () => {
    it('should initialize all the values correctly', async () => {
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), tokenParams._initialBalance);
      assert.equal(await token.totalSupply.call(), tokenParams._initialBalance);
    });
  });

  describe('transferERC223', () => {
    it('transfers the token to a wallet address', async () => {
      let ownerBalance = tokenParams._initialBalance;
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from OWNER to accounts[1]
      const acct1TransferAmt = 300000;
      await token.transfer(ACCT1, acct1TransferAmt, { from: OWNER });
      assert.equal(await token.balanceOf(ACCT1), acct1TransferAmt);

      ownerBalance -= acct1TransferAmt;
      assert.equal(await token.balanceOf(OWNER), ownerBalance);

      // transfer from OWNER to accounts[2]
      const acct2TransferAmt = 250000;
      await token.transfer(ACCT2, acct2TransferAmt, { from: OWNER });
      assert.equal(await token.balanceOf(ACCT2), acct2TransferAmt);

      ownerBalance -= acct2TransferAmt;
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from accounts[2] to accounts[3]
      await token.transfer(ACCT3, acct2TransferAmt, { from: ACCT2 });
      assert.equal(await token.balanceOf(ACCT3), acct2TransferAmt);
      assert.equal(await token.balanceOf(ACCT2), 0);
    });

    it('transfers the token to ERC223 contract and calls tokenFallback', async () => {
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), tokenParams._initialBalance);
      assert.isFalse(await erc223Receiver.tokenFallbackExec.call());

      const transferAmt = 1234567;
      await token.transfer(erc223Receiver.address, transferAmt, undefined, { from: OWNER });

      assert.equal(await token.balanceOf(OWNER), tokenParams._initialBalance - transferAmt);
      assert.equal(await token.balanceOf(erc223Receiver.address), transferAmt);
      assert.isTrue(await erc223Receiver.tokenFallbackExec.call());
    });

    it('throws when sending to a non-ERC223 contract that didnt implement the tokenFallback', async () => {
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), tokenParams._initialBalance);
      assert.isFalse(await erc223Receiver.tokenFallbackExec.call());

      const transferAmt = 1234567;
      try {
        await token.transfer(nonReceiver.address, transferAmt, undefined, { from: OWNER });
      } catch (e) {
        SolAssert.assertRevert(e);
      }

      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), tokenParams._initialBalance);
      assert.equal(await token.balanceOf(nonReceiver.address), 0);
      assert.isFalse(await erc223Receiver.tokenFallbackExec.call());
    });

    it('throws if the to address is not valid', async () => {
      try {
        await token.transfer(0, 1000, undefined, { from: OWNER });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });

    it('throws if the balance of the transferer is less than the amount', async () => {
      assert.equal(await token.balanceOf(OWNER), tokenParams._initialBalance);
      try {
        await token.transfer(ACCT1, tokenParams._initialBalance + 1, undefined, { from: OWNER });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }

      try {
        await token.transfer(ACCT3, 1, undefined, { from: ACCT2 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });
  });

  describe('transferERC20', async () => {
    it('should allow transfers if the account has tokens', async () => {
      let ownerBalance = tokenParams._initialBalance;
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from OWNER to accounts[1]
      const acct1TransferAmt = 300000;
      await token.transfer(ACCT1, acct1TransferAmt, { from: OWNER });
      assert.equal(await token.balanceOf(ACCT1), acct1TransferAmt);

      ownerBalance -= acct1TransferAmt;
      assert.equal(await token.balanceOf(OWNER), ownerBalance);

      // transfer from OWNER to accounts[2]
      const acct2TransferAmt = 250000;
      await token.transfer(ACCT2, acct2TransferAmt, { from: OWNER });
      assert.equal(await token.balanceOf(ACCT2), acct2TransferAmt);

      ownerBalance -= acct2TransferAmt;
      assert.equal(await token.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from accounts[2] to accounts[3]
      await token.transfer(ACCT3, acct2TransferAmt, { from: ACCT2 });
      assert.equal(await token.balanceOf(ACCT3), acct2TransferAmt);
      assert.equal(await token.balanceOf(ACCT2), 0);
    });

    it('should throw if the to address is not valid', async () => {
      try {
        await token.transfer(0, 1000, { from: OWNER });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });

    it('should throw if the balance of the transferer is less than the amount', async () => {
      assert.equal(await token.balanceOf(OWNER), tokenParams._initialBalance);
      try {
        await token.transfer(ACCT1, tokenParams._initialBalance + 1, { from: OWNER });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }

      try {
        await token.transfer(ACCT3, 1, { from: ACCT2 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });
  });

  describe('approve', async () => {
    it('should allow approving', async () => {
      const acct1Allowance = 1000;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      const acct2Allowance = 3000;
      await token.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT2), acct2Allowance);
    });

    it('should throw if the value is not 0 and has previous approval', async () => {
      const acct1Allowance = 1000;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await token.approve(ACCT1, 123, { from: OWNER });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });
  });

  describe('transferFrom', async () => {
    it('should allow transferring the allowed amount', async () => {
      let ownerBalance = tokenParams._initialBalance;

      // transfers from OWNER to accounts[1]
      const acct1Allowance = 1000;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      await token.transferFrom(OWNER, ACCT1, acct1Allowance, { from: ACCT1 });
      assert.equal(await token.balanceOf(ACCT1), acct1Allowance);

      ownerBalance -= acct1Allowance;
      assert.equal(await token.balanceOf(OWNER), ownerBalance);

      // transfers from OWNER to accounts[2]
      const acct2Allowance = 3000;
      await token.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT2), acct2Allowance);

      await token.transferFrom(OWNER, ACCT2, acct2Allowance, { from: ACCT2 });
      assert.equal(await token.balanceOf(ACCT2), acct2Allowance);

      ownerBalance -= acct2Allowance;
      assert.equal(await token.balanceOf(OWNER), ownerBalance);

      // transfers from accounts[2] to accounts[3]
      const acct3Allowance = 3000;
      await token.approve(ACCT3, acct3Allowance, { from: ACCT2 });
      assert.equal(await token.allowance(ACCT2, ACCT3), acct3Allowance);

      await token.transferFrom(ACCT2, ACCT3, acct3Allowance, { from: ACCT3 });
      assert.equal(await token.balanceOf(ACCT3), acct3Allowance);
      assert.equal(await token.balanceOf(ACCT2), 0);
    });

    it('should throw if the to address is not valid', async () => {
      try {
        await token.transferFrom(OWNER, 0, 1000, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });

    it('should throw if the from balance is less than the transferring amount', async () => {
      const acct1Allowance = tokenParams._initialBalance + 1;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await token.transferFrom(OWNER, ACCT1, acct1Allowance, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });

    it('should throw if the value is more than the allowed amount', async () => {
      const acct1Allowance = 1000;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await token.transferFrom(OWNER, ACCT1, acct1Allowance + 1, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });
  });

  describe('balanceOf', async () => {
    it('should return the right balance', async () => {
      assert.equal(await token.balanceOf(OWNER), tokenParams._initialBalance);
      assert.equal(await token.balanceOf(ACCT1), 0);
      assert.equal(await token.balanceOf(ACCT2), 0);
    });
  });

  describe('allowance', async () => {
    it('should return the right allowance', async () => {
      const acct1Allowance = 1000;
      await token.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT1), acct1Allowance);

      const acct2Allowance = 3000;
      await token.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await token.allowance(OWNER, ACCT2), acct2Allowance);

      assert.equal(await token.allowance(OWNER, ACCT3), 0);
    });
  });
});
