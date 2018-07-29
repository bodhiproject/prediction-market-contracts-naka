const assert = require('chai').assert;

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
  assertEvent(tx, eventName) {
    const found = tx.logs.find((log) => {
      return log.event === eventName;
    })
    assert.isDefined(found, `Event ${eventName} not emitted`);
  }
};
