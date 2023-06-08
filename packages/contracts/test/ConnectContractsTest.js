const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('Deployment script - Sets correct contract addresses dependencies after deployment', async accounts => {
  const [owner] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  
  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let functionCaller
  let borrowerOperations
  let feeRecipient

  before(async () => {
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = coreContracts.feeRecipient;

    priceFeed = coreContracts.priceFeedTestnet
    ebtcToken = coreContracts.ebtcToken
    sortedCdps = coreContracts.sortedCdps
    cdpManager = coreContracts.cdpManager
    activePool = coreContracts.activePool
    functionCaller = coreContracts.functionCaller
    borrowerOperations = coreContracts.borrowerOperations

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectCoreContracts(coreContracts, LQTYContracts)
  })

  it('Sets the correct PriceFeed address in CdpManager', async () => {
    const priceFeedAddress = priceFeed.address

    const recordedPriceFeedAddress = await cdpManager.priceFeed()

    assert.equal(priceFeedAddress, recordedPriceFeedAddress)
  })

  it('Sets the correct EBTCToken address in CdpManager', async () => {
    const ebtcTokenAddress = ebtcToken.address

    const recordedClvTokenAddress = await cdpManager.ebtcToken()

    assert.equal(ebtcTokenAddress, recordedClvTokenAddress)
  })

  it('Sets the correct SortedCdps address in CdpManager', async () => {
    const sortedCdpsAddress = sortedCdps.address

    const recordedSortedCdpsAddress = await cdpManager.sortedCdps()

    assert.equal(sortedCdpsAddress, recordedSortedCdpsAddress)
  })

  it('Sets the correct BorrowerOperations address in CdpManager', async () => {
    const borrowerOperationsAddress = borrowerOperations.address

    const recordedBorrowerOperationsAddress = await cdpManager.borrowerOperationsAddress()

    assert.equal(borrowerOperationsAddress, recordedBorrowerOperationsAddress)
  })

  // ActivePool in CdpM
  it('Sets the correct ActivePool address in CdpManager', async () => {
    const activePoolAddress = activePool.address

    const recordedActivePoolAddresss = await cdpManager.activePool()

    assert.equal(activePoolAddress, recordedActivePoolAddresss)
  })

  // Active Pool

  it('Sets the correct BorrowerOperations address in ActivePool', async () => {
    const borrowerOperationsAddress = borrowerOperations.address

    const recordedBorrowerOperationsAddress = await activePool.borrowerOperationsAddress()

    assert.equal(borrowerOperationsAddress, recordedBorrowerOperationsAddress)
  })

  it('Sets the correct CdpManager address in ActivePool', async () => {
    const cdpManagerAddress = cdpManager.address

    const recordedCdpManagerAddress = await activePool.cdpManagerAddress()
    assert.equal(cdpManagerAddress, recordedCdpManagerAddress)
  })

  //--- BorrowerOperations ---

  // CdpManager in BO
  it('Sets the correct CdpManager address in BorrowerOperations', async () => {
    const cdpManagerAddress = cdpManager.address

    const recordedCdpManagerAddress = await borrowerOperations.cdpManager()
    assert.equal(cdpManagerAddress, recordedCdpManagerAddress)
  })

  // setPriceFeed in BO
  it('Sets the correct PriceFeed address in BorrowerOperations', async () => {
    const priceFeedAddress = priceFeed.address

    const recordedPriceFeedAddress = await borrowerOperations.priceFeed()
    assert.equal(priceFeedAddress, recordedPriceFeedAddress)
  })

  // setSortedCdps in BO
  it('Sets the correct SortedCdps address in BorrowerOperations', async () => {
    const sortedCdpsAddress = sortedCdps.address

    const recordedSortedCdpsAddress = await borrowerOperations.sortedCdps()
    assert.equal(sortedCdpsAddress, recordedSortedCdpsAddress)
  })

  // setActivePool in BO
  it('Sets the correct ActivePool address in BorrowerOperations', async () => {
    const activePoolAddress = activePool.address

    const recordedActivePoolAddress = await borrowerOperations.activePool()
    assert.equal(activePoolAddress, recordedActivePoolAddress)
  })
})
