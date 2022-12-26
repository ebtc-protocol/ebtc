
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
	
    dummyPriceFeed = await PriceFeed.new();
    PriceFeed.setAsDeployed(dummyPriceFeed)
	
    qID = await dummyPriceFeed.ETHUSD_TELLOR_QUERY_ID();
    qBuffer = await dummyPriceFeed.tellorQueryBufferSeconds();
	
    dummyPrice = dec(100, 18)
    await mockTellor.setPrice(dummyPrice)	
    const now = await th.getLatestBlockTimestamp(web3)	
    await mockTellor.setUpdateTime(toBN(now.toString()).sub(toBN(qBuffer.toString())).sub(toBN('1')).toString())
  })

  describe('Tellor Caller testing...', async accounts => {
    it("getTellorBufferValue(bytes32, uint256) with mock tellor", async () => {
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isTrue(_price[0]);
       assert.equal(_price[1].toString(), dummyPrice);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));
    })
	
    it("getTellorCurrentValue(bytes32, uint256) should revert if given buffer is 0", async () => {
       await assertRevert(tellorCaller.getTellorBufferValue(qID, 0), '!bufferTime');
    })
	
    it.skip("getTellorBufferValue(bytes32, uint256) should return valid price with mainnet fork", async () => {
       let _price = await mainnetForkTellorCaller.getTellorBufferValue(qID, qBuffer);
       //console.log('_retrieved=' + _price[0].toString() + ',_price=' + _price[1].toString() + ',timestamp=' + _price[2].toString());
       assert.isTrue(_price[0]);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));
    })
	
    it.skip("getTellorBufferValue(bytes32, uint256) twice with different buffers with mainnet fork", async () => {
       let _price = await mainnetForkTellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isTrue(_price[0]);
       assert.isTrue(_price[2] < (Date.now() - qBuffer));	   
	   
       let _price2 = await mainnetForkTellorCaller.getTellorBufferValue(qID, 1);
       assert.isTrue(_price2[0]);
       // the latter report should have at least the same retrived timestamp as the first report if not newer
       assert.isTrue(_price2[2] >= _price[2]);
       assert.isTrue(_price2[2] < Date.now());	
    })
	
  })
})

