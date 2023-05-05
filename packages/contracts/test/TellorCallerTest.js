
const TellorCaller = artifacts.require("./TellorCaller.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")
const MockTellor = artifacts.require("./MockTellor.sol")

const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper

const { dec, assertRevert, toBN } = th

contract('TellorCaller', async accounts => {

  const [owner, alice] = accounts;
  let priceFeedTestnet
  let priceFeed
  let zeroAddressPriceFeed
  let mockChainlink

  beforeEach(async () => {	
    // use mainnet fork https://docs.tellor.io/tellor/the-basics/contracts-reference#mainnet-ethereum
    mainnetForkTellorCaller = await TellorCaller.new("0xB3B662644F8d3138df63D2F43068ea621e2981f9")

    mockTellor = await MockTellor.new()
    MockTellor.setAsDeployed(mockTellor)

    tellorCaller = await TellorCaller.new(mockTellor.address)
    TellorCaller.setAsDeployed(tellorCaller)	
	
    qBuffer = await tellorCaller.tellorQueryBufferSeconds();

    await mockTellor.setPrice(dec(3714, 13))
    const now = await th.getLatestBlockTimestamp(web3)	
    // set oracle update time to (now - buffer - 1) to satisfy the Tellor getDataBefore() semantic requirement:
    //     Finds the most RECENT UNDISPUTED submission BEFROE a specific timestamp
    await mockTellor.setUpdateTime(toBN(now.toString()).sub(toBN(qBuffer.toString())).sub(toBN('1')).toString())
  })

  describe('Tellor Caller testing...', async accounts => {
    it("getFallbackResponse() with mock tellor", async () => {
       let _price = await tellorCaller.getFallbackResponse();
       assert.equal(_price[0].toString(), '37140000000000000');
       assert.isTrue(_price[1] < (Date.now() - qBuffer));
       assert.isTrue(_price[2]);
    })
	
    it("getFallbackResponse() returns invalid price data with mock tellor", async () => {		
       await mockTellor.setInvalidRequest(1) // invalid price
       let _price = await tellorCaller.getFallbackResponse();
       assert.equal(_price[0].toString(), '0');
       assert.isFalse(_price[2]);
    })
	
    it("getFallbackResponse() returns invalid timestamp data with mock tellor", async () => {		
       await mockTellor.setInvalidRequest(2) // invalid timestamp
       let _price = await tellorCaller.getFallbackResponse();
       assert.equal(_price[1].toString(), '0');
       assert.isFalse(_price[2]);
    })
	
    it.skip("getFallbackResponse() should return valid price with mainnet fork", async () => {
       let _price = await mainnetForkTellorCaller.getFallbackResponse();
       //console.log('_retrieved=' + _price[0].toString() + ',_price=' + _price[1].toString() + ',timestamp=' + _price[2].toString());
       assert.isTrue(_price[0]);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));
    })
  })
})

