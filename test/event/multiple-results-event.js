const { assert } = require('chai')
const TimeMachine = require('sol-time-machine')
const sassert = require('sol-assert')
const { isNumber } = require('lodash') 
const getConstants = require('../constants')
const {
  toSatoshi,
  currentBlockTime,
  constructTransfer223Data,
  decodeEvent,
} = require('../util')
const NRC223PreMinted = artifacts.require('NRC223PreMinted')
const ConfigManager = artifacts.require('ConfigManager')
const EventFactory = artifacts.require('EventFactory')
const MultipleResultsEvent = artifacts.require('MultipleResultsEvent')

const web3 = global.web3
const { toBN } = web3.utils;

const CREATE_EVENT_FUNC_SIG = '662edd20'
const BET_FUNC_SIG = '885ab66d'
const SET_RESULT_FUNC_SIG = 'a6b4218b'
const VOTE_FUNC_SIG = '1e00eb7f'
const RESULT_INVALID = 'Invalid'
const RESULT_INDEX_INVALID = 255

const fundUsers = async ({ nbotMethods, accounts }) => {
  await nbotMethods.transfer(accounts[1], toSatoshi(10000).toString())
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[2], toSatoshi(10000).toString())
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[3], toSatoshi(10000).toString())
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[4], toSatoshi(10000).toString())
    .send({ from: accounts[0] })
  await nbotMethods.transfer(accounts[5], toSatoshi(10000).toString())
    .send({ from: accounts[0] })
}

const getEventParams = async (cOracle, currTime) => {
  return [
    'Test Event 1',
    [
      web3.utils.fromAscii('A'),
      web3.utils.fromAscii('B'),
      web3.utils.fromAscii('C'),
    ],
    currTime + 3000,
    currTime + 4000,
    currTime + 6000,
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
      ['string', 'bytes32[3]', 'uint256', 'uint256', 'uint256', 'address',
        'uint8', 'uint256'],
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
  { nbotMethods, eventAddr, amtDecimals, amtSatoshi, resultIndex, from }
) => {
  const amt = isNumber(amtDecimals) ? toSatoshi(amtDecimals).toString() : amtSatoshi
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
  ).send({ from, gas: 300000 })
}

const placeVote = async (
  { nbotMethods, eventAddr, amtDecimals, amtSatoshi, resultIndex, from }
) => {
  const amt = isNumber(amtDecimals) ? toSatoshi(amtDecimals).toString() : amtSatoshi
  const data = constructTransfer223Data(VOTE_FUNC_SIG, ['uint8'], [resultIndex])
  await nbotMethods['transfer(address,uint256,bytes)'](
    eventAddr,
    amt,
    web3.utils.hexToBytes(data),
  ).send({ from, gas: 400000 })
}

const calculateNormalWinnings = ({
  maxPercent,
  arbRewardPercent,
  arbRewardPercentComp,
  betRoundWinnersTotal,
  betRoundLosersTotal,
  voteRoundsWinnersTotal,
  voteRoundsLosersTotal,
  myWinningBets,
  myWinningVotes,
}) => {
  let betRoundWinningAmt = toBN(0)
  if (myWinningBets.gt(0)) {
    betRoundWinningAmt = betRoundLosersTotal
      .mul(arbRewardPercentComp)
      .div(maxPercent)
      .mul(myWinningBets)
      .div(betRoundWinnersTotal)
  }

  let voteRoundsWinningAmt = toBN(0)
  if (myWinningVotes.gt(0)) {
    voteRoundsWinningAmt = betRoundLosersTotal
      .mul(arbRewardPercent)
      .div(maxPercent)
      .add(voteRoundsLosersTotal)
      .mul(myWinningVotes)
      .div(voteRoundsWinnersTotal)
  }

  return myWinningBets
    .add(myWinningVotes)
    .add(betRoundWinningAmt)
    .add(voteRoundsWinningAmt)
}

