const { find, each, isPlainObject, isArray, isString, isNumber } = require('lodash')

const web3 = global.web3
const { toBN, padRight } = web3.utils

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

  /**
   * Converts the amount to a lower denomination.
   * @param {number|string} amount Amount to convert
   * @param {number} decimals Number of decimals
   * @return {BN} Amount as BN.js instance
   */
  static toDenomination(amount, decimals = 0) {
    if (((isString(amount) && amount.includes('.'))
      || (isNumber(amount) && amount % 1 != 0))
      && decimals > 0) {
      const arr = amount.toString().split('.')
      const whole = arr[0]
      const dec = arr[1]

      const wholeBn = toBN(10 ** decimals).mul(toBN(whole))
      const decBn = toBN(padRight(dec, decimals))
      return wholeBn.add(decBn)
    }

    return toBN(10 ** decimals).mul(toBN(amount))
  }

  /**
   * Converts the amount to a lower denomination.
   * @param {number|string} amount Amount to convert
   * @return {BN} Amount as BN.js instance
   */
  static toSatoshi(amount) {
    return Utils.toDenomination(amount, 8)
  }

  // Gets the unix time in seconds of the current block
  static async currentBlockTime() {
    const blockNum = await web3.eth.getBlockNumber()
    const block = await web3.eth.getBlock(blockNum)
    return block.timestamp
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
