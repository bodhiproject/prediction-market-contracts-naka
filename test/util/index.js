const { find, each, isPlainObject, isArray, isString } = require('lodash')

const web3 = global.web3

module.exports = class Utils {
  static addHexPrefix(str) {
    if (!isString(str)) return str
    if (!str.startsWith('0x')) return `0x${str}`
    return str
  }

  static removeHexPrefix(str) {
    if (!isString(str)) return str
    if (str.startsWith('0x')) return str.substr(2)
    return str
  }

  /*
  * Converts the amount to a lower denomination as a BigNumber.
  * eg. (number: 1, decimals: 4) = 10000
  * @param number {BigNumber|number|string} The number to convert.
  * @param decimals {number} The denomination number of decimals to convert to.
  * @retun {BigNumber} The converted BigNumber.
  */
  static toDenomination(number, decimals = 0) {
    const bn = web3.utils.toBN(number)
    const decimalsBn = web3.utils.toBN(10 ** decimals)
    return bn.mul(decimalsBn)
  }

  /*
  * Truncates the decimals off the BigNumber and returns a new BigNumber.
  * @param number {BigNumber} The number to truncate.
  * @retun {BigNumber} The truncated BigNumber.
  */
  static bigNumberFloor(bigNumber) {
    return web3.toBigNumber(bigNumber.toString().split('.')[0])
  }

  /*
  * Returns the original value increased by a percentage.
  * @param bigNumber {BigNumber} The BigNumber to increase.
  * @param percentage {BigNumber} The percent amount to increase the number by.
  * @retun {BigNumber} The increased BigNumber by the percentage.
  */
  static percentIncrease(bigNumber, percentage) {
    return bigNumber.times(web3.toBigNumber(percentage)).div(web3.toBigNumber(100)).plus(bigNumber)
  }

  // Gets the unix time in seconds of the current block
  static async currentBlockTime() {
    const blockNum = await web3.eth.getBlockNumber()
    const block = await web3.eth.getBlock(blockNum)
    return block.timestamp
  }

  /*
  * Removes the padded zeros in an address hex string.
  * eg. 0x0000000000000000000000006b36fdf89d706035dc97b6aa4bc84b2418a452f1 -> 0x6b36fdf89d706035dc97b6aa4bc84b2418a452f1
  * @param hexString {string} The hex string to remove the padding from.
  * @return {string} The hex string with the padded zeros removed.
  */
  static paddedHexToAddress(hexString) {
    const regex = new RegExp(/(0x)(0+)([a-fA-F0-9]{40})/)
    const matches = regex.exec(hexString)
    return matches && matches[1] + matches[3]
  }

  static constructTransfer223Data(funcSig, types, params) {
    const encoded = Utils.removeHexPrefix(web3.eth.abi.encodeParameters(types, params))
    return Utils.addHexPrefix(`${funcSig}${encoded}`)
  }

  /**
   * Gets the object from the ABI given the name and type
   * @param {object} abi ABI to search in
   * @param {string} name Name of the function or event
   * @param {string} type One of: [function, event]
   * @return {object|undefined} Object found in ABI
   */
  static getAbiObject(abi, name, type) {
    if (!abi) return undefined;
    return find(abi, { name, type });
  }

  /**
   * Gets an event signature from the ABI given the name
   * @param {object} abi ABI to search in
   * @param {string} name Name of the function or event
   * @return {object|undefined} Object found in ABI
   */
  static getEventSig(abi, name) {
    const obj = Utils.getAbiObject(abi, name, 'event')
    return web3.eth.abi.encodeEventSignature(obj)
  }

  static decodeEvent(events, abi, name) {
    const obj = Utils.getAbiObject(abi, name, 'event')
    const eventSig = Utils.getEventSig(abi, name)
    const keys = Object.keys(events)

    // Checks object's topics for the matching event signature
    const decode = (event) => {
      if (isPlainObject(event) && event.raw.topics.includes(eventSig)) {
        return web3.eth.abi.decodeLog(
          obj.inputs,
          event.raw.data,
          event.raw.topics,
        )
      }
      return undefined
    }

    let decoded
    each(keys, (key) => {
      const event = events[key]

      // Try to decode if event is an object
      decoded = decode(event)
      if (decoded) return false

      // Otherwise loop through each sub-event
      if (isArray(event)) {
        each(event, (innerEvent) => {
          decoded = decode(innerEvent)
          if (decoded) return false
        })
      }
    })
    return decoded
  }
}
