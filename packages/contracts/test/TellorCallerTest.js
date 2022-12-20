
const TellorCaller = artifacts.require("./TellorCaller.sol")
const PriceFeed = artifacts.require("./PriceFeed.sol")

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
    tellorCaller = await TellorCaller.new("0xB3B662644F8d3138df63D2F43068ea621e2981f9")
    dummyPriceFeed = await PriceFeed.new();
    qID = await dummyPriceFeed.ETHUSD_TELLOR_QUERY_ID();
    qBuffer = await dummyPriceFeed.tellorQueryBufferSeconds();
  })

  describe('Tellor Caller testing...', async accounts => {
    it("getTellorCurrentValue(bytes32, uint256) should revert if given buffer is 0", async () => {
       await assertRevert(tellorCaller.getTellorBufferValue(qID, 0), '!bufferTime');
    })
	
    it("getTellorCurrentValue(bytes32, uint256) should return valid price", async () => {
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       //console.log('_retrieved=' + _price[0].toString() + ',_price=' + _price[1].toString() + ',timestamp=' + _price[2].toString());
       assert.isTrue(_price[0]);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));
    })
	
    it("getTellorCurrentValue(bytes32, uint256) twice with different buffers", async () => {
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isTrue(_price[0]);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));	   
	   
       let _price2 = await tellorCaller.getTellorBufferValue(qID, 1);
       assert.isTrue(_price2[0]);
       // the latter report should have at least the same retrived timestamp as the first report if not newer
       assert.isTrue(_price2[2] >= _price[2]);
       assert.isTrue(_price2[2] < Date.now());	
    })
	
  })
})

