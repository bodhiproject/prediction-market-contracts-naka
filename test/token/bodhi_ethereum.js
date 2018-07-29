const assert = require('chai').assert;

const BodhiEthereum = artifacts.require('./token/BodhiEthereum.sol');
const BlockHeightManager = require('../util/block_height_manager');
const Utils = require('../util/');
const SolAssert = require('../util/sol_assert');

contract('BodhiEthereum', (accounts) => {
  const blockHeightManager = new BlockHeightManager(web3);
  const OWNER = accounts[0];

  let token;
  let decimals;

  before(blockHeightManager.snapshot);
  afterEach(blockHeightManager.revert);

  beforeEach(async () => {
    token = await BodhiEthereum.deployed({ from: OWNER });
    decimals = await token.decimals.call();
  });

  describe('constructor', async () => {
    it('initializes all the values', async () => {
      assert.equal(await token.owner.call(), OWNER);

      const tokenTotalSupply = await token.tokenTotalSupply.call();
      const expectedTokenTotalSupply = Utils.getBigNumberWithDecimals(100e6, decimals);
      assert.equal(tokenTotalSupply.toString(), expectedTokenTotalSupply.toString());
    });
  });

  describe('mint', () => {
    it('allows the owner to mint tokens', async () => {
      assert.equal((await token.totalSupply.call()).toString(), 0);

      const mintAmt = 12345678;
      await token.mint(OWNER, mintAmt, { from: OWNER });
      assert.equal((await token.totalSupply.call()).toString(), mintAmt.toString());
    });

    it('does not allow a non-owner to mint tokens', async () => {
      assert.equal((await token.totalSupply.call()).toString(), 0);

      try {
        await token.mint(accounts[1], 1, { from: accounts[1] });
        assert.fail();
      } catch (e) {
        SolAssert.assertRevert(e);
      }

      try {
        await token.mint(accounts[2], 1, { from: accounts[2] });
        assert.fail();
      } catch (e) {
        SolAssert.assertRevert(e);
      }

      assert.equal((await token.totalSupply.call()).toString(), 0);
    });

    it('throws if trying to mint more than the tokenTotalSupply', async () => {
      assert.equal(await token.totalSupply.call(), 0);

      const tokenTotalSupply = await token.tokenTotalSupply.call();
      await token.mint(OWNER, tokenTotalSupply, { from: OWNER });
      assert.equal((await token.totalSupply.call()).toString(), tokenTotalSupply.toString());

      try {
        await token.mint(OWNER, 1, { from: OWNER });
        assert.fail();
      } catch (e) {
        SolAssert.assertRevert(e);
      }

      totalSupply = await token.totalSupply.call();
      assert.equal(totalSupply.toString(), tokenTotalSupply.toString());
    });
  });
});
