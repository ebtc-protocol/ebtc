
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
    await mockTellor.setEthPrice(dec(1500, 18))
    await mockTellor.setBtcPrice(dec(20000, 18))
    const now = await th.getLatestBlockTimestamp(web3)	
    // set oracle update time to (now - buffer - 1) to satisfy the Tellor getDataBefore() semantic requirement:
    //     Finds the most RECENT UNDISPUTED submission BEFROE a specific timestamp
    await mockTellor.setUpdateTime(toBN(now.toString()).sub(toBN(qBuffer.toString())).sub(toBN('1')).toString())
  })

  describe('Tellor Caller testing...', async accounts => {
    it("getTellorBufferValue(bytes32, uint256) with mock tellor", async () => {
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isTrue(_price[0]);
       assert.equal(_price[1].toString(), '1500000000000000000000');
       assert.isTrue(_price[2] < (Date.now() - qBuffer));
    })
	
    it("getTellorBufferValue(bytes32, uint256) returns invalid price data with mock tellor", async () => {		
       await mockTellor.setInvalidRequest(1) // invalid price
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isFalse(_price[0]);
       assert.equal(_price[1].toString(), '0');
    })
	
    it("getTellorBufferValue(bytes32, uint256) returns invalid timestamp data with mock tellor", async () => {		
       await mockTellor.setInvalidRequest(2) // invalid timestamp
       let _price = await tellorCaller.getTellorBufferValue(qID, qBuffer);
       assert.isFalse(_price[0]);
       assert.equal(_price[2].toString(), '0');
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

