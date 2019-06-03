const { assert } = require('chai')
const TimeMachine = require('sol-time-machine')
const sassert = require('sol-assert')
const getConstants = require('../constants')
const {
  toDenomination,
  bigNumberFloor,
  percentIncrease,
  currentBlockTime,
  paddedHexToAddress,
  constructTransfer223Data,
  decodeEvent,
} = require('../util')
const NRC223PreMinted = artifacts.require('NRC223PreMinted')
const ConfigManager = artifacts.require('ConfigManager')
const EventFactory = artifacts.require('EventFactory')
const MultipleResultsEvent = artifacts.require('MultipleResultsEvent')

const web3 = global.web3

const CREATE_EVENT_FUNC_SIG = '662edd20'
const BET_FUNC_SIG = '885ab66d'
const SET_RESULT_FUNC_SIG = 'a6b4218b'
const RESULT_INVALID = 'Invalid'
const TOKEN_DECIMALS = 8

const fundUsers = async ({ nbotMethods, accounts }) => {
  await nbotMethods.transfer(accounts[1], toDenomination(10000, TOKEN_DECIMALS))
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[2], toDenomination(10000, TOKEN_DECIMALS))
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[3], toDenomination(10000, TOKEN_DECIMALS))
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[4], toDenomination(10000, TOKEN_DECIMALS))
    .send({ from: accounts[0] })
}

const getEventParams = async (cOracle) => {
  const currTime = await currentBlockTime()
  return [
    'Test Event 1',
    [
      web3.utils.fromAscii('A'),
      web3.utils.fromAscii('B'),
      web3.utils.fromAscii('C'),
    ],
    `${currTime + 1000}`,
    `${currTime + 3000}`,
    `${currTime + 4000}`,
    `${currTime + 6000}`,
    cOracle,
    0,
    10,
  ]
}

const createEvent = async (
  { nbotMethods, eventParams, eventFactoryAddr, escrowAmt, from, gas }
) => {
  try {
    // Construct data
    const data = constructTransfer223Data(
      CREATE_EVENT_FUNC_SIG,
      ['string', 'bytes32[3]', 'uint256', 'uint256', 'uint256', 'uint256', 
        'address', 'uint8', 'uint256'],
      eventParams,
    )

    // Send tx
    const receipt = await nbotMethods['transfer(address,uint256,bytes)'](
      eventFactoryAddr,
      escrowAmt,
      data,
    ).send({ from, gas })
  
    // Parse event log and instantiate event instance
    const decoded = decodeEvent(
      receipt.events,
      EventFactory._json.abi,
      'MultipleResultsEventCreated'
    )
    // TODO: web3.eth.abi.decodeLog is parsing the logs backwards so it should
    // using eventAddress instead of ownerAddress
    return decoded.ownerAddress
  } catch (err) {
    throw err
  }
}

const placeBet = async (
  { nbotMethods, eventAddr, amtDecimals, resultIndex, from }
) => {
  const amt = toDenomination(amtDecimals, TOKEN_DECIMALS)
  const data = constructTransfer223Data(BET_FUNC_SIG, ['uint8'], [resultIndex])
  await nbotMethods['transfer(address,uint256,bytes)'](
    eventAddr,
    amt,
    web3.utils.hexToBytes(data),
  ).send({ from, gas: 200000 })
}

const setResult = async (
  { nbotMethods, eventAddr, amt, resultIndex, from }
) => {
  const data = constructTransfer223Data(
    SET_RESULT_FUNC_SIG,
    ['uint8'],
    [resultIndex]
  )
  await nbotMethods['transfer(address,uint256,bytes)'](
    eventAddr,
    amt,
    web3.utils.hexToBytes(data),
  ).send({ from, gas: 400000 })
}

