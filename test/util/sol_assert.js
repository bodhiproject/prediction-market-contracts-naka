const chai = require('chai');

const web3 = global.web3;
const { assert } = chai;

module.exports = {
  assertRevert(error) {
    assert.isAbove(error.message.search('revert'), -1, 'Revert error must be returned');
  },
  assertInvalidOpcode(error) {
    assert.isAbove(error.message.search('invalid opcode'), -1, 'Invalid opcode error must be returned');
  },
  assertBNEqual(first, second) {
    assert.equal(first.toString(), second.toString());
  },
  assertBNNotEqual(first, second) {
    assert.notEqual(first.toString(), second.toString());
  },
  bytesStrEqual(bytesString, string) {
    assert.equal(web3.toUtf8(bytesString), string);
  },
  assertEvent(tx, eventName) {
    const found = tx.logs.find((log) => {
      return log.event === eventName;
    })
    assert.isDefined(found, `Event ${eventName} not emitted`);
  }
};