contract('MultipleResultsEvent', (accounts) => {
  const {
    OWNER,
    ACCT1,
    ACCT2,
    ACCT3,
    ACCT4,
    ACCT5,
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
  let betStartTime
  let betEndTime
  let resultSetStartTime
  let resultSetEndTime

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
    await fundUsers({ nbotMethods, accounts })

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

    // Setup event params
    betStartTime = await currentBlockTime()
    eventParams = await getEventParams(OWNER, betStartTime)
    betEndTime = eventParams[2]
    resultSetStartTime = eventParams[3]
    resultSetEndTime = eventParams[4]

    // NBOT.transfer() -> create event
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
      assert.equal(eventMeta[0], 6)
      assert.equal(eventMeta[1], 'Test Event 1')
      assert.equal(web3.utils.toUtf8(eventMeta[2][0]), RESULT_INVALID)
      assert.equal(web3.utils.toUtf8(eventMeta[2][1]), 'A')
      assert.equal(web3.utils.toUtf8(eventMeta[2][2]), 'B')
      assert.equal(web3.utils.toUtf8(eventMeta[2][3]), 'C')
      assert.equal(eventMeta[3], 4)

      const centralizedMeta = await eventMethods.centralizedMetadata().call()
      assert.equal(centralizedMeta[0], eventParams[5])
      assert.equal(centralizedMeta[1], betStartTime)
      assert.equal(centralizedMeta[2], betEndTime)
      assert.equal(centralizedMeta[3], resultSetStartTime)
      assert.equal(centralizedMeta[4], resultSetEndTime)

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
      assert.equal(configMeta[3], eventParams[7])
    })

    it('throws if centralizedOracle address is invalid', async () => {
      try {
        const params = await getEventParams(INVALID_ADDR, await currentBlockTime())
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
        const params = await getEventParams(OWNER, await currentBlockTime())
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
        const params = await getEventParams(OWNER, await currentBlockTime())
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
        const params = await getEventParams(OWNER, await currentBlockTime())
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
        const params = await getEventParams(OWNER, await currentBlockTime())
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
        const params = await getEventParams(OWNER, await currentBlockTime())
        params[0] = 'Test Event 6'
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
        sassert.revert(e, 'resultSetStartTime should be >= betEndTime')
      }
    })

    it('throws if resultSetEndTime is <= resultSetStartTime', async () => {
      try {
        const params = await getEventParams(OWNER, await currentBlockTime())
        params[0] = 'Test Event 7'
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
    describe('valid time', () => {
      beforeEach(async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(betStartTime - currTime)
        assert.isAtLeast(await currentBlockTime(), betStartTime)
        assert.isBelow(await currentBlockTime(), betEndTime)
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
        sassert.bnEqual(await eventMethods.totalBets().call(), toSatoshi(bet1Amt))
  
        const bet2Amt = 1;
        await placeBet({
          nbotMethods,
          eventAddr,
          amtDecimals: bet2Amt,
          resultIndex: 1,
          from: ACCT1,
        })
        sassert.bnEqual(
          await eventMethods.totalBets().call(),
          toSatoshi(bet1Amt + bet2Amt))
      })
  
      it('throws if the currentRound is not 0', async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(resultSetStartTime - currTime)
        assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

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

    describe('invalid time', () => {
      it('throws if the current time is > betEndTime', async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(betEndTime - currTime)
        assert.isAtLeast(await currentBlockTime(), betEndTime)

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

  describe('setResult()', () => {
    let threshold

    beforeEach(async () => {
      threshold = await eventMethods.currentConsensusThreshold().call()
    })

    describe('valid time', () => {
      beforeEach(async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(resultSetStartTime - currTime)
        assert.isAtLeast(await currentBlockTime(), resultSetStartTime)
      })

      it('sets the result', async () => {
        assert.equal(
          await eventMethods.currentResultIndex().call(),
          RESULT_INDEX_INVALID)

        await setResult({
          nbotMethods,
          eventAddr,
          amt: threshold,
          resultIndex: 1,
          from: OWNER,
        })
        assert.equal(await eventMethods.currentResultIndex().call(), 1)
        assert.equal(await eventMethods.currentRound().call(), 1)
        assert.equal(await eventMethods.totalBets().call(), threshold)
        sassert.bnGTE(
          await eventMethods.currentConsensusThreshold().call(),
          threshold)
        sassert.bnGTE(
          await eventMethods.currentArbitrationEndTime().call(),
          resultSetEndTime)
      })

      it('allows anyone to set the result after the resultSetEndTime', async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(resultSetEndTime - currTime)
        assert.isAtLeast(await currentBlockTime(), resultSetEndTime)

        assert.equal(
          await eventMethods.currentResultIndex().call(),
          RESULT_INDEX_INVALID)

        await setResult({
          nbotMethods,
          eventAddr,
          amt: threshold,
          resultIndex: 1,
          from: ACCT1,
        })
        assert.equal(await eventMethods.currentResultIndex().call(), 1)
        assert.equal(await eventMethods.currentRound().call(), 1)
        assert.equal(await eventMethods.totalBets().call(), threshold)
        sassert.bnGTE(
          await eventMethods.currentConsensusThreshold().call(),
          threshold)
        sassert.bnGTE(
          await eventMethods.currentArbitrationEndTime().call(),
          resultSetEndTime)
      })

      it('throws if the resultIndex is invalid', async () => {
        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: threshold,
            resultIndex: 4,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'resultIndex is not valid')
        }
      })
  
      it('throws if the currentRound is not 0', async () => {
        await setResult({
          nbotMethods,
          eventAddr,
          amt: threshold,
          resultIndex: 1,
          from: OWNER,
        })
        assert.equal(await eventMethods.currentRound().call(), 1)

        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: threshold,
            resultIndex: 2,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Can only set result during the betting round')
        }
      })

      it('throws if a non-centralized oracle sets the result during oracle result setting', async () => {
        assert.isBelow(await currentBlockTime(), resultSetEndTime)

        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: threshold,
            resultIndex: 1,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'Only the Centralized Oracle can set the result')
        }
      })

      it('throws if the value is not the consensus threshold', async () => {
        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: toBN(threshold).sub(toBN(1)).toString(),
            resultIndex: 1,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Set result amount should = consensusThreshold')
        }

        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: toBN(threshold).add(toBN(1)).toString(),
            resultIndex: 1,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Set result amount should = consensusThreshold')
        }
      })
    })

    describe('invalid time', () => {
      it('throws if the current time is < resultSetStartTime', async () => {
        assert.isBelow(await currentBlockTime(), resultSetStartTime)

        try {
          await setResult({
            nbotMethods,
            eventAddr,
            amt: threshold,
            resultIndex: 1,
            from: OWNER,
          })
        } catch (e) {
          sassert.revert(e, 'Current time should be >= resultSetStartTime')
        }
      })
    })
  })

  describe('vote()', () => {
    let threshold

    describe('valid time', () => {
      beforeEach(async () => {
        const currTime = await currentBlockTime()
        await timeMachine.increaseTime(resultSetStartTime - currTime)
        assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

        threshold = await eventMethods.currentConsensusThreshold().call()
        await setResult({
          nbotMethods,
          eventAddr,
          amt: threshold,
          resultIndex: 1,
          from: OWNER,
        })
        assert.equal(await eventMethods.currentResultIndex().call(), 1)
        assert.equal(await eventMethods.currentRound().call(), 1)
        assert.isBelow(
          await currentBlockTime(),
          Number(await eventMethods.currentArbitrationEndTime().call()))
      })

      it('allows voting', async () => {
        let amt = 1
        await placeVote({
          nbotMethods,
          eventAddr,
          amtDecimals: amt,
          resultIndex: 2,
          from: ACCT1,
        })
        let totalBets = toBN(threshold).add(toSatoshi(amt))
        sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

        amt = 2
        await placeVote({
          nbotMethods,
          eventAddr,
          amtDecimals: amt,
          resultIndex: 2,
          from: ACCT2,
        })
        totalBets = totalBets.add(toSatoshi(amt))
        sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      })

      it('sets the result if voting to the threshold', async () => {
        const amt = await eventMethods.currentConsensusThreshold().call()
        await placeVote({
          nbotMethods,
          eventAddr,
          amtSatoshi: amt,
          resultIndex: 2,
          from: ACCT1,
        })
        let totalBets = toBN(threshold).add(toBN(amt))
        sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
        assert.equal(await eventMethods.currentResultIndex().call(), 2)
        assert.equal(await eventMethods.currentRound().call(), 2)
      })

      it('refunds the diff over the threshold', async () => {
        const balance = toBN(await nbotMethods.balanceOf(ACCT1).call())
        const amt = toBN(await eventMethods.currentConsensusThreshold().call())
        const diff = toSatoshi(25)
        await placeVote({
          nbotMethods,
          eventAddr,
          amtSatoshi: amt.add(diff).toString(),
          resultIndex: 2,
          from: ACCT1,
        })
        sassert.bnEqual(
          await eventMethods.totalBets().call(),
          toBN(threshold).add(amt))
        assert.equal(await eventMethods.currentResultIndex().call(), 2)
        assert.equal(await eventMethods.currentRound().call(), 2)
        sassert.bnEqual(await nbotMethods.balanceOf(ACCT1).call(), balance.sub(amt))
      })

      it('throws if the resultIndex is invalid', async () => {
        try {
          await placeVote({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 4,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'resultIndex is not valid')
        }
      })

      it('throws if the current time is past the arbitrationEndTime', async () => {
        const currTime = await currentBlockTime()
        const arbEndTime = Number(await eventMethods.currentArbitrationEndTime().call())
        await timeMachine.increaseTime(arbEndTime - currTime)
        assert.isAtLeast(await currentBlockTime(), arbEndTime)

        try {
          await placeVote({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 2,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'Current time should be < arbitrationEndTime')
        }
      })

      it('throws if voting on the last result index', async () => {
        assert.equal(await eventMethods.currentResultIndex().call(), 1)

        try {
          await placeVote({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 1,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'Cannot vote on the last result index')
        }
      })

      it('throws if the vote amount is 0', async () => {
        try {
          await placeVote({
            nbotMethods,
            eventAddr,
            amtDecimals: 0,
            resultIndex: 2,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'Vote amount should be > 0')
        }
      })
    })

    describe('invalid time', () => {
      it('throws if trying to vote in round 0', async () => {
        assert.equal(await eventMethods.currentRound().call(), 0)

        try {
          await placeVote({
            nbotMethods,
            eventAddr,
            amtDecimals: 1,
            resultIndex: 1,
            from: ACCT1,
          })
        } catch (e) {
          sassert.revert(e, 'Can only vote after the betting round')
        }
      })
    })
  })

  describe('withdraw()', () => {
    it('withdraws the winning amount', async () => {
      const cOracleResult = 1
      let totalBets

      // Advance to betting time
      let currTime = await currentBlockTime()
      await timeMachine.increaseTime(betStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), betStartTime)
      assert.isBelow(await currentBlockTime(), betEndTime)

      // First round of betting
      const bet1 = toSatoshi(100)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet1.toString(),
        resultIndex: 1,
        from: ACCT1,
      })
      totalBets = bet1
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet2 = toSatoshi(100)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet2.toString(),
        resultIndex: 2,
        from: ACCT2,
      })
      totalBets = totalBets.add(bet2)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      // Advance to result setting time
      currTime = await currentBlockTime()
      await timeMachine.increaseTime(resultSetStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

      // Set result 2
      const cOracleThreshold =
        toBN(await eventMethods.currentConsensusThreshold().call())
      await setResult({
        nbotMethods,
        eventAddr,
        amt: cOracleThreshold.toString(),
        resultIndex: cOracleResult,
        from: OWNER,
      })
      totalBets = totalBets.add(cOracleThreshold)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      assert.equal(await eventMethods.currentResultIndex().call(), cOracleResult)
      assert.equal(await eventMethods.currentRound().call(), 1)

      // Advance to arbitration end time
      currTime = await currentBlockTime()
      const arbEndTime = Number(await eventMethods.currentArbitrationEndTime().call())
      await timeMachine.increaseTime(arbEndTime - currTime)
      assert.isAtLeast(await currentBlockTime(), arbEndTime)

      let balance = toBN(await nbotMethods.balanceOf(eventAddr).call())

      // ACCT1 winner withdraws
      let winningAmt = toBN(await eventMethods.calculateWinnings(ACCT1).call())
      assert.isTrue(winningAmt.toNumber() > 0)
      let receipt = await eventMethods.withdraw().send({ from: ACCT1, gas: 200000 })
      sassert.event(receipt, 'WinningsWithdrawn')
      assert.isTrue(await eventMethods.didWithdraw(ACCT1).call())
      sassert.bnEqual(
        await nbotMethods.balanceOf(eventAddr).call(),
        balance.sub(winningAmt))
      balance = balance.sub(winningAmt)

      // OWNER winner withdraws winning amount and escrow
      const ownerBal = toBN(await nbotMethods.balanceOf(OWNER).call())
      winningAmt = toBN(await eventMethods.calculateWinnings(OWNER).call())
      assert.isTrue(winningAmt.toNumber() > 0)
      receipt = await eventMethods.withdraw().send({ from: OWNER, gas: 200000 })
      sassert.event(receipt, 'WinningsWithdrawn')
      assert.isTrue(await eventMethods.didWithdraw(OWNER).call())
      sassert.bnEqual(
        await nbotMethods.balanceOf(eventAddr).call(),
        balance.sub(winningAmt))
      sassert.bnEqual(
        await nbotMethods.balanceOf(OWNER).call(),
        ownerBal.add(winningAmt).add(toBN(escrowAmt)))

      // Contract should be empty
      assert.equal(await nbotMethods.balanceOf(eventAddr).call(), 0)
    })

    it('throws if trying to withdraw during round 0', async () => {
      assert.equal(await eventMethods.currentRound().call(), 0)

      try {
        await eventMethods.withdraw().send({ from: OWNER, gas: 200000 })
      } catch (e) {
        sassert.revert(e, 'Cannot withdraw during betting round.')
      }
    })

    it('throws if trying to withdraw before the arbitrationEndTime', async () => {
      // Advance to result setting time
      let currTime = await currentBlockTime()
      await timeMachine.increaseTime(resultSetStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

      // Set result
      const cOracleThreshold =
        toBN(await eventMethods.currentConsensusThreshold().call())
      await setResult({
        nbotMethods,
        eventAddr,
        amt: cOracleThreshold.toString(),
        resultIndex: 1,
        from: OWNER,
      })
      assert.equal(await eventMethods.currentResultIndex().call(), 1)
      assert.equal(await eventMethods.currentRound().call(), 1)

      // Check if under arb end time
      const arbEndTime = Number(await eventMethods.currentArbitrationEndTime().call())
      assert.isBelow(await currentBlockTime(), arbEndTime)

      try {
        await eventMethods.withdraw().send({ from: OWNER, gas: 200000 })
      } catch (e) {
        sassert.revert(e, 'Current time should be >= arbitrationEndTime')
      }
    })

    it('throws if trying to withdraw more than once', async () => {
      // Advance to result setting time
      let currTime = await currentBlockTime()
      await timeMachine.increaseTime(resultSetStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

      // Set result
      const cOracleThreshold =
        toBN(await eventMethods.currentConsensusThreshold().call())
      await setResult({
        nbotMethods,
        eventAddr,
        amt: cOracleThreshold.toString(),
        resultIndex: 1,
        from: OWNER,
      })
      assert.equal(await eventMethods.currentResultIndex().call(), 1)
      assert.equal(await eventMethods.currentRound().call(), 1)

      // Advance to arbitration end time
      currTime = await currentBlockTime()
      const arbEndTime = Number(await eventMethods.currentArbitrationEndTime().call())
      await timeMachine.increaseTime(arbEndTime - currTime)
      assert.isAtLeast(await currentBlockTime(), arbEndTime)

      // Withdraw once
      await eventMethods.withdraw().send({ from: OWNER, gas: 200000 })
      assert.isTrue(await eventMethods.didWithdraw(OWNER).call())

      try {
        await eventMethods.withdraw().send({ from: OWNER, gas: 200000 })
      } catch (e) {
        sassert.revert(e, 'Already withdrawn')
      }
    })
  })

  describe('calculateWinnings', () => {
    it('returns the amount for a non-invalid result', async () => {
      const cOracleResult = 2
      const dOracle1Result = 0
      const dOracle2Result = 2
      let totalBets

      // Advance to betting time
      let currTime = await currentBlockTime()
      await timeMachine.increaseTime(betStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), betStartTime)
      assert.isBelow(await currentBlockTime(), betEndTime)

      // First round of betting
      const bet1 = toSatoshi(12)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet1.toString(),
        resultIndex: 0,
        from: ACCT1,
      })
      totalBets = bet1
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet2 = toSatoshi(23)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet2.toString(),
        resultIndex: 1,
        from: ACCT2,
      })
      totalBets = totalBets.add(bet2)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet3 = toSatoshi(30)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet3.toString(),
        resultIndex: cOracleResult,
        from: ACCT3,
      })
      totalBets = totalBets.add(bet3)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet4 = toSatoshi(12)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet4.toString(),
        resultIndex: cOracleResult,
        from: ACCT4,
      })
      totalBets = totalBets.add(bet4)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      // Advance to result setting time
      currTime = await currentBlockTime()
      await timeMachine.increaseTime(resultSetStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

      // Set result 2
      const cOracleThreshold =
        toBN(await eventMethods.currentConsensusThreshold().call())
      await setResult({
        nbotMethods,
        eventAddr,
        amt: cOracleThreshold.toString(),
        resultIndex: cOracleResult,
        from: OWNER,
      })
      totalBets = totalBets.add(cOracleThreshold)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      assert.equal(await eventMethods.currentResultIndex().call(), cOracleResult)
      assert.equal(await eventMethods.currentRound().call(), 1)

      // dOracle1 voting. Threshold hits and result becomes 0.
      const vote1a = toSatoshi(60)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote1a.toString(),
        resultIndex: dOracle1Result,
        from: ACCT1,
      })
      totalBets = totalBets.add(vote1a)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const vote2a = toSatoshi(50)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote2a.toString(),
        resultIndex: dOracle1Result,
        from: ACCT2,
      })
      totalBets = totalBets.add(vote2a)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      assert.equal(await eventMethods.currentResultIndex().call(), dOracle1Result)
      assert.equal(await eventMethods.currentRound().call(), 2)

      // dOracle2 voting. Threshold hits and result becomes 2.
      const vote3a = toSatoshi(41)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote3a.toString(),
        resultIndex: dOracle2Result,
        from: ACCT3,
      })
      totalBets = totalBets.add(vote3a)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const vote4a = toSatoshi(43)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote4a.toString(),
        resultIndex: dOracle2Result,
        from: ACCT4,
      })
      totalBets = totalBets.add(vote4a)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const vote5a = toSatoshi(37)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote5a.toString(),
        resultIndex: dOracle2Result,
        from: ACCT5,
      })
      totalBets = totalBets.add(vote5a)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      assert.equal(await eventMethods.currentResultIndex().call(), dOracle2Result)
      assert.equal(await eventMethods.currentRound().call(), 3)

      // dOracle3 voting. Does not hit threshold and result gets finalized to 2.
      const vote1b = toSatoshi(53)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote1b.toString(),
        resultIndex: dOracle1Result,
        from: ACCT1,
      })
      totalBets = totalBets.add(vote1b)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const vote2b = toSatoshi(49)
      await placeVote({
        nbotMethods,
        eventAddr,
        amtSatoshi: vote2b.toString(),
        resultIndex: dOracle1Result,
        from: ACCT2,
      })
      totalBets = totalBets.add(vote2b)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      // Advance to arbitration end time
      currTime = await currentBlockTime()
      const arbEndTime = Number(await eventMethods.currentArbitrationEndTime().call())
      await timeMachine.increaseTime(arbEndTime - currTime)
      assert.isAtLeast(await currentBlockTime(), arbEndTime)

      // Withdraw winnings: ACCT3, ACCT4, ACCT5, ORACLE
      const maxPercent = toBN(100)
      const arbRewardPercent = toBN((await eventMethods.configMetadata().call())[3])
      const arbRewardPercentComp = maxPercent.sub(arbRewardPercent)
      const betRoundWinnersTotal = bet3.add(bet4)
      const betRoundLosersTotal = bet1.add(bet2)
      const voteRoundsWinnersTotal = cOracleThreshold.add(vote3a).add(vote4a).add(vote5a)
      const voteRoundsLosersTotal = vote1a.add(vote2a).add(vote1b).add(vote2b)
      const calcParams = {
        maxPercent,
        arbRewardPercent,
        arbRewardPercentComp,
        betRoundWinnersTotal,
        betRoundLosersTotal,
        voteRoundsWinnersTotal,
        voteRoundsLosersTotal,
      }

      // ACCT3 winner
      let myWinningBets = bet3
      let myWinningVotes = vote3a
      let winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT3).call(), winningAmt)

      // ACCT4 winner
      myWinningBets = bet4
      myWinningVotes = vote4a
      winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT4).call(), winningAmt)

      // ACCT5 winner
      myWinningBets = toBN(0)
      myWinningVotes = vote5a
      winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT5).call(), winningAmt)

      // CentralizedOracle winner
      myWinningBets = toBN(0)
      myWinningVotes = cOracleThreshold
      winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(OWNER).call(), winningAmt)

      // ACCT1 loser
      myWinningBets = toBN(0)
      myWinningVotes = toBN(0)
      winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT1).call(), winningAmt)

      // ACCT2 loser
      myWinningBets = toBN(0)
      myWinningVotes = toBN(0)
      winningAmt = calculateNormalWinnings({
        myWinningBets,
        myWinningVotes,
        ...calcParams,
      })
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT2).call(), winningAmt)
    })

    it('returns the amount for an invalid result', async () => {
      const cOracleResult = 0
      let totalBets

      // Advance to betting time
      let currTime = await currentBlockTime()
      await timeMachine.increaseTime(betStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), betStartTime)
      assert.isBelow(await currentBlockTime(), betEndTime)

      // First round of betting
      const bet1 = toSatoshi(12)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet1.toString(),
        resultIndex: 0,
        from: ACCT1,
      })
      totalBets = bet1
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet2 = toSatoshi(23)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet2.toString(),
        resultIndex: 1,
        from: ACCT2,
      })
      totalBets = totalBets.add(bet2)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet3 = toSatoshi(30)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet3.toString(),
        resultIndex: cOracleResult,
        from: ACCT3,
      })
      totalBets = totalBets.add(bet3)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      const bet4 = toSatoshi(12)
      await placeBet({
        nbotMethods,
        eventAddr,
        amtSatoshi: bet4.toString(),
        resultIndex: cOracleResult,
        from: ACCT4,
      })
      totalBets = totalBets.add(bet4)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)

      // Advance to result setting time
      currTime = await currentBlockTime()
      await timeMachine.increaseTime(resultSetStartTime - currTime)
      assert.isAtLeast(await currentBlockTime(), resultSetStartTime)

      // Set result 2
      const cOracleThreshold =
        toBN(await eventMethods.currentConsensusThreshold().call())
      await setResult({
        nbotMethods,
        eventAddr,
        amt: cOracleThreshold.toString(),
        resultIndex: cOracleResult,
        from: OWNER,
      })
      totalBets = totalBets.add(cOracleThreshold)
      sassert.bnEqual(await eventMethods.totalBets().call(), totalBets)
      assert.equal(await eventMethods.currentResultIndex().call(), cOracleResult)
      assert.equal(await eventMethods.currentRound().call(), 1)

      // ACCT1 should get all their bets back
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT1).call(), bet1)

      // ACCT2 should get all their bets back
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT2).call(), bet2)

      // ACCT3 should get all their bets back
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT3).call(), bet3)

      // ACCT4 should get all their bets back
      sassert.bnEqual(await eventMethods.calculateWinnings(ACCT4).call(), bet4)
    })

    it('returns 0 if currentResultIndex is invalid', async () => {
      assert.equal(
        await eventMethods.currentResultIndex().call(),
        RESULT_INDEX_INVALID)
      sassert.bnEqual(await eventMethods.calculateWinnings(OWNER).call(), 0)
    })
  })
})
