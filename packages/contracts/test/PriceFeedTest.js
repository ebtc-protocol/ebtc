
const PriceFeed = artifacts.require("./PriceFeedTester.sol")
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol")
const MockChainlink = artifacts.require("./MockAggregator.sol")
const MockTellor = artifacts.require("./MockTellor.sol")
const TellorCaller = artifacts.require("./TellorCaller.sol")
const GovernorTester = artifacts.require("./GovernorTester.sol");

const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper
const mv = testHelpers.MoneyValues

const { dec, assertRevert, toBN, ZERO_ADDRESS } = th

const hre = require("hardhat");

contract('PriceFeed', async accounts => {

  const [owner, alice] = accounts;

  // CL feed normal prices
  const normalEthBtcPrice = dec(668056, 1)
  const normalStEthEthPrice = dec(9993566582, 8)

  // Normal aggr. answer price
  const normalStEthBtcPrice = dec(6684860650283503, 1)

  // CL feed decreased prices
  const decreasedEbtcPrice = dec(5000, 13);

  // PriceFeed testnet default price
  const normalEbtcPrice = dec(7428, 13);

  let priceFeedTestnet
  let priceFeed
  let mockChainlink
  let mockEthBtcChainlink
  let mockStEthEthChainlink
  let priceFeedContract 
  const fetchPriceFuncABI = '[{"inputs":[],"name":"fetchPrice","outputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}]';   

  // --- Helper functions
  const setAddresses = async () => {
    // using FallbackCaller as authority as we're not testing governance function
    await priceFeed.setAddresses(mockChainlink.address, tellorCaller.address, tellorCaller.address, { from: owner })
  }

  const setChainlinkTotalPrice = async (mockEthBtcChainlink, mockStEthEthChainlink, price) => {
    // For simplicity, we set the stETH/ETH price to 1
    await mockEthBtcChainlink.setPrice(price)
    await mockStEthEthChainlink.setPrice(dec(1, 18))
  }

  const setChainlinkTotalPrevPrice = async (mockEthBtcChainlink, mockStEthEthChainlink, price) => {
    // For simplicity, we set the stETH/ETH price to 1
    await mockEthBtcChainlink.setPrevPrice(price)
    await mockStEthEthChainlink.setPrevPrice(dec(1, 18))
  }

  // -- Test suites
  
  describe('PriceFeedTestnet basic tests', async () => {
    beforeEach(async () => {
      priceFeedTestnet = await PriceFeedTestnet.new(owner)
      PriceFeedTestnet.setAsDeployed(priceFeedTestnet)
    })

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

  describe('PriceFeed internal testing contract', async accounts => {
    beforeEach(async () => {
      // CL feeds mocks
      mockEthBtcChainlink = await MockChainlink.new(8)
      MockChainlink.setAsDeployed(mockEthBtcChainlink)
      mockStEthEthChainlink = await MockChainlink.new(18)
      MockChainlink.setAsDeployed(mockStEthEthChainlink)

      // Read bytecodes to replace internal contract constants for CL's
      const codeEthBtcCL = await hre.network.provider.send("eth_getCode", [
        mockEthBtcChainlink.address,
      ]);
      const codeStEthEthBtcCL = await hre.network.provider.send("eth_getCode", [
        mockEthBtcChainlink.address,
      ]);

      // Manipulate constants in `priceFeed` re cl oracles
      const ETH_BTC_CL_FEED = "0xAc559F25B1619171CbC396a50854A3240b6A4e99";
      const STETH_ETH_CL_FEED = "0x86392dC19c0b719886221c78AB11eb8Cf5c52812";

      // We set the code of the CL aggregators to that of our MockAggregator given their
      // addresses immutability
      await network.provider.send("hardhat_setCode", [ETH_BTC_CL_FEED, codeEthBtcCL]);
      await network.provider.send("hardhat_setCode", [
        STETH_ETH_CL_FEED,
        codeStEthEthBtcCL,
      ]);

      mockEthBtcChainlink = await ethers.getContractAt("MockAggregator", ETH_BTC_CL_FEED)
      mockStEthEthChainlink = await ethers.getContractAt("MockAggregator", STETH_ETH_CL_FEED);

      assert.equal(mockEthBtcChainlink.address, ETH_BTC_CL_FEED)
      assert.equal(mockStEthEthChainlink.address, STETH_ETH_CL_FEED)
      
      mockTellor = await MockTellor.new()
      MockTellor.setAsDeployed(mockTellor)

      tellorCaller = await TellorCaller.new(mockTellor.address)
      TellorCaller.setAsDeployed(tellorCaller)

      await mockEthBtcChainlink.setDecimals(8);
      await mockStEthEthChainlink.setDecimals(18);

      // Set Chainlink latest and prev round Id's to non-zero
      await mockEthBtcChainlink.setLatestRoundId(3)
      await mockEthBtcChainlink.setPrevRoundId(2)

      await mockStEthEthChainlink.setLatestRoundId(3)
      await mockStEthEthChainlink.setPrevRoundId(2)

      //Set current and prev prices in both oracles
      await mockEthBtcChainlink.setPrice(normalEthBtcPrice)
      await mockEthBtcChainlink.setPrevPrice(normalEthBtcPrice)

      await mockStEthEthChainlink.setPrice(normalStEthEthPrice)
      await mockStEthEthChainlink.setPrevPrice(normalStEthEthPrice)

      await mockTellor.setPrice(normalStEthEthPrice)

      // Set mock price updateTimes in both oracles to very recent
      const now = await th.getLatestBlockTimestamp(web3)
      await mockEthBtcChainlink.setUpdateTime(now)
      await mockStEthEthChainlink.setUpdateTime(now)
      await mockTellor.setUpdateTime(now)

      let _newAuthority = await GovernorTester.new(owner);    

      priceFeed = await PriceFeed.new(tellorCaller.address, _newAuthority.address, STETH_ETH_CL_FEED, ETH_BTC_CL_FEED, true)
      PriceFeed.setAsDeployed(priceFeed)
      priceFeedContract = new ethers.Contract(priceFeed.address, fetchPriceFuncABI, (await ethers.provider.getSigner(alice)));
    })

    // --- Chainlink breaks ---

    it("C1 chainlinkWorking: Chainlink broken by zero latest roundId of feed 1, Fallback working: switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      // await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      // await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setLatestRoundId(0)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by zero latest roundId of feed 2, Fallback working: switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockStEthEthChainlink.setLatestRoundId(0)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by zero timestamp on feed 1, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setUpdateTime(0)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by zero timestamp on feed 2, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockStEthEthChainlink.setUpdateTime(0)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by future timestamp on Feed 1, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      const now = await th.getLatestBlockTimestamp(web3)
      const future = now + 1000

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setUpdateTime(future)
      
      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by future timestamp on Feed 2, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      const now = await th.getLatestBlockTimestamp(web3)
      const future = now + 1000

      await mockTellor.setPrice(normalEbtcPrice)
      await mockStEthEthChainlink.setUpdateTime(future)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by negative price on feed 1, Fallback working,  switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setPrice("-5000")
      await mockStEthEthChainlink.setPrice(dec(1000000000000000000, 1))

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken by negative price on feed 2, Fallback working,  switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setPrice(dec(999, 8))
      await mockStEthEthChainlink.setPrice("-5000")

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink broken - latest round call reverted on Feed 1, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setLatestRevert()

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)

      // Needs to re-revert state, otherwise mess state for next test
      await mockEthBtcChainlink.setLatestRevert()
    })

    it("C1 chainlinkWorking: Chainlink broken - latest round call reverted on Feed 2, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockStEthEthChainlink.setLatestRevert()

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)

      // Needs to re-revert state, otherwise mess state for next test
      await mockStEthEthChainlink.setLatestRevert()
    })

    it("C1 chainlinkWorking: previous round call reverted on Feed 1, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockEthBtcChainlink.setPrevRevert()

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)

      // Needs to re-revert state, otherwise mess state for next test
      await mockEthBtcChainlink.setPrevRevert()
    })

    it("C1 chainlinkWorking: previous round call reverted on Feed 2, Fallback working, switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)
      await mockStEthEthChainlink.setPrevRevert()

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)

      // Needs to re-revert state, otherwise mess state for next test
      await mockStEthEthChainlink.setPrevRevert()
    })

    // --- Chainlink timeout ---

    it("C1 chainlinkWorking: Chainlink frozen from Feed 1, Fallback working: switch to usingFallbackChainlinkFrozen", async () => {

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await th.fastForwardTime(4800 + 1, web3.currentProvider) // fast forward timeout length + 1
      const now = await th.getLatestBlockTimestamp(web3)

      // Fallback price is recent
      await mockTellor.setUpdateTime(now)
      await mockTellor.setPrice(normalEbtcPrice)
      // The second feed is recent
      await mockStEthEthChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '3') // status 3: using Fallback, Chainlink frozen
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink frozen from Feed 2, Fallback working: switch to usingFallbackChainlinkFrozen", async () => {

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await th.fastForwardTime(90000 + 1, web3.currentProvider) // fast forward timeout length + 1
      const now = await th.getLatestBlockTimestamp(web3)

      // Fallback price is recent
      await mockTellor.setUpdateTime(now)
      await mockTellor.setPrice(normalEbtcPrice)
      // The first feed is recent
      await mockEthBtcChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '3') // status 3: using Fallback, Chainlink frozen
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink frozen by Feed 1, Fallback frozen: switch to usingFallbackChainlinkFrozen", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)

      await th.fastForwardTime(4800 + 1, web3.currentProvider) // fast forward timeout length + 1

      // check Fallback price timestamp is out of date by > its timout (4800)
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(4800 + 1))))

      // The second feed is recent
      await mockStEthEthChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '3') // status 3: using Fallback, Chainlink frozen
    })

    it("C1 chainlinkWorking: Chainlink frozen by Feed 2, Fallback frozen: switch to usingFallbackChainlinkFrozen", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(normalEbtcPrice)

      await th.fastForwardTime(90000 + 1, web3.currentProvider) // fast forward timeout length + 1

      // check Fallback price timestamp is out of date by > its timout (4800)
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(90000 + 1))))

      // The first feed is recent
      await mockEthBtcChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '3') // status 3: using Fallback, Chainlink frozen
    })

    it("C1 chainlinkWorking: Chainlink times out, Fallback broken by 0 price: switch to usingChainlinkFallbackUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await th.fastForwardTime(4800, web3.currentProvider) // Fast forward Feed's 1 timeout Threshold

      // Fallback breaks by 0 price
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '4') // status 4: using Chainlink, Fallback untrusted
    })

    it("C1 chainlinkWorking: Chainlink is out of date by <1hr20: remain chainlinkWorking", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1234, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1234, 8))
      await th.fastForwardTime(4740, web3.currentProvider) // fast forward 1hrs 19 minutes 

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
      
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(1234, 18))
    })

    // --- Chainlink price deviation ---

    it("C1 chainlinkWorking: Chainlink price drop of >50%, switch to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setLastGoodPrice(normalEbtcPrice)

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
      let price = await priceFeed.lastGoodPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink price drop of 50%, remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1, 8))  // price drops to 1

      const priceFetchTx = await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price drop of 50%, return the Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1, 8))  // price drops to 1

      const priceFetchTx = await priceFeed.fetchPrice()

      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(1, 18))
    })

    it("C1 chainlinkWorking: Chainlink price drop of <50%, remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100000001))   // price drops to 1.00000001:  a drop of < 50% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price drop of <50%, return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 100000001)   // price drops to 1.00000001:  a drop of < 50% from previous

      const priceFetchTx = await priceFeed.fetchPrice()

      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(100000001, 10))
    })

    // Price increase
    it("C1 chainlinkWorking: Chainlink price increase of >100%, switch to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 400000001)  // price increases to 4.000000001: an increase of > 100% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
    })

    it("C1 chainlinkWorking: Chainlink price increase of >100%, return Fallback price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 400000001)  // price increases to 4.000000001: an increase of > 100% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink price increase of 100%, remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(4, 8))  // price increases to 4: an increase of 100% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price increase of 100%, return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(4, 8))  // price increases to 4: an increase of 100% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(4, 18))
    })

    it("C1 chainlinkWorking: Chainlink price increase of <100%, remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 399999999)  // price increases to 3.99999999: an increase of < 100% from previous

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price increase of <100%,  return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(normalEbtcPrice)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 399999999)  // price increases to 3.99999999: an increase of < 100% from previous

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(399999999, 10))
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback price matches: remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(normalEbtcPrice)

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, normalEbtcPrice)
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, normalEbtcPrice)
      await mockTellor.setPrice(normalEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback price matches: return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 7018000)  // price drops to 0.99999999: a drop of > 50% from previous
      await mockTellor.setPrice(normalEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback price within 5% of Chainlink: remain chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(2, 18))
    
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      await mockTellor.setPrice(dec(104, 18)) // Fallback price drops to 104.99: price difference with new Chainlink price is now just under 5%

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback price within 5% of Chainlink: return Chainlink price", async () => {

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      await mockTellor.setPrice(normalEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, normalEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback live but not within 5% of Chainlink: switch to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setLastGoodPrice(normalEbtcPrice)

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      // Fallback price drops to 105.000001: price difference with new Chainlink price is now > 5%
      await mockTellor.setPrice(decreasedEbtcPrice)

      await priceFeed.fetchPrice()
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback live but not within 5% of Chainlink: return Fallback price", async () => {
      
      priceFeed.setLastGoodPrice(normalEbtcPrice)

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      await mockTellor.setPrice(decreasedEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, decreasedEbtcPrice)
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback frozen: switch to usingFallbackChainlinkUntrusted", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      await mockTellor.setPrice(decreasedEbtcPrice)

      // 4 hours pass with no Fallback updates
      await th.fastForwardTime(14400, web3.currentProvider)

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockEthBtcChainlink.setUpdateTime(now)
      await mockStEthEthChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback frozen: return last good price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1000, 8))  // prev price = 1000
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(100, 8))  // price drops to 100: a drop of > 50% from previous
      await mockTellor.setPrice(decreasedEbtcPrice)

      // 4 hours pass with no Fallback updates
      await th.fastForwardTime(14400, web3.currentProvider)

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now)
      await mockEthBtcChainlink.setUpdateTime(now)
      await priceFeed.fetchPrice()
      let price = await priceFeed.lastGoodPrice()

      // Check that the returned price is the last good price
      assert.equal(price, dec(1200, 18))
    })

    // --- Chainlink fails and Fallback is broken ---

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by 0 price: switch to bothOracleSuspect", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      await mockTellor.setPrice(0)  // Fallback price drops to 0

      const priceFetchTx = await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by 0 price: return last good price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      // Make mock Chainlink price deviate too much
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      // Make mock Fallback return 0 price
      await mockTellor.setPrice(0)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeed.lastGoodPrice()

      // Check that the returned price is in fact the previous price
      assert.equal(price, dec(1200, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by 0 timestamp: switch to bothOracleSuspect", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      // Make mock Chainlink price deviate too much
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      // Make mock Fallback return 0 timestamp
      await mockTellor.setUpdateTime(0)
      const priceFetchTx = await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by 0 timestamp: return last good price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(decreasedEbtcPrice)

      // Make mock Chainlink price deviate too much
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      // Make mock Fallback return 0 timestamp
      await mockTellor.setUpdateTime(0)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeed.lastGoodPrice()

      // Check that the returned price is in fact the previous price
      assert.equal(price, dec(1200, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2')  // status 2: both oracles untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by future timestamp: Pricefeed switches to bothOracleSuspect", async () => {
      
      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      // Make mock Chainlink price deviate too much
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      // Make mock Fallback return 0 timestamp
      await mockTellor.setUpdateTime(0)

      const priceFetchTx = await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    it("C1 chainlinkWorking: Chainlink price drop of >50% and Fallback is broken by future timestamp: return last good price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await mockTellor.setPrice(decreasedEbtcPrice)

      // Make mock Chainlink price deviate too much
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 8))  // price = 2
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 99999999)  // price drops to 0.99999999: a drop of > 50% from previous

      // Make mock Fallback return a future timestamp
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
    it("C1 chainlinkWorking: Chainlink is working and Fallback is working - remain on chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(decreasedEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback is working - return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(decreasedEbtcPrice)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()

      // Check that the returned price is current Chainlink price
      assert.equal(price, dec(102, 18))
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback freezes - remain on chainlinkWorking", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(decreasedEbtcPrice)

      // 4 hours pass with no Fallback updates
      await th.fastForwardTime(14400, web3.currentProvider)

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink's price is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink's price is current

      const priceFetchTx = await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '0') // status 0: Chainlink working
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback freezes - return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18))

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(decreasedEbtcPrice)

      // 4 hours pass with no Fallback updates
      await th.fastForwardTime(14400, web3.currentProvider)

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink's price is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink's price is current

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()

      // Check that the returned price is current Chainlink price
      assert.equal(price, dec(102, 18))
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback breaks: switch to usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '4') // status 4: Using Chainlink, Fallback untrusted
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback breaks with ifRetrieve = false: switch to usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(7413, 13))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(7413, 13))

      await mockTellor.setPrice(decreasedEbtcPrice)
      await mockTellor.setRevertRequest()
      await priceFeed.fetchPrice()

      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '4') // status 4: // status 4: Using Chainlink, Fallback untrusted
    })

    it("C1 chainlinkWorking: Chainlink is working and Fallback breaks: return Chainlink price", async () => {
      
      priceFeed.setLastGoodPrice(dec(1200, 18)) // establish a "last good price" from the previous price fetch

      const statusBefore = await priceFeed.status()
      assert.equal(statusBefore, '0') // status 0: Chainlink working

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(101, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(102, 8))

      await mockTellor.setPrice(0)

      const priceFetchTx = await priceFeed.fetchPrice()
      let price = await priceFeedContract.callStatic.fetchPrice()

      // Check that the returned price is current Chainlink price
      assert.equal(price, dec(102, 18))
    })

    // --- Case 2: using Fallback ---

    // using Fallback, Fallback breaks
    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by zero price: switch to bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await priceFeed.setLastGoodPrice(dec(123, 18))

      const now = await th.getLatestBlockTimestamp(web3)
      await mockTellor.setUpdateTime(now)
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by zero price: return last good price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

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

    // using Fallback, Fallback breaks
    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by call reverted: switch to bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await priceFeed.setLastGoodPrice(dec(123, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await mockTellor.setPrice(decreasedEbtcPrice)

      await mockTellor.setRevertRequest()

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by call reverted: return last good price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await priceFeed.setLastGoodPrice(dec(123, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await mockTellor.setPrice(decreasedEbtcPrice)

      await mockTellor.setRevertRequest()

      await priceFeed.fetchPrice()
      const price = await priceFeed.lastGoodPrice()

      assert.equal(price, '123000000000000000000')
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    // using Fallback, Fallback breaks
    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by zero timestamp: switch to bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await priceFeed.setLastGoodPrice(dec(123, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await mockTellor.setPrice(decreasedEbtcPrice)

      await mockTellor.setUpdateTime(0)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C2 usingFallbackChainlinkUntrusted: Fallback breaks by zero timestamp: return last good price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await priceFeed.setLastGoodPrice(dec(123, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await mockTellor.setPrice(decreasedEbtcPrice)

      await mockTellor.setUpdateTime(0)

      await priceFeed.fetchPrice()
      const price = await priceFeed.lastGoodPrice()

      assert.equal(price, '123000000000000000000')
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    // using Fallback, Fallback freezes
    it("C2 usingFallbackChainlinkUntrusted: Fallback freezes - remain usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await mockTellor.setPrice(decreasedEbtcPrice)

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now)
      await mockEthBtcChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })

    it("C2 usingFallbackChainlinkUntrusted: Fallback freezes - return last good price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await mockTellor.setPrice(decreasedEbtcPrice)

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now)
      await mockEthBtcChainlink.setUpdateTime(now)

      await priceFeed.fetchPrice()
      const price = await priceFeed.lastGoodPrice()

      assert.equal(price, dec(246, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
    })

    // using Fallback, both Chainlink & Fallback go live

    it("C2 usingFallbackChainlinkUntrusted: both Fallback and Chainlink are live and <= 5% price difference - switch to chainlinkWorking", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await mockTellor.setPrice(dec(7000, 13))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067') // price = 105: 5% difference from Chainlink

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 0)  // status 0: Chainlink working
    })

    it("C2 usingFallbackChainlinkUntrusted: both Fallback and Chainlink are live and <= 5% price difference - return Chainlink price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await mockTellor.setPrice(dec(7000, 13))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067') // price = 105: 5% difference from Chainlink

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '70220670000000000')
    })

    it("C2 usingFallbackChainlinkUntrusted: both Fallback and Chainlink are live and > 5% price difference - remain usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await mockTellor.setPrice(decreasedEbtcPrice)
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })

    it("C2 usingFallbackChainlinkUntrusted: both Fallback and Chainlink are live and > 5% price difference - return Fallback price", async () => {
      
      priceFeed.setStatus(1) // status 1: using Fallback, Chainlink untrusted

      await mockTellor.setPrice(decreasedEbtcPrice)
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      // Fallback price
      assert.equal(price, decreasedEbtcPrice)
    })

    it("C2 usingFallbackChainlinkUntrusted: Fallback frozen with stale data while chainlink break", async () => {
      
      priceFeed.setStatus(0) // status 0: Chainlink working

      await priceFeed.setLastGoodPrice(dec(999, 18))
      let _p = await priceFeed.lastGoodPrice()

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, 0)

      await mockTellor.setUpdateTime(1)
      await mockTellor.setPrice(decreasedEbtcPrice)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })


    // --- Case 3: Both Oracles suspect

    it("C3 bothOraclesUntrusted: both Fallback and Chainlink are live and > 5% price difference remain bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(2) // status 2: both oracles untrusted

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await mockTellor.setPrice(decreasedEbtcPrice)
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C3 bothOraclesUntrusted: both Fallback and Chainlink are live and > 5% price difference, return last good price", async () => {
      
      priceFeed.setStatus(2) // status 2: both oracles untrusted

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await mockTellor.setPrice(decreasedEbtcPrice)
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      await priceFeed.fetchPrice()
      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(50, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })

    it("C3 bothOraclesUntrusted: both Fallback and Chainlink are live and <= 5% price difference, switch to chainlinkWorking", async () => {
      
      priceFeed.setStatus(2) // status 2: both oracles untrusted

      await mockTellor.setPrice(dec(7000, 13))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 0)  // status 0: Chainlink working
    })

    it("C3 bothOraclesUntrusted: both Fallback and Chainlink are live and <= 5% price difference, return Chainlink price", async () => {
      
      priceFeed.setStatus(2) // status 2: both oracles untrusted

      await mockTellor.setPrice(dec(7000, 13))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '70220670000000000')
    })

    // --- Case 4 ---
    it("C4 usingFallbackChainlinkFrozen: when both Chainlink and Fallback break, switch to bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Both Chainlink and Fallback break with 0 price
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when both Chainlink and Fallback break, return last good price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Both Chainlink and Fallback break with 0 price
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(50, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, 2) // status 2: both oracles untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink breaks and Fallback freezes, switch to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Chainlink breaks
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))

      await mockTellor.setPrice(decreasedEbtcPrice)

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink breaks and Fallback freezes, return last good price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Chainlink breaks
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(50, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '1') // status 1: using Fallback, Chainlink untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink breaks and Fallback live, switch to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Chainlink breaks
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink breaks and Fallback live, return Fallback price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      // Chainlink breaks
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(0))

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(7000, 13))
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with <5% price difference, switch back to chainlinkWorking", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 0)  // status 0: Chainlink working
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with <5% price difference, return Chainlink current price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '70220670000000000')  // Chainlink price
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with >5% price difference, switch back to usingFallbackChainlinkUntrusted", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 1)  // status 1: using Fallback, Chainlink untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with >5% price difference, return Chainlink current price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7522067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(7000, 13))  // Fallback price
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with similar price, switch back to chainlinkWorking", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 0)  // status 0: Chainlink working
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback is live with similar price, return Chainlink current price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '70220670000000000')  // Chainlink price
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback breaks, switch to usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)  // status 4: Using Chainlink, Fallback untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink is live and Fallback breaks, return Chainlink current price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen
		
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '70220670000000000')
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback breaks, switch to usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // set tellor broken
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)  // status 4: using Chainlink, Fallback untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback broken, return last good price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // set tellor broken
      await mockTellor.setPrice(0)

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(50, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '4') // status 4: using Chainlink, Fallback untrusted
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback live, remain usingFallbackChainlinkFrozen", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // set Fallback to current time
      await mockTellor.setUpdateTime(now)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 3)  // status 3: using Fallback, Chainlink frozen
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback live, return Fallback price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7032067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7022067')

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // set Fallback to current time
      await mockTellor.setUpdateTime(now)

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, dec(7000, 13))
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback freezes, remain usingFallbackChainlinkFrozen", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // check Fallback price timestamp is out of date by > 4 hours
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(toBN(tellorUpdateTime).lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 3)  // status 3: using Fallback, Chainlink frozen
    })

    it("C4 usingFallbackChainlinkFrozen: when Chainlink still frozen and Fallback freezes, return last good price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      await priceFeed.setLastGoodPrice(dec(50, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(999, 8))

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      // check Fallback price timestamp is out of date by > 4 hours
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(toBN(tellorUpdateTime).lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(50, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '3') // status 3: using Fallback, Chainlink frozen
    })

    it("C4 usingFallbackChainlinkFrozen: Fallback frozen with stale data while chainlink is live, return last good price", async () => {
      
      priceFeed.setStatus(3) // status 3: using Fallback, Chainlink frozen

      const now = await th.getLatestBlockTimestamp(web3)
      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink is current
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1234, 8))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1234, 8))
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
    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live and Fallback price >5% - no status change", async () => {
      
      priceFeed.setStatus(4) // status 4: using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(decreasedEbtcPrice)

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)  // status 4: using Chainlink, Fallback untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live and Fallback price >5% - return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4: using chainlink, Fallback untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(decreasedEbtcPrice)

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '74220670000000000')
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live and Fallback price within <5%, switch to chainlinkWorking", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(dec(7500, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 0)  // status 0: Chainlink working
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, Fallback price not within 5%, return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(dec(7000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '74220670000000000')
    })

    // ---------

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, <50% price deviation from previous, Fallback price not within 5%, remain on usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(dec(1000, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)  // status 4: using Chainlink, Fallback untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, <50% price deviation from previous, Fallback price not within 5%, return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7422067')

      await mockTellor.setPrice(dec(1000, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '74220670000000000')
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, >50% price deviation from previous, Fallback price not within 5%, remain on usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(normalEbtcPrice)

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5022067')
      await mockTellor.setPrice(dec(10000, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, >50% price deviation from previous,  Fallback price not within 5%, return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')
      await mockTellor.setPrice(dec(7000, 13))

      const price = await priceFeedContract.callStatic.fetchPrice()
      assert.equal(price, '50320670000000000') // last good price
    })

    // -------

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, <50% price deviation from previous, and Fallback is frozen, remain on usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice('74320670000000000')

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink is current

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4)  // status 4: using Chainlink, Fallback untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, <50% price deviation from previous, Fallback is frozen, return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink is current

      await priceFeed.fetchPrice()
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, >50% price deviation from previous, Fallback is frozen, remain on usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(7000, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '3032067') // >50% price drop from previous Chainlink price
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '2516033') // >50% price drop from previous Chainlink price
      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink is current

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both Oracles untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink is live, >50% price deviation from previous, Fallback is frozen, return Chainlink price", async () => {
      
      priceFeed.setStatus(4) // status 4:  using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(5500, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours

      // check Fallback price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const tellorUpdateTime = await mockTellor.getUpdateTime()
      assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))))

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '3032067')
      await mockStEthEthChainlink.setUpdateTime(now) // Chainlink is current
      await mockEthBtcChainlink.setUpdateTime(now) // Chainlink is current

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(246, 18)) // last good price
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink frozen, remain on usingChainlinkFallbackUntrusted", async () => {
      
      priceFeed.setStatus(4) // status 4: using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(5500, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 4) // status 4: using Chainlink, Fallback untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink frozen, return last good price", async () => {
      
      priceFeed.setStatus(4) // status 4: using Chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')

      await mockTellor.setPrice(dec(5500, 13))

      await th.fastForwardTime(14400, web3.currentProvider) // Fast forward 4 hours

      // check Chainlink price timestamp is out of date by > 4 hours
      const now = await th.getLatestBlockTimestamp(web3)
      const chainlinkUpdateTime = (await mockStEthEthChainlink.latestRoundData())[3]
      assert.isTrue(toBN(chainlinkUpdateTime).lt(toBN(now).sub(toBN(14400))))

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(246, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '4') // status 4: using Chainlink, Fallback untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: when Chainlink breaks too, switch to bothOraclesSuspect", async () => {
      
      priceFeed.setStatus(4) // status 4: using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '5032067')
      await mockStEthEthChainlink.setUpdateTime(0)  // Chainlink breaks by 0 timestamp

      await mockTellor.setPrice(dec(5500, 13))

      await priceFeed.fetchPrice()

      const status = await priceFeed.status()
      assert.equal(status, 2)  // status 2: both oracles untrusted
    })

    it("C5 usingChainlinkFallbackUntrusted: Chainlink breaks too, return last good price", async () => {
      
      priceFeed.setStatus(4) // status 4: using chainlink, Fallback untrusted

      await priceFeed.setLastGoodPrice(dec(246, 18))

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec('7432067'))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, '7432067')
      await mockStEthEthChainlink.setUpdateTime(0)  // Chainlink breaks by 0 timestamp

      await mockTellor.setPrice(dec(5500, 13))

      await priceFeed.fetchPrice()

      const price = await priceFeed.lastGoodPrice()
      assert.equal(price, dec(246, 18))
      const statusAfter = await priceFeed.status()
      assert.equal(statusAfter, '2') // status 2: both oracles untrusted
    })
    
    it("SetFallbackCaller() should only allow authorized caller", async() => {
      const ETH_BTC_CL_FEED = "0xAc559F25B1619171CbC396a50854A3240b6A4e99";
      const STETH_ETH_CL_FEED = "0x86392dC19c0b719886221c78AB11eb8Cf5c52812";
      let _newAuthority = await GovernorTester.new(alice);    
      let myPriceFeed = await PriceFeed.new(tellorCaller.address, _newAuthority.address, STETH_ETH_CL_FEED, ETH_BTC_CL_FEED, true)
      
      await assertRevert(myPriceFeed.setFallbackCaller(_newAuthority.address, {from: alice}), "Auth: UNAUTHORIZED"); 
      assert.isTrue(tellorCaller.address == (await myPriceFeed.fallbackCaller())); 
          
      assert.isTrue(_newAuthority.address == (await myPriceFeed.authority()));
      let _role123 = 123;
      let _setFallbackSig = "0xb6f0e8ce"; // myPriceFeed#SET_FALLBACK_CALLER_SIG;
      await _newAuthority.setRoleCapability(_role123, myPriceFeed.address, _setFallbackSig, true, {from: alice});	  
      await _newAuthority.setUserRole(alice, _role123, true, {from: alice});
      assert.isTrue((await _newAuthority.canCall(alice, myPriceFeed.address, _setFallbackSig)));

      // TODO: now this has health-checks, needs to be some healthy "fallback"
      let mockTellorRandom = await MockTellor.new()
      MockTellor.setAsDeployed(mockTellorRandom)

      let tellorCallerRandom = await TellorCaller.new(mockTellorRandom.address)
      TellorCaller.setAsDeployed(tellorCallerRandom)

      await mockTellorRandom.setPrice(normalStEthEthPrice)

      // Set mock price updateTimes in both oracles to very recent
      const now = await th.getLatestBlockTimestamp(web3)
      await mockTellorRandom.setUpdateTime(now)

      await myPriceFeed.setFallbackCaller(tellorCallerRandom.address, {from: alice}); 
      assert.isTrue(tellorCallerRandom.address == (await myPriceFeed.fallbackCaller())); 
    })
  })

  describe('Fallback Oracle is bricked', async () => {
    beforeEach(async () => {
      // CL feeds mocks
      mockEthBtcChainlink = await MockChainlink.new(8)
      MockChainlink.setAsDeployed(mockEthBtcChainlink)
      mockStEthEthChainlink = await MockChainlink.new(18)
      MockChainlink.setAsDeployed(mockStEthEthChainlink)

      // Read bytecodes to replace internal contract constants for CL's
      const codeEthBtcCL = await hre.network.provider.send("eth_getCode", [
        mockEthBtcChainlink.address,
      ]);
      const codeStEthEthBtcCL = await hre.network.provider.send("eth_getCode", [
        mockEthBtcChainlink.address,
      ]);

      // Manipulate constants in `priceFeed` re cl oracles
      const ETH_BTC_CL_FEED = "0xAc559F25B1619171CbC396a50854A3240b6A4e99";
      const STETH_ETH_CL_FEED = "0x86392dC19c0b719886221c78AB11eb8Cf5c52812";

      // We set the code of the CL aggregators to that of our MockAggregator given their
      // addresses immutability
      await network.provider.send("hardhat_setCode", [ETH_BTC_CL_FEED, codeEthBtcCL]);
      await network.provider.send("hardhat_setCode", [
        STETH_ETH_CL_FEED,
        codeStEthEthBtcCL,
      ]);

      mockEthBtcChainlink = await ethers.getContractAt("MockAggregator", ETH_BTC_CL_FEED)
      mockStEthEthChainlink = await ethers.getContractAt("MockAggregator", STETH_ETH_CL_FEED);

      assert.equal(mockEthBtcChainlink.address, ETH_BTC_CL_FEED)
      assert.equal(mockStEthEthChainlink.address, STETH_ETH_CL_FEED)

      mockTellor = await MockTellor.new()
      MockTellor.setAsDeployed(mockTellor)

      tellorCaller = await TellorCaller.new(mockTellor.address)
      TellorCaller.setAsDeployed(tellorCaller)

      mockEthBtcChainlink.setDecimals(8);
      mockStEthEthChainlink.setDecimals(18);

      // Set Chainlink latest and prev round Id's to non-zero
      await mockEthBtcChainlink.setLatestRoundId(3)
      await mockEthBtcChainlink.setPrevRoundId(2)

      await mockStEthEthChainlink.setLatestRoundId(3)
      await mockStEthEthChainlink.setPrevRoundId(2)

      //Set current and prev prices in both oracles
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1, 9))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(1, 9))
      await mockTellor.setPrice(normalEbtcPrice)

      // Set mock price updateTimes in both oracles to very recent
      const now = await th.getLatestBlockTimestamp(web3)
      await mockEthBtcChainlink.setUpdateTime(now)
      await mockStEthEthChainlink.setUpdateTime(now)
      await mockTellor.setUpdateTime(now)

      // Deploy the Authority contract
      let _newAuthority = await GovernorTester.new(alice);

      // Deploy PriceFeed and set it up
      priceFeed = await PriceFeed.new(tellorCaller.address, _newAuthority.address, STETH_ETH_CL_FEED, ETH_BTC_CL_FEED, true)
      PriceFeed.setAsDeployed(priceFeed)
      assert.isTrue(_newAuthority.address == (await priceFeed.authority()));

      // Confirm and store good price 
      const fetchPriceFuncABI = '[{"inputs":[],"name":"fetchPrice","outputs":[{"internalType":"uint256","name":"_price","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}]';
      priceFeedContract = new ethers.Contract(priceFeed.address, fetchPriceFuncABI, (await ethers.provider.getSigner(alice)));         
      let price = await priceFeedContract.callStatic.fetchPrice() // Fetch price to store a good price
      // Check eBTC PriceFeed gives 10, with 18 digit precision
      assert.equal(price, dec(10, 18))

      // We assign Alice permission to change the fallback Oracle
      let _role123 = 123;
      let _setFallbackSig = "0xb6f0e8ce"; // priceFeed#SET_FALLBACK_CALLER_SIG;
      await _newAuthority.setRoleCapability(_role123, priceFeed.address, _setFallbackSig, true, {from: alice});	  
      await _newAuthority.setUserRole(alice, _role123, true, {from: alice});
      // Alice bricks the fallback Oracle
      await priceFeed.setFallbackCaller(ZERO_ADDRESS, {from: alice}); 
      assert.equal(await priceFeed.fallbackCaller(), ZERO_ADDRESS);
    })

    it("C1 chainlinkWorking: Chainlink broken by zero latest roundId, Fallback bricked, should return last good price", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      await mockEthBtcChainlink.setLatestRoundId(0)
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '2') // status 2: bothOraclesUntrusted
    })

    it("C1 chainlinkWorking: Chainlink broken by zero timestamp, Fallback bricked, should return last good price", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      await mockEthBtcChainlink.setUpdateTime(0)
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '2') // status 2: bothOraclesUntrusted
    })

    it("C1 chainlinkWorking: Chainlink broken by future timestamp, Fallback bricked, should return last good price", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      const now = await th.getLatestBlockTimestamp(web3)
      const future = now + 1000
      await mockEthBtcChainlink.setUpdateTime(future)
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '2') // status 2: bothOraclesUntrusted
    })

    it("C1 chainlinkWorking: Chainlink broken by negative price, Fallback bricked, should return last good price", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, "-5000")
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '2') // status 2: bothOraclesUntrusted
    })

    it("C1 chainlinkWorking: Chainlink frozen, Fallback bricked, should return last good price", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      await th.fastForwardTime(14400, web3.currentProvider) // fast forward 4 hours
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '4') // status 4: usingChainlinkFallbackUntrusted
    })

    it("Price Feed Combination: prefer multiplication over division", async () => {
      // check a case when stETH/ETH is below 1, the resulting stETH/BTC should be smaller than ETH/BTC
      let ethBTCPrice = toBN("6803827");	
      let _combinedPrice = await priceFeed.formatClAggregateAnswer(ethBTCPrice, toBN("990000000000000000"))
      assert.isTrue(_combinedPrice.lt(ethBTCPrice.mul(toBN(dec(10,10)))))
      // check an extreme case when stETH/ETH is far below 1, the resulting stETH/BTC should be relatively much smaller than ETH/BTC
      let _combinedPrice2 = await priceFeed.formatClAggregateAnswer(ethBTCPrice, toBN("11000000000000000"))
      assert.isTrue(_combinedPrice2.mul(toBN(dec(10,1))).lt(ethBTCPrice.mul(toBN(dec(10,10)))))
    })

    it("Chainlink working, Chainlink broken, Fallback bricked, Chainlink recovers, Fallback added", async () => {
      // Status should be 0
      let status = await priceFeed.status()
      assert.equal(status, '0') // status 0: using Chainlink

      await mockEthBtcChainlink.setLatestRoundId(0)
      let price = await priceFeedContract.callStatic.fetchPrice()
      // Price equals last good price
      assert.equal(price.toString(), '0')
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '2') // status 2: bothOraclesUntrusted

      // ChainLink recovers and changes price
      await mockEthBtcChainlink.setLatestRoundId(4)
      await mockEthBtcChainlink.setPrevRoundId(3)
      await mockStEthEthChainlink.setLatestRoundId(4)
      await mockStEthEthChainlink.setPrevRoundId(3)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 9))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(2, 9))

      price = await priceFeedContract.callStatic.fetchPrice()
      // Check eBTC PriceFeed gives 2e9, with 18 digit precision
      assert.equal(price, dec(20, 18))
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '4') // status 4: usingChainlinkFallbackUntrusted

      // Chainlink price updates and there's no status change
      await mockEthBtcChainlink.setLatestRoundId(5)
      await mockEthBtcChainlink.setPrevRoundId(4)
      await mockStEthEthChainlink.setLatestRoundId(5)
      await mockStEthEthChainlink.setPrevRoundId(4)
      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(3, 9))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(3, 9))

      price = await priceFeedContract.callStatic.fetchPrice()
      // Check eBTC PriceFeed gives 3e9, with 18 digit precision
      assert.equal(price, dec(30, 18))
      await priceFeed.fetchPrice()

      // Chainlink and Fallback should be broken so, therefore, the status should change to 2
      status = await priceFeed.status()
      assert.equal(status, '4') // status 4: usingChainlinkFallbackUntrusted

      // A Fallback Oracle is added and it reports a valid value, same as CL
      const now = await th.getLatestBlockTimestamp(web3)
      await mockTellor.setUpdateTime(now)
      await mockTellor.setPrice(dec(40, 18))
      await priceFeed.setFallbackCaller(tellorCaller.address, {from: alice})
      assert.equal(await priceFeed.fallbackCaller(), tellorCaller.address)

      await setChainlinkTotalPrevPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(4, 9))
      await setChainlinkTotalPrice(mockEthBtcChainlink, mockStEthEthChainlink, dec(4, 9))

      price = await priceFeedContract.callStatic.fetchPrice()
      // Check eBTC PriceFeed gives 4e9, with 18 digit precision
      assert.equal(price, dec(40, 18))
      await priceFeed.fetchPrice()

      // Both oracles are live and reporting a simiar value
      status = await priceFeed.status()
      assert.equal(status, '0') // status 0: chainlinkWorking
    })
  })
})