contract('MultipleResultsEvent', (accounts) => {
  const {
    OWNER,
    ACCT1,
    ACCT2,
    ACCT3,
    ACCT4,
    INVALID_ADDR,
    MAX_GAS,
  } = getConstants(accounts)
  const timeMachine = new TimeMachine(web3)

  let nbot
  let nbotAddr
  let nbotMethods
  let configManager
  let configManagerAddr
  let configManagerMethods
  let eventFactory
  let eventFactoryAddr
  let event
  let eventAddr
  let eventMethods
  let eventParams
  let escrowAmt

  beforeEach(timeMachine.snapshot)
  afterEach(timeMachine.revert)

  beforeEach(async () => {
    // Deploy token
    nbot = await NRC223PreMinted.new(
      'Naka Bodhi Token',
      'NBOT',
      8,
      '10000000000000000',
      OWNER,
      { from: OWNER, gas: MAX_GAS })
    nbotAddr = nbot.contract._address
    nbotMethods = nbot.contract.methods

    // Deploy ConfigManager
    configManager = await ConfigManager.new({ from: OWNER, gas: MAX_GAS })
    configManagerAddr = configManager.contract._address
    configManagerMethods = configManager.contract.methods
    configManagerMethods.setBodhiToken(nbotAddr).send({ from: OWNER })
    escrowAmt = await configManagerMethods.eventEscrowAmount().call()

    // Deploy EventFactory
    eventFactory = await EventFactory.new(
      configManagerAddr,
      { from: OWNER, gas: MAX_GAS },
    )
    eventFactoryAddr = eventFactory.contract._address
    configManagerMethods.setEventFactory(eventFactoryAddr).send({ from: OWNER })

    // NBOT.transfer() -> create event
    eventParams = await getEventParams(OWNER)
    eventAddr = await createEvent({
      nbotMethods,
      eventParams,
      eventFactoryAddr,
      escrowAmt, 
      from: OWNER,
      gas: MAX_GAS,
    })
    event = await MultipleResultsEvent.at(eventAddr)
    eventMethods = event.contract.methods
  })

  describe('constructor', () => {
    it('initializes all the values', async () => {
      assert.equal(await eventMethods.owner().call(), OWNER)
      
      const eventMeta = await eventMethods.eventMetadata().call()
      assert.equal(eventMeta[0], 4)
      assert.equal(eventMeta[1], 'Test Event 1')
      assert.equal(web3.utils.toUtf8(eventMeta[2][0]), RESULT_INVALID)
      assert.equal(web3.utils.toUtf8(eventMeta[2][1]), 'A')
      assert.equal(web3.utils.toUtf8(eventMeta[2][2]), 'B')
      assert.equal(web3.utils.toUtf8(eventMeta[2][3]), 'C')
      assert.equal(eventMeta[3], 4)

      const centralizedMeta = await eventMethods.centralizedMetadata().call()
      assert.equal(centralizedMeta[0], eventParams[6])
      assert.equal(centralizedMeta[1], eventParams[2])
      assert.equal(centralizedMeta[2], eventParams[3])
      assert.equal(centralizedMeta[3], eventParams[4])
      assert.equal(centralizedMeta[4], eventParams[5])

      const configMeta = await eventMethods.configMetadata().call()
      assert.equal(configMeta[0], escrowAmt)
      assert.equal(
        configMeta[1],
        (await configManagerMethods.arbitrationLength().call())[0],
      )
      assert.equal(
        configMeta[2],
        await configManagerMethods.thresholdPercentIncrease().call(),
      )
      assert.equal(configMeta[3], eventParams[8])
    })

    it('throws if centralizedOracle address is invalid', async () => {
      try {
        const params = await getEventParams(INVALID_ADDR)
        params[0] = 'Test Event 2'
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e)
      }
    })

    it('throws if eventName is empty', async () => {
      try {
        const params = await getEventParams(OWNER)
        params[0] = ''
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'Event name cannot be empty')
      }
    })

    it('throws if eventResults 0 or 1 are empty', async () => {
      try {
        const params = await getEventParams(OWNER)
        params[0] = 'Test Event 3'
        params[1] = [
          web3.utils.fromAscii(''),
          web3.utils.fromAscii('B'),
          web3.utils.fromAscii('C'),
        ]
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'First event result cannot be empty')
      }

      try {
        const params = await getEventParams(OWNER)
        params[0] = 'Test Event 4'
        params[1] = [
          web3.utils.fromAscii('A'),
          web3.utils.fromAscii(''),
          web3.utils.fromAscii(''),
        ]
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'Second event result cannot be empty')
      }
    })

    it('throws if betEndTime is <= betStartTime', async () => {
      try {
        const params = await getEventParams(OWNER)
        params[0] = 'Test Event 5'
        params[3] = params[2]
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'betEndTime should be > betStartTime')
      }
    })

    it('throws if resultSetStartTime is < betEndTime', async () => {
      try {
        const params = await getEventParams(OWNER)
        params[0] = 'Test Event 6'
        params[4] = params[3]
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'resultSetStartTime should be >= betEndTime')
      }
    })

    it('throws if resultSetEndTime is <= resultSetStartTime', async () => {
      try {
        const params = await getEventParams(OWNER)
        params[0] = 'Test Event 7'
        params[5] = params[4]
        await createEvent({
          nbotMethods,
          eventParams: params,
          eventFactoryAddr,
          escrowAmt,
          from: OWNER, 
          gas: MAX_GAS,
        })
      } catch (e) {
        sassert.revert(e, 'resultSetEndTime should be > resultSetStartTime')
      }
    })
  })

  describe('tokenFallback()', () => {
    it('throws if data is not long enough', async () => {
      try {
        await nbotMethods['transfer(address,uint256,bytes)'](
          eventAddr,
          1,
          web3.utils.hexToBytes('0xaabbcc'),
        ).send({ from: OWNER, gas: 200000 })
      } catch (e) {
        sassert.revert(e, 'Data is not long enough')
      }
    })

    it('throws if function sig is unhandled', async () => {
      try {
        await nbotMethods['transfer(address,uint256,bytes)'](
          eventAddr,
          1,
          web3.utils.hexToBytes('0xaabbccdd0000000000000000000000000000000000000000000000000000000000000001'),
        ).send({ from: OWNER, gas: 200000 })
      } catch (e) {
        sassert.revert(e, 'Unhandled function in tokenFallback')
      }
    })
  })

  describe('bet()', () => {
    describe('valid bet time', () => {
      beforeEach(async () => {
        await fundUsers({ nbotMethods, accounts })
  
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(Number(eventParams[2]) - currTime)
        assert.isAtLeast(await currentBlockTime(), Number(eventParams[2]))
        assert.isBelow(await currentBlockTime(), Number(eventParams[3]))
      })

      it('allows users to bet', async () => {
        const bet1Amt = 1;
        await placeBet({
          nbotMethods,
          eventAddr,
          amtDecimals: bet1Amt,
          resultIndex: 0,
          from: OWNER,
        })
        assert.equal(
          await eventMethods.totalBets().call(),
          toDenomination(bet1Amt, TOKEN_DECIMALS))
  
        const bet2Amt = 1;
        await placeBet({
          nbotMethods,
          eventAddr,
          amtDecimals: bet2Amt,
          resultIndex: 1,
          from: ACCT1,
        })
        assert.equal(
          await eventMethods.totalBets().call(),
          toDenomination(bet1Amt + bet2Amt, TOKEN_DECIMALS))
      })
  
      it('throws if the currentRound is not 0', async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(Number(eventParams[4]) - currTime)
        assert.isAtLeast(await currentBlockTime(), Number(eventParams[4]))

        const amt = await eventMethods.currentConsensusThreshold().call()
        await setResult({
          nbotMethods,
          eventAddr,
          amt,
          resultIndex: 1,
          from: OWNER,
        })
        assert.equal(await eventMethods.currentRound().call(), 1)

        try {
          await placeBet({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 2,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Can only bet during the betting round')
        }
      })

      it('throws if the resultIndex is invalid', async () => {
        try {
          await placeBet({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 4,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'resultIndex is not valid')
        }
      })

      it('throws if the bet amount is 0', async () => {
        try {
          await placeBet({
            nbotMethods,
            eventAddr,
            amtDecimals: 0,
            resultIndex: 0,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Bet amount should be > 0')
        }
      })
    })

    describe('invalid bet time', () => {
      beforeEach(async () => {
        await fundUsers({ nbotMethods, accounts })
      })

      it('throws if the current time is < betStartTime', async () => {
        assert.isBelow(await currentBlockTime(), Number(eventParams[2]))

        try {
          await placeBet({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 0,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Current time should be >= betStartTime')
        }
      })

      it('throws if the current time is > betEndTime', async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(Number(eventParams[3]) - currTime)
        assert.isAtLeast(await currentBlockTime(), Number(eventParams[3]))

        try {
          await placeBet({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 0,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Current time should be < betEndTime.')
        }
      })
    })
  })

  //   describe('vote()', () => {
  //     beforeEach(async () => {
  //       const threshold = await cOracle.consensusThreshold.call()

  //       // Advance to result setting start time
  //       await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  //       assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)
  //       assert.isBelow(currentBlockTime(), eventParams._resultSettingEndTime)

  //       // Set the result
  //       const setResultIndex = 3
  //       const tx = await ContractHelper.transferSetResult(token, event, cOracle, OWNER, setResultIndex, threshold,
  //         OWNER)

  //       // Get dOracle
  //       const dOracleAddress = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //       dOracle = await DecentralizedOracle.at(dOracleAddress)
  //       assert.equal(await dOracle.lastResultIndex.call(), setResultIndex)
  //     })

  //     it('calls vote() correctly and sets the result when hitting the threshold', async () => {
  //       // Vote
  //       const threshold = await dOracle.consensusThreshold.call()
  //       const voteIndex = 1
  //       const tx = await ContractHelper.transferVote(token, event, dOracle, ACCT1, voteIndex, threshold)

  //       // Validate event
  //       assert.equal(await event.status.call(), EventStatus.ORACLE_VOTING)
  //       assert.equal(await event.resultIndex.call(), voteIndex)

  //       // Validate dOracle1
  //       SolAssert.assertBNEqual((await dOracle.getTotalVotes())[voteIndex], threshold)
  //       SolAssert.assertBNEqual((await dOracle.getVoteBalances({ from: ACCT1 }))[voteIndex], threshold)
  //       assert.isTrue(await dOracle.finished.call())
  //       assert.equal(await dOracle.resultIndex.call(), voteIndex)

  //       // Validate dOracle2
  //       const dOracle2Address = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //       const dOracle2 = await DecentralizedOracle.at(dOracle2Address)
  //       assert.equal(await dOracle2.lastResultIndex.call(), voteIndex)
  //       SolAssert.assertBNEqual(await dOracle2.consensusThreshold.call(),
  //         percentIncrease(threshold, thresholdIncrease))
  //     })

  //     it('throws if the data length is not 76 bytes', async () => {
  //       const voteAmount = toDenomination(50, tokenDecimals)
  //       const voteIndex = 1
  //       let data = '0x6f02d1fb'
  //         + Qweb3Utils.trimHexPrefix(dOracle.address)
  //         + Qweb3Utils.trimHexPrefix(ACCT1)
  //         + Encoder.uintToHex(voteIndex)
  //       assert.equal(data.length, 154)
  //       data = data.slice(0, 152)
  //       assert.equal(data.length, 152)

  //       try {
  //         await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](event.address, voteAmount, data)
  //           .send({ from: ACCT1, gas: 5000000 })
  //         assert.fail()
  //       } catch (e) {
  //         SolAssert.assertRevert(e)
  //       }
  //     })
  //   })

  //   it('throws if trying to call an unhandled function', async () => {
  //     try {
  //       await tokenWeb3Contract.methods["transfer(address,uint256,bytes)"](
  //         event.address,
  //         toDenomination(1, tokenDecimals),
  //         '0xabcdef01'
  //       ).send({ from: OWNER, gas: 5000000 })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }
  //   })
  // })

  // describe('finalizeResult()', () => {
  //   const cOracleResult = 1

  //   beforeEach(async () => {
  //     // Advance to result setting time
  //     await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)
  //     assert.isBelow(currentBlockTime(), eventParams._resultSettingEndTime)

  //     // Set the result
  //     const threshold = await cOracle.consensusThreshold.call()
  //     const tx = await ContractHelper.transferSetResult(token, event, cOracle, OWNER, cOracleResult, threshold, OWNER)
  //     const dOracleAddress = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     dOracle = await DecentralizedOracle.at(dOracleAddress)

  //     // Advance to arbitrationEndTime
  //     const arbitrationEndTime = (await dOracle.arbitrationEndTime.call()).toNumber()
  //     await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), arbitrationEndTime)

  //     // Finalize
  //     assert.equal(await event.status.call(), EventStatus.ORACLE_VOTING)
  //     await event.finalizeResult(dOracle.address, { from: ACCT1 })
  //     assert.equal(await event.status.call(), EventStatus.COLLECTION)
  //   })

  //   it('finalizes the result', async () => {
  //     const finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], cOracleResult)
  //     assert.isTrue(finalResult[1])
  //   })

  //   it('throws if the current status is not Status.Arbitration', async () => {
  //     try {
  //       await event.finalizeResult(dOracle.address, { from: ACCT1 })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }
  //   })
  // })

  // describe('withdrawWinnings()', () => {
  //   const cOracleResult = 2
  //   const dOracle1Result = 1
  //   const dOracle2Result = 2
  //   let bet1, bet2, bet3, bet4
  //   let totalBetBalance
  //   let cOracleThreshold

  //   beforeEach(async () => {
  //     // Advance to betting time
  //     await timeMachine.increaseTime(eventParams._bettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._bettingStartTime)
  //     assert.isBelow(currentBlockTime(), eventParams._bettingEndTime)

  //     // First round of betting
  //     bet1 = toDenomination(7777777777)
  //     await event.bet(cOracle.address, 0, { from: ACCT1, value: bet1 })
  //     totalBetBalance = bet1
  //     assert.equal(await web3.eth.getBalance(event.address), totalBetBalance)
  //     SolAssert.assertBNEqual((await event.getBetBalances({ from: ACCT1 }))[0], bet1)

  //     bet2 = toDenomination(2212345678)
  //     await event.bet(cOracle.address, 1, { from: ACCT2, value: bet2 })
  //     totalBetBalance = bet1.add(bet2)
  //     assert.equal(await web3.eth.getBalance(event.address), totalBetBalance)
  //     SolAssert.assertBNEqual((await event.getBetBalances({ from: ACCT2 }))[1], bet2)

  //     bet3 = toDenomination(3027596457)
  //     await event.bet(cOracle.address, cOracleResult, { from: ACCT3, value: bet3 })
  //     totalBetBalance = bet1.add(bet2).add(bet3)
  //     assert.equal(await web3.eth.getBalance(event.address), totalBetBalance)
  //     SolAssert.assertBNEqual((await event.getBetBalances({ from: ACCT3 }))[cOracleResult], bet3)

  //     bet4 = toDenomination(1298765432)
  //     await event.bet(cOracle.address, cOracleResult, { from: ACCT4, value: bet4 })
  //     totalBetBalance = bet1.add(bet2).add(bet3).add(bet4)
  //     assert.equal(await web3.eth.getBalance(event.address), totalBetBalance)
  //     SolAssert.assertBNEqual((await event.getBetBalances({ from: ACCT4 }))[cOracleResult], bet4)

  //     SolAssert.assertBNEqual(await event.totalBetTokens.call(), totalBetBalance)

  //     // Advance time to result setting time
  //     await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)
  //     assert.isBelow(currentBlockTime(), eventParams._resultSettingEndTime)
      
  //     // cOracle set result 2
  //     cOracleThreshold = await cOracle.consensusThreshold.call()
  //     const tx = await ContractHelper.transferSetResult(token, event, cOracle, OWNER, cOracleResult, cOracleThreshold)
  //     const dOracleAddress = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     dOracle = await DecentralizedOracle.at(dOracleAddress)
  //   })

  //   it('transfers the tokens for a multiple betting/voting rounds', async () => {
  //     // dOracle1 voting hits consensusThreshold
  //     const vote1a = toDenomination(61.12345678, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle, ACCT1, dOracle1Result, vote1a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT1 }))[dOracle1Result], vote1a)

  //     const vote2 = toDenomination(48.87654322, tokenDecimals)
  //     let tx = await ContractHelper.transferVote(token, event, dOracle, ACCT2, dOracle1Result, vote2)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT2 }))[dOracle1Result], vote2)

  //     let totalVoteBalance = cOracleThreshold.add(vote1a).add(vote2)
  //     let totalArbitrationTokens = await event.totalArbitrationTokens.call()
  //     SolAssert.assertBNEqual(await token.balanceOf(event.address), totalArbitrationTokens)

  //     // Get dOracle2 instance
  //     const dOracle2Address = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     const dOracle2 = await DecentralizedOracle.at(dOracle2Address)
      
  //     // DecentralizedOracle2 voting hits consensusThreshold
  //     const vote3 = toDenomination(73.73737373, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle2, ACCT3, dOracle2Result, vote3)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT3 }))[dOracle2Result], vote3)

  //     const vote4 = toDenomination(47.26262627, tokenDecimals)
  //     tx = await ContractHelper.transferVote(token, event, dOracle2, ACCT4, dOracle2Result, vote4)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT4 }))[dOracle2Result], vote4)

  //     // Get dOracle3 instance
  //     const dOracle3Address = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     const dOracle3 = await DecentralizedOracle.at(dOracle3Address)

  //     totalVoteBalance = totalVoteBalance.add(vote3).add(vote4)
  //     totalArbitrationTokens = await event.totalArbitrationTokens.call()
  //     SolAssert.assertBNEqual(totalArbitrationTokens, totalVoteBalance)
  //     SolAssert.assertBNEqual(await token.balanceOf(event.address), totalArbitrationTokens)

  //     // dOracle3 voting under consensusThreshold
  //     const vote1b = toDenomination(71.35713713, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle3, ACCT1, dOracle1Result, vote1b)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT1 }))[dOracle1Result], vote1a.add(vote1b))

  //     // Advance to arbitrationEndTime
  //     const arbitrationEndTime = (await dOracle3.arbitrationEndTime.call()).toNumber()
  //     await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), arbitrationEndTime)
      
  //     // DecentralizedOracle finalize result
  //     await event.finalizeResult(dOracle3.address, { from: ACCT1 })
  //     assert.equal(await event.status.call(), EventStatus.COLLECTION)
  //     const finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], dOracle2Result)
  //     assert.isTrue(finalResult[1])

  //     const expectedTotalBetTokens = bet1.add(bet2).add(bet3).add(bet4)
  //     SolAssert.assertBNEqual(await event.totalBetTokens.call(), expectedTotalBetTokens)
  //     const expectedTotalArbitrationTokens = cOracleThreshold.add(vote1a).add(vote1b).add(vote2).add(vote3).add(vote4)
  //     SolAssert.assertBNEqual(await event.totalArbitrationTokens.call(), expectedTotalArbitrationTokens)

  //     // ACCT3 winner withdraw
  //     let winningsArr = await event.calculateWinnings({ from: ACCT3 })
  //     let arbTokensWon = winningsArr[0]
  //     let betTokensWon = winningsArr[1]

  //     let expectedBetTokens = toDenomination(await web3.eth.getBalance(event.address)).sub(betTokensWon)
  //     let expectedArbTokens = (await token.balanceOf(event.address)).sub(arbTokensWon)
  //     assert.isFalse(await event.didWithdraw.call(ACCT3))
  //     await event.withdrawWinnings({ from: ACCT3 })
  //     SolAssert.assertBNEqual(await web3.eth.getBalance(event.address), expectedBetTokens)
  //     SolAssert.assertBNEqual(await token.balanceOf(event.address), expectedArbTokens)
  //     assert.isTrue(await event.didWithdraw.call(ACCT3))

  //     // ACCT4 winner withdraw
  //     winningsArr = await event.calculateWinnings({ from: ACCT4 })
  //     arbTokensWon = winningsArr[0]
  //     betTokensWon = winningsArr[1]

  //     expectedBetTokens = toDenomination(await web3.eth.getBalance(event.address)).sub(betTokensWon)
  //     expectedArbTokens = (await token.balanceOf(event.address)).sub(arbTokensWon)
  //     assert.isFalse(await event.didWithdraw.call(ACCT4))
  //     await event.withdrawWinnings({ from: ACCT4 })
  //     SolAssert.assertBNEqual(await web3.eth.getBalance(event.address), expectedBetTokens)
  //     SolAssert.assertBNEqual(await token.balanceOf(event.address), expectedArbTokens)
  //     assert.isTrue(await event.didWithdraw.call(ACCT4))

  //     // OWNER winner withdraw
  //     winningsArr = await event.calculateWinnings({ from: OWNER })
  //     arbTokensWon = winningsArr[0]
  //     betTokensWon = winningsArr[1]

  //     expectedBetTokens = toDenomination(await web3.eth.getBalance(event.address)).sub(betTokensWon)
  //     expectedArbTokens = (await token.balanceOf(event.address)).sub(arbTokensWon)
  //     assert.isFalse(await event.didWithdraw.call(OWNER))
  //     await event.withdrawWinnings({ from: OWNER })
  //     SolAssert.assertBNEqual(await web3.eth.getBalance(event.address), expectedBetTokens)
  //     SolAssert.assertBNEqual(await token.balanceOf(event.address), expectedArbTokens)
  //     assert.isTrue(await event.didWithdraw.call(OWNER))

  //     // ACCT1 loser withdraw
  //     winningsArr = await event.calculateWinnings({ from: ACCT1 })
  //     arbTokensWon = winningsArr[0]
  //     betTokensWon = winningsArr[1]

  //     assert.equal(arbTokensWon, 0)
  //     assert.equal(betTokensWon, 0)
  //     assert.isFalse(await event.didWithdraw.call(ACCT1))
  //     await event.withdrawWinnings({ from: ACCT1 })
  //     assert.isTrue(await event.didWithdraw.call(ACCT1))

  //     // ACCT2 loser withdraw
  //     winningsArr = await event.calculateWinnings({ from: ACCT2 })
  //     arbTokensWon = winningsArr[0]
  //     betTokensWon = winningsArr[1]

  //     assert.equal(arbTokensWon, 0)
  //     assert.equal(betTokensWon, 0)
  //     assert.isFalse(await event.didWithdraw.call(ACCT2))
  //     await event.withdrawWinnings({ from: ACCT2 })
  //     assert.isTrue(await event.didWithdraw.call(ACCT2))
  //   })

  //   it('throws if status is not Status.Collection', async () => {
  //     assert.notEqual(await event.status.call(), EventStatus.COLLECTION)
  //     try {
  //       await event.withdrawWinnings({ from: OWNER })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }
  //   })

  //   it('throws if already withdrawn', async () => {
  //     // Advance to arbitrationEndTime
  //     const arbitrationEndTime = (await dOracle.arbitrationEndTime.call()).toNumber()
  //     await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), arbitrationEndTime)
      
  //     // dOracle finalize result
  //     await event.finalizeResult(dOracle.address, { from: ACCT1 })
  //     assert.equal(await event.status.call(), EventStatus.COLLECTION)
  //     const finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], cOracleResult)
  //     assert.isTrue(finalResult[1])

  //     // Winner withdraw
  //     await event.withdrawWinnings({ from: ACCT3 })
  //     assert.isTrue(await event.didWithdraw.call(ACCT3))

  //     try {
  //       await event.withdrawWinnings({ from: ACCT3 })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }

  //     // Loser withdraw
  //     await event.withdrawWinnings({ from: ACCT1 })
  //     assert.isTrue(await event.didWithdraw.call(ACCT1))

  //     try {
  //       await event.withdrawWinnings({ from: ACCT1 })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }
  //   })
  // })

  // // TODO: refactor when EscrowBank is done
  // // describe('withdrawEscrow()', () => {
  // //   describe('in Status:Collection', () => {
  // //     beforeEach(async () => {
  // //       // Set result
  // //       await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  // //       assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)
  // //       assert.isBelow(currentBlockTime(), eventParams._resultSettingEndTime)

  // //       await ContractHelper.approve(token, ORACLE, event.address, cOracleThreshold)

  // //       await centralizedOracle.setResult(0, { from: ORACLE })
  // //       assert.isTrue((await event.oracles.call(0))[1])
  // //       assert.equal((await event.status.call()).toNumber(), STATUS_VOTING)
  // //       const finalResult = await event.getFinalResult()
  // //       assert.equal(finalResult[0], 0)
  // //       assert.isFalse(finalResult[1])

  // //       // Finalize
  // //       decentralizedOracle = await DecentralizedOracle.at((await event.oracles.call(1))[0])

  // //       const arbitrationEndTime = (await decentralizedOracle.arbitrationEndTime.call()).toNumber()
  // //       await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  // //       assert.isAtLeast(currentBlockTime(), arbitrationEndTime)

  // //       await decentralizedOracle.finalizeResult({ from: ACCT1 })
  // //       assert.isTrue(await decentralizedOracle.finished.call())
  // //       assert.equal((await event.status.call()).toNumber(), STATUS_COLLECTION)
  // //     })

  // //     it('transfer the escrow to the creator', async () => {
  // //       const balanceBefore = await token.balanceOf(OWNER)
  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), escrowAmount)

  // //       assert.equal(await event.owner.call(), OWNER)
  // //       await event.withdrawEscrow({ from: OWNER })
  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), 0)
  // //       SolAssert.assertBNEqual(await token.balanceOf(OWNER), balanceBefore.add(escrowAmount))
  // //     })

  // //     it('throws if trying to withdraw escrow from non-owner address', async () => {
  // //       const balanceBeforeOwner = await token.balanceOf(OWNER)
  // //       const balanceBeforeUser1 = await token.balanceOf(ACCT1)

  // //       try {
  // //         await event.withdrawEscrow({ from: ACCT1 })
  // //         assert.fail()
  // //       } catch (e) {
  // //         SolAssert.assertRevert(e)
  // //       }

  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), escrowAmount)
  // //       SolAssert.assertBNEqual(await token.balanceOf(OWNER), balanceBeforeOwner)
  // //       SolAssert.assertBNEqual(await token.balanceOf(ACCT1), balanceBeforeUser1)
  // //     })

  // //     it('throws if the creator tries to withdraw escrow more than once', async () => {
  // //       const balanceBefore = await token.balanceOf(OWNER)
  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), escrowAmount)

  // //       assert.equal(await event.owner.call(), OWNER)
  // //       await event.withdrawEscrow({ from: OWNER })
  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), 0)
  // //       const balanceAfter = balanceBefore.add(escrowAmount)
  // //       SolAssert.assertBNEqual(await token.balanceOf(OWNER), balanceAfter)

  // //       try {
  // //         await event.withdrawEscrow({ from: OWNER })
  // //         assert.fail()
  // //       } catch (e) {
  // //         SolAssert.assertRevert(e)
  // //       }

  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), 0)
  // //       SolAssert.assertBNEqual(await token.balanceOf(OWNER), balanceAfter)
  // //     })
  // //   })

  // //   describe('not in Status:Collection', () => {
  // //     it('throws if trying to withdraw escrow not in Status:Collection', async () => {
  // //       assert.notEqual((await event.status.call()).toNumber(), STATUS_COLLECTION)

  // //       const balanceBefore = await token.balanceOf(OWNER)

  // //       try {
  // //         await event.withdrawEscrow({ from: OWNER })
  // //         assert.fail()
  // //       } catch (e) {
  // //         SolAssert.assertRevert(e)
  // //       }

  // //       SolAssert.assertBNEqual(await token.balanceOf(configMgr.address), escrowAmount)
  // //       SolAssert.assertBNEqual(await token.balanceOf(OWNER), balanceBefore)
  // //     })
  // //   })
  // // })

  // describe('getFinalResult()', () => {
  //   it('returns the final resultIndex and flag if finalized', async () => {
  //     // Advance to result setting time
  //     await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)

  //     // Set result
  //     const finalResultIndex = 1
  //     const tx = await ContractHelper.transferSetResult(token, event, cOracle, OWNER, finalResultIndex,
  //       cOracleThreshold)
  //     const dOracleAddress = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     dOracle = await DecentralizedOracle.at(dOracleAddress)

  //     let finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], finalResultIndex)
  //     assert.isFalse(finalResult[1])

  //     // Advance to finalize time
  //     const arbitrationEndTime = (await dOracle.arbitrationEndTime.call()).toNumber()
  //     await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), arbitrationEndTime)
  //     await event.finalizeResult(dOracle.address)

  //     finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], finalResultIndex)
  //     assert.isTrue(finalResult[1])
  //   })
  // })

  // describe('calculateWinnings', () => {
  //   const cOracleResult = 2

  //   it('returns the correct amounts for multiple rounds', async () => {
  //     const dOracle1Result = 0
  //     const dOracle2Result = 2
  //     let totalBets
  //     let totalVotes

  //     // Advance to betting time
  //     await timeMachine.increaseTime(eventParams._bettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._bettingStartTime)
  //     assert.isBelow(currentBlockTime(), eventParams._bettingEndTime)

  //     // First round of betting
  //     bet1 = toDenomination(12.3456789, TOKEN_DECIMALS)
  //     await event.bet(cOracle.address, 0, { from: ACCT1, value: bet1 })
  //     totalBets = bet1
  //     SolAssert.assertBNEqual(toDenomination(await web3.eth.getBalance(event.address)), totalBets)

  //     bet2 = toDenomination(23.45678901, TOKEN_DECIMALS)
  //     await event.bet(cOracle.address, 1, { from: ACCT2, value: bet2 })
  //     totalBets = bet1.add(bet2)
  //     SolAssert.assertBNEqual(toDenomination(await web3.eth.getBalance(event.address)), totalBets)

  //     bet3 = toDenomination(30.47682524, TOKEN_DECIMALS)
  //     await event.bet(cOracle.address, cOracleResult, { from: ACCT3, value: bet3 })
  //     totalBets = bet1.add(bet2).add(bet3)
  //     SolAssert.assertBNEqual(toDenomination(await web3.eth.getBalance(event.address)), totalBets)

  //     bet4 = toDenomination(12.18956777, TOKEN_DECIMALS)
  //     await event.bet(cOracle.address, cOracleResult, { from: ACCT4, value: bet4 })
  //     totalBets = bet1.add(bet2).add(bet3).add(bet4)
  //     SolAssert.assertBNEqual(toDenomination(await web3.eth.getBalance(event.address)), totalBets)

  //     SolAssert.assertBNEqual(await event.totalBetTokens.call(), totalBets)

  //     // Advance to result setting time
  //     await timeMachine.increaseTime(eventParams._resultSettingStartTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), eventParams._resultSettingStartTime)

  //     // Set result 2
  //     let tx = await ContractHelper.transferSetResult(token, event, cOracle, OWNER, cOracleResult, cOracleThreshold)
  //     const dOracleAddress = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     dOracle = await DecentralizedOracle.at(dOracleAddress)

  //     totalVotes = cOracleThreshold
  //     SolAssert.assertBNEqual(await event.totalArbitrationTokens.call(), totalVotes)
  //     assert.equal((await event.getFinalResult())[0], cOracleResult)

  //     // dOracle1 voting. Threshold hits and result becomes 0.
  //     const vote1a = toDenomination(60.12345678, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle, ACCT1, dOracle1Result, vote1a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT1 }))[dOracle1Result], vote1a)

  //     const vote2a = toDenomination(49.87654322, tokenDecimals)
  //     tx = await ContractHelper.transferVote(token, event, dOracle, ACCT2, dOracle1Result, vote2a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT2 }))[dOracle1Result], vote2a)

  //     totalVotes = totalVotes.add(vote1a).add(vote2a)
  //     SolAssert.assertBNEqual(await event.totalArbitrationTokens.call(), totalVotes)
  //     assert.equal((await event.getFinalResult())[0], dOracle1Result)

  //     // Get dOracle2
  //     const dOracle2Address = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     const dOracle2 = await DecentralizedOracle.at(dOracle2Address)

  //     // dOracle2 voting. Threshold hits and result becomes 2.
  //     const vote3a = toDenomination(30.12345678, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle2, ACCT3, dOracle2Result, vote3a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT3 }))[dOracle2Result], vote3a)

  //     const vote4a = toDenomination(40.87654321, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle2, ACCT4, dOracle2Result, vote4a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT4 }))[dOracle2Result], vote4a)

  //     const vote5a = toDenomination(50.00000001, tokenDecimals)
  //     tx = await ContractHelper.transferVote(token, event, dOracle2, ACCT5, dOracle2Result, vote5a)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT5 }))[dOracle2Result], vote5a)

  //     totalVotes = totalVotes.add(vote3a).add(vote4a).add(vote5a)
  //     SolAssert.assertBNEqual(await event.totalArbitrationTokens.call(), totalVotes)
  //     assert.equal((await event.getFinalResult())[0], dOracle2Result)

  //     // Get dOracle3
  //     const dOracle3Address = paddedHexToAddress(tx.events['2'].raw.topics[2])
  //     const dOracle3 = await DecentralizedOracle.at(dOracle3Address)

  //     // dOracle3 voting. Does not his threshold and result gets finalized to 2.
  //     const vote1b = toDenomination(53.77777777, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle3, ACCT1, dOracle1Result, vote1b)
  //     const totalVote1 = vote1a.add(vote1b)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT1 }))[dOracle1Result], totalVote1)

  //     const vote2b = toDenomination(49.55555555, tokenDecimals)
  //     await ContractHelper.transferVote(token, event, dOracle3, ACCT2, dOracle1Result, vote2b)
  //     const totalVote2 = vote2a.add(vote2b)
  //     SolAssert.assertBNEqual((await event.getVoteBalances({ from: ACCT2 }))[dOracle1Result], totalVote2)

  //     // Advance to finalize time
  //     const arbitrationEndTime = (await dOracle3.arbitrationEndTime.call()).toNumber()
  //     await timeMachine.increaseTime(arbitrationEndTime - currentBlockTime())
  //     assert.isAtLeast(currentBlockTime(), arbitrationEndTime)
      
  //     // Finalize result 2
  //     await event.finalizeResult(dOracle3.address)
  //     assert.equal(await event.status.call(), EventStatus.COLLECTION)
  //     const finalResult = await event.getFinalResult()
  //     assert.equal(finalResult[0], dOracle2Result)
  //     assert.isTrue(finalResult[1])

  //     // Withdraw winnings: ACCT3, ACCT4, ACCT5, ORACLE
  //     const percentCut = await event.ARBITRATION_REWARD_PERCENTAGE.call()
  //     let losersBetTokens = bet1.add(bet2)
  //     const winnersBetTokens = bet3.add(bet4)
  //     const rewardBetTokens = bigNumberFloor(losersBetTokens.mul(percentCut).div(100))
  //     losersBetTokens = losersBetTokens.sub(rewardBetTokens)
  //     const losersArbTokens = vote1a.add(vote2a).add(vote1b).add(vote2b)
  //     const winnersArbTokens = cOracleThreshold.add(vote3a).add(vote4a).add(vote5a)

  //     // ACCT3 winner
  //     let votes = vote3a
  //     let expectedArbTokens = bigNumberFloor(votes.mul(losersArbTokens).div(winnersArbTokens).add(votes))
  //     let winnerBetTokenReward = bigNumberFloor(votes.mul(rewardBetTokens).div(winnersArbTokens))

  //     let bets = bet3
  //     let expectedBetTokens = bigNumberFloor(bets.mul(losersBetTokens).div(winnersBetTokens).add(bets))
  //     expectedBetTokens = expectedBetTokens.add(winnerBetTokenReward)

  //     let winningsArr = await event.calculateWinnings({ from: ACCT3 })
  //     SolAssert.assertBNEqual(winningsArr[0], expectedArbTokens)
  //     SolAssert.assertBNEqual(winningsArr[1], expectedBetTokens)

  //     // ACCT4 winner
  //     votes = vote4a
  //     expectedArbTokens = bigNumberFloor(votes.mul(losersArbTokens).div(winnersArbTokens).add(votes))
  //     winnerBetTokenReward = bigNumberFloor(votes.mul(rewardBetTokens).div(winnersArbTokens))

  //     bets = bet4
  //     expectedBetTokens = bigNumberFloor(bets.mul(losersBetTokens).div(winnersBetTokens).add(bets))
  //     expectedBetTokens = expectedBetTokens.add(winnerBetTokenReward)

  //     winningsArr = await event.calculateWinnings({ from: ACCT4 })
  //     SolAssert.assertBNEqual(winningsArr[0], expectedArbTokens)
  //     SolAssert.assertBNEqual(winningsArr[1], expectedBetTokens)

  //     // ACCT5 winner
  //     votes = vote5a
  //     expectedArbTokens = bigNumberFloor(votes.mul(losersArbTokens).div(winnersArbTokens).add(votes))
  //     winnerBetTokenReward = bigNumberFloor(votes.mul(rewardBetTokens).div(winnersArbTokens))

  //     bets = toDenomination(0)
  //     expectedBetTokens = bigNumberFloor(bets.mul(losersBetTokens).div(winnersBetTokens).add(bets))
  //     expectedBetTokens = expectedBetTokens.add(winnerBetTokenReward)

  //     winningsArr = await event.calculateWinnings({ from: ACCT5 })
  //     SolAssert.assertBNEqual(winningsArr[0], expectedArbTokens)
  //     SolAssert.assertBNEqual(winningsArr[1], expectedBetTokens)

  //     // CentralizedOracle winner
  //     votes = cOracleThreshold
  //     expectedArbTokens = bigNumberFloor(votes.mul(losersArbTokens).div(winnersArbTokens).add(votes))
  //     winnerBetTokenReward = bigNumberFloor(votes.mul(rewardBetTokens).div(winnersArbTokens))

  //     bets = toDenomination(0)
  //     expectedBetTokens = bigNumberFloor(bets.mul(losersBetTokens).div(winnersBetTokens).add(bets))
  //     expectedBetTokens = expectedBetTokens.add(winnerBetTokenReward)

  //     winningsArr = await event.calculateWinnings({ from: OWNER })
  //     SolAssert.assertBNEqual(winningsArr[0], expectedArbTokens)
  //     SolAssert.assertBNEqual(winningsArr[1], expectedBetTokens)

  //     // ACCT1 loser
  //     winningsArr = await event.calculateWinnings({ from: ACCT1 })
  //     SolAssert.assertBNEqual(winningsArr[0], 0)
  //     SolAssert.assertBNEqual(winningsArr[1], 0)

  //     // ACCT2 loser
  //     winningsArr = await event.calculateWinnings({ from: ACCT2 })
  //     SolAssert.assertBNEqual(winningsArr[0], 0)
  //     SolAssert.assertBNEqual(winningsArr[1], 0)
  //   })

  //   it('throws if status is not Status.Collection', async () => {
  //     assert.notEqual(await event.status.call(), EventStatus.COLLECTION)
  //     try {
  //       await event.calculateWinnings({ from: ACCT3 })
  //       assert.fail()
  //     } catch (e) {
  //       SolAssert.assertRevert(e)
  //     }
  //   })
  // })
})
