
const PriceFeed = artifacts.require("./PriceFeedTester.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const MockChainlink = artifacts.require("./MockAggregator.sol")
const MockTellor = artifacts.require("./MockTellor.sol")
const TellorCaller = artifacts.require("./TellorCaller.sol")
const GovernorTester = artifacts.require("./GovernorTester.sol");

const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper

const { dec, assertRevert, toBN } = th

contract('PriceFeed', async accounts => {

  const [owner, alice] = accounts;
  const normalEbtcPrice = dec(7428, 13);
  const decreasedEbtcPrice = dec(5000, 13);
  let priceFeedTestnet
  let priceFeed
  let zeroAddressPriceFeed
  let mockChainlink

  const setAddresses = async () => {
    // Using tellorCaller as authority as we're not testing governance function
    await priceFeed.setAddresses(mockChainlink.address, tellorCaller.address, tellorCaller.address, { from: owner })
  }

  beforeEach(async () => {
    priceFeedTestnet = await PriceFeedTestnet.new()
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet)

    priceFeed = await PriceFeed.new()
    PriceFeed.setAsDeployed(priceFeed)

    zeroAddressPriceFeed = await PriceFeed.new()
    PriceFeed.setAsDeployed(zeroAddressPriceFeed)

    mockChainlink = await MockChainlink.new()
    MockChainlink.setAsDeployed(mockChainlink)

    mockTellor = await MockTellor.new()
    MockTellor.setAsDeployed(mockTellor)

    tellorCaller = await TellorCaller.new(mockTellor.address)
    TellorCaller.setAsDeployed(tellorCaller)

    // Set Chainlink latest and prev round Id's to non-zero
    await mockChainlink.setLatestRoundId(3)
    await mockChainlink.setPrevRoundId(2)

    //Set current and prev prices in both oracles
    await mockChainlink.setPrice(dec(100, 18))
    await mockChainlink.setPrevPrice(dec(100, 18))
    await mockTellor.setPrice(normalEbtcPrice)

    // Set mock price updateTimes in both oracles to very recent
    const now = await th.getLatestBlockTimestamp(web3)
    await mockChainlink.setUpdateTime(now)
    await mockTellor.setUpdateTime(now)
  })

  describe('PriceFeed internal testing contract', async accounts => {
    it("fetchPrice before setPrice should return the default price", async () => {
      const price = await priceFeedTestnet.getPrice()
      assert.equal(price, normalEbtcPrice)
    })
    it("should be able to fetchPrice after setPrice, output of former matching input of latter", async () => {
      await priceFeedTestnet.setPrice(dec(100, 18))
      const price = await priceFeedTestnet.getPrice()
      assert.equal(price, dec(100, 18))
    })
  })

  describe('Mainnet PriceFeed setup', async accounts => {
    it("fetchPrice should fail on contract with no chainlink address set", async () => {
      try {
        const price = await zeroAddressPriceFeed.fetchPrice()
        assert.isFalse(price.receipt.status)
      } catch (err) {
        console.log(err)
        console.log(err.message)
        assert.include(err.message, "function returned an unexpected amount of data") 
      }
    })

    it("fetchPrice should fail on contract with no tellor address set", async () => {
      try {
        const price = await zeroAddressPriceFeed.fetchPrice()
        assert.isFalse(price.receipt.status)
      } catch (err) {
        console.log(err)
        console.log(err.message)
        assert.include(err.message, "function returned an unexpected amount of data")
      }
    })

    it("setAddresses should fail whe called by nonOwner", async () => {
      await assertRevert(
        priceFeed.setAddresses(mockChainlink.address, mockTellor.address, mockTellor.address, { from: alice }),
        "Ownable: caller is not the owner"
      )
    })

    it("setAddresses should fail after address has already been set", async () => {
      // Owner can successfully set any address
      const txOwner = await priceFeed.setAddresses(mockChainlink.address, mockTellor.address, mockTellor.address, { from: owner })
      assert.isTrue(txOwner.receipt.status)

      await assertRevert(
        priceFeed.setAddresses(mockChainlink.address, mockTellor.address, mockTellor.address, { from: owner }),
        "Ownable: caller is not the owner"
      )

      await assertRevert(
        priceFeed.setAddresses(mockChainlink.address, mockTellor.address, mockTellor.address, { from: alice }),
        "Ownable: caller is not the owner"
      )
    })
  })

  it("C1 Chainlink working: fetchPrice should return the correct price, taking into account the number of decimal digits on the aggregator", async () => {
    await setAddresses()

    // Oracle price price is 10.00000000
    await mockChainlink.setDecimals(8)
    await mockChainlink.setPrevPrice(dec(1, 9))
    await mockChainlink.setPrice(dec(1, 9))
    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    // Check Liquity PriceFeed gives 10, with 18 digit precision
    assert.equal(price, dec(10, 18))

    // Oracle price is 1e9
    await mockChainlink.setDecimals(0)
    await mockChainlink.setPrevPrice(dec(1, 9))
    await mockChainlink.setPrice(dec(1, 9))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Liquity PriceFeed gives 1e9, with 18 digit precision
    assert.isTrue(price.eq(toBN(dec(1, 27))))

    // Oracle price is 0.0001
    await mockChainlink.setDecimals(18)
    const decimals = await mockChainlink.decimals()

    await mockChainlink.setPrevPrice(dec(1, 14))
    await mockChainlink.setPrice(dec(1, 14))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision
    assert.isTrue(price.eq(toBN(dec(1, 14))))

    // Oracle price is 1234.56789
    await mockChainlink.setDecimals(5)
    await mockChainlink.setPrevPrice(dec(123456789))
    await mockChainlink.setPrice(dec(123456789))
    await priceFeed.fetchPrice()
    price = await priceFeed.lastGoodPrice()
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision
    assert.equal(price, '1234567890000000000000')
  })

  // --- Chainlink breaks ---

  it("C1 chainlinkWorking: Chainlink broken by zero latest roundId, Tellor working: switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setLatestRoundId(0)

    await priceFeed.fetchPrice()
    await priceFeed.lastGoodPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink broken by zero latest roundId, Tellor working: use Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setLatestRoundId(0)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink broken by zero timestamp, Tellor working, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setUpdateTime(0)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking:  Chainlink broken by zero timestamp, Tellor working, return Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setUpdateTime(0)

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink broken by future timestamp, Tellor working, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    const now = await th.getLatestBlockTimestamp(web3)
    const future = toBN(now).add(toBN('1000'))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setUpdateTime(future)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink broken by future timestamp, Tellor working, return Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    const now = await th.getLatestBlockTimestamp(web3)
    const future = toBN(now).add(toBN('1000'))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setUpdateTime(future)

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink broken by negative price, Tellor working,  switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrice("-5000")

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink broken by negative price, Tellor working, return Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrice("-5000")

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })


  it("C1 chainlinkWorking: Chainlink broken - decimals call reverted, Tellor working, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setDecimalsRevert()

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink broken - decimals call reverted, Tellor working, return Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setDecimalsRevert()

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink broken - latest round call reverted, Tellor working, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setLatestRevert()

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: latest round call reverted, Tellor working, return the Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setLatestRevert()

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: previous round call reverted, Tellor working, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevRevert()

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: previous round call reverted, Tellor working, return Tellor Price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevRevert()

    await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  // --- Chainlink timeout ---

  it("C1 chainlinkWorking: Chainlink frozen, Tellor working: switch to usingTellorChainlinkFrozen", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours
    const now = await th.getLatestBlockTimestamp(web3)

    // Tellor price is recent
    await mockTellor.setUpdateTime(now)
    await mockTellor.setPrice(normalEbtcPrice)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '3') // status 3: using Tellor, Chainlink frozen 
  })

  it("C1 chainlinkWorking: Chainlink frozen, Tellor working: return Tellor price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    // Tellor price is recent
    await mockTellor.setUpdateTime(now)
    await mockTellor.setPrice(normalEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink frozen, Tellor frozen: switch to usingTellorChainlinkFrozen", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '3') // status 3: using Tellor, Chainlink frozen
  })

  it("C1 chainlinkWorking: Chainlink frozen, Tellor frozen: return last good price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await mockTellor.setPrice(normalEbtcPrice)

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '3') // status 3: using Tellor, Chainlink frozen
  })

  it("C1 chainlinkWorking: Chainlink times out, Tellor broken by 0 price: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // Tellor breaks by 0 price
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 4: using Chainlink, Tellor untrusted
  })

  it("C1 chainlinkWorking: Chainlink times out, Tellor broken by 0 price: return last good price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await priceFeed.setLastGoodPrice(dec(999, 18))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    await mockTellor.setPrice(dec(0))

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 3: using chainlink; tellor untrusted
  })

  it("C1 chainlinkWorking: Chainlink is out of date by <3hrs: remain chainlinkWorking", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1234, 8))
    await mockChainlink.setPrice(dec(1234, 8))
    await th.fastForwardTime(10740, web3.currentProvider) // fast forward 2hrs 59 minutes 

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink is out of date by <3hrs: return Chainklink price", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    const decimals = await mockChainlink.decimals()

    await mockChainlink.setPrevPrice(dec(1234, 8))
    await mockChainlink.setPrice(dec(1234, 8))
    await th.fastForwardTime(10740, web3.currentProvider) // fast forward 2hrs 59 minutes

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(1234, 18))
  })

  // --- Chainlink price deviation ---

  it("C1 chainlinkWorking: Chainlink price drop of >50%, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(normalEbtcPrice)

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50%, return the Tellor price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(normalEbtcPrice)

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink price drop of 50%, remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(1, 8))  // price drops to 1

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price drop of 50%, return the Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(1, 8))  // price drops to 1

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(1, 18))
  })

  it("C1 chainlinkWorking: Chainlink price drop of <50%, remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(100000001))   // price drops to 1.00000001:  a drop of < 50% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price drop of <50%, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(100000001)   // price drops to 1.00000001:  a drop of < 50% from previous

    const priceFetchTx = await priceFeed.fetchPrice()

    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(100000001, 10))
  })

  // Price increase
  it("C1 chainlinkWorking: Chainlink price increase of >100%, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(400000001)  // price increases to 4.000000001: an increase of > 100% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink price increase of >100%, return Tellor price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(400000001)  // price increases to 4.000000001: an increase of > 100% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink price increase of 100%, remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(4, 8))  // price increases to 4: an increase of 100% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price increase of 100%, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(dec(4, 8))  // price increases to 4: an increase of 100% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(4, 18))
  })

  it("C1 chainlinkWorking: Chainlink price increase of <100%, remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(399999999)  // price increases to 3.99999999: an increase of < 100% from previous

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price increase of <100%,  return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(normalEbtcPrice)
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(399999999)  // price increases to 3.99999999: an increase of < 100% from previous

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(399999999, 10))
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price matches: remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(normalEbtcPrice)

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(normalEbtcPrice)
    await mockChainlink.setPrice(normalEbtcPrice)
    await mockTellor.setPrice(normalEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price matches: return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(7018000)  // price drops to 0.99999999: a drop of > 50% from previous
    await mockTellor.setPrice(normalEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  xit("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price within 5% of Chainlink: remain chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))
   
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(104999999) // Tellor price drops to 104.99: price difference with new Chainlink price is now just under 5%

    const priceFetchTx = await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price within 5% of Chainlink: return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(2, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(normalEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, normalEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor live but not within 5% of Chainlink: switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(normalEbtcPrice)

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    // Tellor price drops to 105.000001: price difference with new Chainlink price is now > 5%
    await mockTellor.setPrice(decreasedEbtcPrice)

    await priceFeed.fetchPrice()
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor live but not within 5% of Chainlink: return Tellor price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(normalEbtcPrice)

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(decreasedEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()
    assert.equal(price, decreasedEbtcPrice)
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor frozen: switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(decreasedEbtcPrice)

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider)

     // check Tellor price timestamp is out of date by > 4 hours
     const now = await th.getLatestBlockTimestamp(web3)
     const tellorUpdateTime = await mockTellor.getUpdateTime()
     assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

     await mockChainlink.setUpdateTime(now)

    await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor frozen: return last good price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(1000, 8))  // prev price = 1000
    await mockChainlink.setPrice(dec(100, 8))  // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(decreasedEbtcPrice)

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider)

     // check Tellor price timestamp is out of date by > 4 hours
     const now = await th.getLatestBlockTimestamp(web3)
     const tellorUpdateTime = await mockTellor.getUpdateTime()
     assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

     await mockChainlink.setUpdateTime(now)
     await priceFeed.fetchPrice()
     let price = await priceFeed.lastGoodPrice()

     // Check that the returned price is the last good price
     assert.equal(price, dec(1200, 18))
  })

  // --- Chainlink fails and Tellor is broken ---

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 price: switch to bothOracleSuspect", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    await mockTellor.setPrice(0)  // Tellor price drops to 0

    const priceFetchTx = await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 price: return last good price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 price
    await mockTellor.setPrice(0)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 timestamp: switch to bothOracleSuspect", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0)
    const priceFetchTx = await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 timestamp: return last good price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(decreasedEbtcPrice)

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2')  // status 2: both oracles untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by future timestamp: Pricefeed switches to bothOracleSuspect", async () => {
    await setAddresses()
    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0)

    const priceFetchTx = await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by future timestamp: return last good price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockTellor.setPrice(decreasedEbtcPrice)

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrevPrice(dec(2, 8))  // price = 2
    await mockChainlink.setPrice(99999999)  // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return a future timestamp
    const now = await th.getLatestBlockTimestamp(web3)
    const future = toBN(now).add(toBN("10000"))
    await mockTellor.setUpdateTime(future)

    await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is in fact the previous price
    assert.equal(price, dec(1200, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  // -- Chainlink is working
  it("C1 chainlinkWorking: Chainlink is working and Tellor is working - remain on chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(decreasedEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor is working - return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(decreasedEbtcPrice)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current Chainlink price
    assert.equal(price, dec(102, 18))
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor freezes - remain on chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(decreasedEbtcPrice)

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider)

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now) // Chainlink's price is current

    const priceFetchTx = await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '0') // status 0: Chainlink working
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor freezes - return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18))

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(decreasedEbtcPrice)

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider)

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now) // Chainlink's price is current

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current Chainlink price
    assert.equal(price, dec(102, 18))
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor breaks: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 4: Using Chainlink, Tellor untrusted
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor breaks with ifRetrieve = false: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(7413, 13))
    await mockChainlink.setPrice(dec(7413, 13))

    await mockTellor.setPrice(decreasedEbtcPrice)
    await mockTellor.setRevertRequest()
    await priceFeed.fetchPrice()

    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 4: // status 4: Using Chainlink, Tellor untrusted
  })

  it("C1 chainlinkWorking: Chainlink is working and Tellor breaks: return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status()
    assert.equal(statusBefore, '0') // status 0: Chainlink working

    await mockChainlink.setPrevPrice(dec(101, 8))
    await mockChainlink.setPrice(dec(102, 8))

    await mockTellor.setPrice(0)

    const priceFetchTx = await priceFeed.fetchPrice()
    let price = await priceFeed.lastGoodPrice()

    // Check that the returned price is current Chainlink price
    assert.equal(price, dec(102, 18))
  })

  // --- Case 2: Using Tellor ---

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero price: switch to bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await priceFeed.setLastGoodPrice(dec(123, 18))

    const now = await th.getLatestBlockTimestamp(web3)
    await mockTellor.setUpdateTime(now)
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero price: return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await priceFeed.setLastGoodPrice(dec(123, 18))

    const now = await th.getLatestBlockTimestamp(web3)
    await mockTellor.setUpdateTime(now)
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '123000000000000000000')
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by call reverted: switch to bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(dec(123, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await mockTellor.setPrice(decreasedEbtcPrice)

    await mockTellor.setRevertRequest()

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by call reverted: return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(dec(123, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await mockTellor.setPrice(decreasedEbtcPrice)

    await mockTellor.setRevertRequest()

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()

    assert.equal(price, '123000000000000000000')
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero timestamp: switch to bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(dec(123, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await mockTellor.setPrice(decreasedEbtcPrice)

    await mockTellor.setUpdateTime(0)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero timestamp: return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(dec(123, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))
    await mockTellor.setPrice(decreasedEbtcPrice)

    await mockTellor.setUpdateTime(0)

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()

    assert.equal(price, '123000000000000000000')
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  // Using Tellor, Tellor freezes
  it("C2 usingTellorChainlinkUntrusted: Tellor freezes - remain usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockTellor.setPrice(decreasedEbtcPrice)

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: using Tellor, Chainlink untrusted
  })

  it("C2 usingTellorChainlinkUntrusted: Tellor freezes - return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockTellor.setPrice(decreasedEbtcPrice)

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now)

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()

    assert.equal(price, dec(246, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  // Using Tellor, both Chainlink & Tellor go live

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and <= 5% price difference - switch to chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(7000, 13))
    await mockChainlink.setPrice('7022067') // price = 105: 5% difference from Chainlink

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 0)  // status 0: Chainlink working
  })

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and <= 5% price difference - return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(7000, 13))
    await mockChainlink.setPrice('7022067') // price = 105: 5% difference from Chainlink

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '70220670000000000')
  })

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and > 5% price difference - remain usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(decreasedEbtcPrice)
    await mockChainlink.setPrice('7522067')

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: using Tellor, Chainlink untrusted
  })

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and > 5% price difference - return Tellor price", async () => {
    await setAddresses()
    priceFeed.setStatus(1) // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(decreasedEbtcPrice)
    await mockChainlink.setPrice('7522067')

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    // Tellor price
    assert.equal(price, decreasedEbtcPrice)
  })

  it("C2 usingTellorChainlinkUntrusted: Tellor frozen with stale data while chainlink break", async () => {
    await setAddresses()
    priceFeed.setStatus(0) // status 0: Chainlink working

    await priceFeed.setLastGoodPrice(dec(999, 18))
    let _p = await priceFeed.lastGoodPrice()

    await mockChainlink.setPrice(0)

    await mockTellor.setUpdateTime(1)
    await mockTellor.setPrice(decreasedEbtcPrice)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: using Tellor, Chainlink untrusted
  })


  // --- Case 3: Both Oracles suspect

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and > 5% price difference remain bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(2) // status 2: both oracles untrusted

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockTellor.setPrice(decreasedEbtcPrice)
    await mockChainlink.setPrice('7522067')

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and > 5% price difference, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(2) // status 2: both oracles untrusted

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockTellor.setPrice(decreasedEbtcPrice)
    await mockChainlink.setPrice('7522067')

    await priceFeed.fetchPrice()
    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(50, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and <= 5% price difference, switch to chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setStatus(2) // status 2: both oracles untrusted

    await mockTellor.setPrice(dec(7000, 13))
    await mockChainlink.setPrice('7022067')

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 0)  // status 0: Chainlink working
  })

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and <= 5% price difference, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(2) // status 2: both oracles untrusted

    await mockTellor.setPrice(dec(7000, 13))
    await mockChainlink.setPrice('7022067')

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '70220670000000000')
  })

  // --- Case 4 ---
  it("C4 usingTellorChainlinkFrozen: when both Chainlink and Tellor break, switch to bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Both Chainlink and Tellor break with 0 price
    await mockChainlink.setPrice(0)
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when both Chainlink and Tellor break, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(2) // status 2: using tellor, chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Both Chainlink and Tellor break with 0 price
    await mockChainlink.setPrice(dec(0))
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(50, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor freezes, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0))

    await mockTellor.setPrice(decreasedEbtcPrice)

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: using Tellor, Chainlink untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor freezes, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0))

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(50, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '1') // status 1: using Tellor, Chainlink untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor live, switch to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0))

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: using Tellor, Chainlink untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor live, return Tellor price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0))

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(7000, 13))
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with <5% price difference, switch back to chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 0)  // status 0: Chainlink working
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with <5% price difference, return Chainlink current price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '70220670000000000')  // Chainlink price
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with >5% price difference, switch back to usingTellorChainlinkUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7522067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 1)  // status 1: Using Tellor, Chainlink untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with >5% price difference, return Chainlink current price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7522067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(7000, 13))  // Tellor price
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with similar price, switch back to chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 0)  // status 0: Chainlink working
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with similar price, return Chainlink current price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '70220670000000000')  // Chainlink price
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor breaks, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)  // status 4: Using Chainlink, Tellor untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor breaks, return Chainlink current price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '70220670000000000')
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor breaks, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    // set tellor broken
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)  // status 4: using Chainlink, Tellor untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor broken, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    // set tellor broken
    await mockTellor.setPrice(0)

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(50, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 4: using Chainlink, Tellor untrusted
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor live, remain usingTellorChainlinkFrozen", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    // set Tellor to current time
    await mockTellor.setUpdateTime(now)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 3)  // status 3: using Tellor, Chainlink frozen
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor live, return Tellor price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec('7032067'))
    await mockChainlink.setPrice('7022067')

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    // set Tellor to current time
    await mockTellor.setUpdateTime(now)

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(7000, 13))
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor freezes, remain usingTellorChainlinkFrozen", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

     // check Tellor price timestamp is out of date by > 4 hours
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 3)  // status 3: using Tellor, Chainlink frozen
  })

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor freezes, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(dec(50, 18))

    await mockChainlink.setPrevPrice(dec(999, 8))
    await mockChainlink.setPrice(dec(999, 8))

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

     // check Tellor price timestamp is out of date by > 4 hours
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(50, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '3') // status 3: using Tellor, Chainlink frozen
  })

  it("C4 usingTellorChainlinkFrozen: Tellor frozen with stale data while chainlink is live, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(3) // status 3: using Tellor, Chainlink frozen

    const now = await th.getLatestBlockTimestamp(web3)
    await mockChainlink.setUpdateTime(now) // Chainlink is current
    await mockChainlink.setPrevPrice(dec(1234, 8))
    await mockChainlink.setPrice(dec(1234, 8))
    await priceFeed.setLastGoodPrice(dec(1234, 18))
    let _p = await priceFeed.lastGoodPrice()

    await mockTellor.setUpdateTime(1)
    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 3)  // status 3: no change
    assert.equal(toBN((await priceFeed.lastGoodPrice()).toString()).toString(), toBN(_p.toString()).toString());
  })

  // --- Case 5 ---
  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price >5% - no status change", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(decreasedEbtcPrice)

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)  // status 4: using Chainlink, Tellor untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price >5% - return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(decreasedEbtcPrice)

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '74220670000000000')
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price within <5%, switch to chainlinkWorking", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(dec(7500, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 0)  // status 0: Chainlink working
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '74220670000000000')
  })

  // ---------

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor price not within 5%, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(dec(1000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)  // status 4: using Chainlink, Tellor untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7422067')

    await mockTellor.setPrice(dec(1000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '74220670000000000')
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor price not within 5%, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(normalEbtcPrice)

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5022067')
    await mockTellor.setPrice(dec(10000, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous,  Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')
    await mockTellor.setPrice(dec(7000, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    console.log(price.toString())
    assert.equal(price, '50320670000000000') // last good price
  })

  // -------

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, and Tellor is frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice('74320670000000000')

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setUpdateTime(now) // Chainlink is current

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4)  // status 4: using Chainlink, Tellor untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor is frozen, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setPrice(dec('7432067'))
    await mockChainlink.setUpdateTime(now) // Chainlink is current

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, '74320670000000000')
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor is frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(7000, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setPrice('3032067') // >50% price drop from previous Chainlink price
    await mockChainlink.setUpdateTime(now) // Chainlink is current

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both Oracles untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor is frozen, return Chainlink price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(5500, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const tellorUpdateTime = await mockTellor.getUpdateTime()
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await mockChainlink.setPrice('3032067')
    await mockChainlink.setUpdateTime(now) // Chainlink is current

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(246, 18)) // last good price
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(5500, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 4) // status 4: using Chainlink, Tellor untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink frozen, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using Chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')

    await mockTellor.setPrice(dec(5500, 13))

    await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3)
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3]
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(246, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '4') // status 4: using Chainlink, Tellor untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: when Chainlink breaks too, switch to bothOraclesSuspect", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('5032067')
    await mockChainlink.setUpdateTime(0)  // Chainlink breaks by 0 timestamp

    await mockTellor.setPrice(dec(5500, 13))

    await priceFeed.fetchPrice()

    const status = await priceFeed.status()
    assert.equal(status, 2)  // status 2: both oracles untrusted
  })

  it("C5 usingChainlinkTellorUntrusted: Chainlink breaks too, return last good price", async () => {
    await setAddresses()
    priceFeed.setStatus(4) // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(dec(246, 18))

    await mockChainlink.setPrevPrice(dec('7432067'))
    await mockChainlink.setPrice('7432067')
    await mockChainlink.setUpdateTime(0)  // Chainlink breaks by 0 timestamp

    await mockTellor.setPrice(dec(5500, 13))

    await priceFeed.fetchPrice()

    const price = await priceFeed.lastGoodPrice()
    assert.equal(price, dec(246, 18))
    const statusAfter = await priceFeed.status()
    assert.equal(statusAfter, '2') // status 2: both oracles untrusted
  })
  
  it("SetTellorCaller() should only allow authorized caller", async() => {
    let myPriceFeed = await PriceFeed.new()
    let _newAuthority = await GovernorTester.new(alice);
    await myPriceFeed.setAddresses(mockChainlink.address, tellorCaller.address, _newAuthority.address, { from: owner })
	  
    await assertRevert(myPriceFeed.setTellorCaller(_newAuthority.address, {from: alice}), "PriceFeed: sender not authorized for setTellorCaller(address)"); 
    assert.isTrue(tellorCaller.address == (await myPriceFeed.tellorCaller())); 
	  	  
    assert.isTrue(_newAuthority.address == (await myPriceFeed.authority()));
    let _role123 = 123;
    let _setTelorSig = "0x9545e9a5";//myPriceFeed#SET_TELLOR_CALLER_SIG;
    await _newAuthority.setRoleCapability(_role123, myPriceFeed.address, _setTelorSig, true, {from: alice});	  
    await _newAuthority.setUserRole(alice, _role123, true, {from: alice});
    assert.isTrue((await _newAuthority.canCall(alice, myPriceFeed.address, _setTelorSig)));
    await myPriceFeed.setTellorCaller(_newAuthority.address, {from: alice}); 
    assert.isTrue(_newAuthority.address == (await myPriceFeed.tellorCaller())); 
  })
})

