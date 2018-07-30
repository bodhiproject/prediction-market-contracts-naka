const web3 = global.web3;

module.exports = class Utils {
  // Converts the amount to a big number given the number of decimals
  static getBigNumberWithDecimals(amount, numOfDecimals) {
    return web3.toBigNumber(amount * (10 ** numOfDecimals));
  }

  // Gets the unix time in seconds of the current block
  static getCurrentBlockTime() {
    return web3.eth.getBlock(web3.eth.blockNumber).timestamp;
  }

  /*
  * Calculates the new big number after a percentage increase
  * @param amount {BN} The original number to increase.
  * @param percentIncrease {Number} The percentage to increase as a whole number.
  * @return {BN} The big number with percentage increase.
  */
  static getPercentageIncrease(amount, percentIncrease) {
    const increaseAmount = amount.mul(percentIncrease).div(100);
    return web3.toBigNumber(Math.floor(amount.add(increaseAmount)));
  }

  /*
  * Removes the padded zeros in a hex string.
  * eg. 0x0000000000000000000000006b36fdf89d706035dc97b6aa4bc84b2418a452f1 -> 0x6b36fdf89d706035dc97b6aa4bc84b2418a452f1
  * @param hexString {string} The hex string to remove the leading zeros.
  * @return {string} The hex string with the padded zeros removed.
  */
  static removePaddedZeros(hexString) {
    const regex = new RegExp(/(0x)(0+)([a-fA-F0-9]+)/);
    const matches = regex.exec(hexString);
    return matches && matches[1] + matches[3];
  }
};
