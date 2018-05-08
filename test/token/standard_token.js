const assert = require('chai').assert;
const web3 = global.web3;

const StandardTokenMock = artifacts.require('./mock/StandardTokenMock.sol');
const ERC223ReceiverMock = artifacts.require('./mock/ERC223ReceiverMock.sol');
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

  let instance;
  let erc223Receiver;

  beforeEach(blockHeightManager.snapshot);
  afterEach(blockHeightManager.revert);

  beforeEach(async () => {
    instance = await StandardTokenMock.new(...Object.values(tokenParams), { from: OWNER });
    erc223Receiver = await ERC223ReceiverMock.new({ from: OWNER });
  });

  describe('constructor', async () => {
    it('should initialize all the values correctly', async () => {
      assert.equal(await instance.balanceOf(OWNER, { from: OWNER }), tokenParams._initialBalance);
      assert.equal(await instance.totalSupply.call(), tokenParams._initialBalance);
    });
  });

  describe.only('transferERC223', () => {
    it('should transfer the token and call tokenFallback', async () => {
      let ownerBalance = tokenParams._initialBalance;
      assert.equal(await instance.balanceOf(OWNER, { from: OWNER }), ownerBalance);
      assert.isFalse(await erc223Receiver.tokenFallbackExec.call());

      const transferAmt = 1234567;
      await instance.transfer(erc223Receiver.address, transferAmt, undefined, { from: OWNER });

      assert.equal(await instance.balanceOf(OWNER), ownerBalance - transferAmt);
      assert.equal(await instance.balanceOf(erc223Receiver.address), transferAmt);
      assert.isTrue(await erc223Receiver.tokenFallbackExec.call());
    });
  });

  describe('transferERC20', async () => {
    it('should allow transfers if the account has tokens', async () => {
      let ownerBalance = tokenParams._initialBalance;
      assert.equal(await instance.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from OWNER to accounts[1]
      const acct1TransferAmt = 300000;
      await instance.transfer(ACCT1, acct1TransferAmt, { from: OWNER });
      assert.equal(await instance.balanceOf(ACCT1), acct1TransferAmt);

      ownerBalance -= acct1TransferAmt;
      assert.equal(await instance.balanceOf(OWNER), ownerBalance);

      // transfer from OWNER to accounts[2]
      const acct2TransferAmt = 250000;
      await instance.transfer(ACCT2, acct2TransferAmt, { from: OWNER });
      assert.equal(await instance.balanceOf(ACCT2), acct2TransferAmt);

      ownerBalance -= acct2TransferAmt;
      assert.equal(await instance.balanceOf(OWNER, { from: OWNER }), ownerBalance);

      // transfer from accounts[2] to accounts[3]
      await instance.transfer(ACCT3, acct2TransferAmt, { from: ACCT2 });
      assert.equal(await instance.balanceOf(ACCT3), acct2TransferAmt);
      assert.equal(await instance.balanceOf(ACCT2), 0);
    });

    it('should throw if the to address is not valid', async () => {
      try {
        await instance.transfer(0, 1000, { from: OWNER });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });

    it('should throw if the balance of the transferer is less than the amount', async () => {
      assert.equal(await instance.balanceOf(OWNER), tokenParams._initialBalance);
      try {
        await instance.transfer(ACCT1, tokenParams._initialBalance + 1, { from: OWNER });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }

      try {
        await instance.transfer(ACCT3, 1, { from: ACCT2 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });
  });

  describe('approve', async () => {
    it('should allow approving', async () => {
      const acct1Allowance = 1000;
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      const acct2Allowance = 3000;
      await instance.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT2), acct2Allowance);
    });

    it('should throw if the value is not 0 and has previous approval', async () => {
      const acct1Allowance = 1000;
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await instance.approve(ACCT1, 123, { from: OWNER });
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
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      await instance.transferFrom(OWNER, ACCT1, acct1Allowance, { from: ACCT1 });
      assert.equal(await instance.balanceOf(ACCT1), acct1Allowance);

      ownerBalance -= acct1Allowance;
      assert.equal(await instance.balanceOf(OWNER), ownerBalance);

      // transfers from OWNER to accounts[2]
      const acct2Allowance = 3000;
      await instance.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT2), acct2Allowance);

      await instance.transferFrom(OWNER, ACCT2, acct2Allowance, { from: ACCT2 });
      assert.equal(await instance.balanceOf(ACCT2), acct2Allowance);

      ownerBalance -= acct2Allowance;
      assert.equal(await instance.balanceOf(OWNER), ownerBalance);

      // transfers from accounts[2] to accounts[3]
      const acct3Allowance = 3000;
      await instance.approve(ACCT3, acct3Allowance, { from: ACCT2 });
      assert.equal(await instance.allowance(ACCT2, ACCT3), acct3Allowance);

      await instance.transferFrom(ACCT2, ACCT3, acct3Allowance, { from: ACCT3 });
      assert.equal(await instance.balanceOf(ACCT3), acct3Allowance);
      assert.equal(await instance.balanceOf(ACCT2), 0);
    });

    it('should throw if the to address is not valid', async () => {
      try {
        await instance.transferFrom(OWNER, 0, 1000, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertRevert(e);
      }
    });

    it('should throw if the from balance is less than the transferring amount', async () => {
      const acct1Allowance = tokenParams._initialBalance + 1;
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await instance.transferFrom(OWNER, ACCT1, acct1Allowance, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });

    it('should throw if the value is more than the allowed amount', async () => {
      const acct1Allowance = 1000;
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      try {
        await instance.transferFrom(OWNER, ACCT1, acct1Allowance + 1, { from: ACCT1 });
      } catch (e) {
        SolAssert.assertInvalidOpcode(e);
      }
    });
  });

  describe('balanceOf', async () => {
    it('should return the right balance', async () => {
      assert.equal(await instance.balanceOf(OWNER), tokenParams._initialBalance);
      assert.equal(await instance.balanceOf(ACCT1), 0);
      assert.equal(await instance.balanceOf(ACCT2), 0);
    });
  });

  describe('allowance', async () => {
    it('should return the right allowance', async () => {
      const acct1Allowance = 1000;
      await instance.approve(ACCT1, acct1Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT1), acct1Allowance);

      const acct2Allowance = 3000;
      await instance.approve(ACCT2, acct2Allowance, { from: OWNER });
      assert.equal(await instance.allowance(OWNER, ACCT2), acct2Allowance);

      assert.equal(await instance.allowance(OWNER, ACCT3), 0);
    });
  });
});
