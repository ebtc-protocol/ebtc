const deploymentHelper = require("../utils/deploymentHelpers.js")

contract('Deployment script - Sets correct contract addresses dependencies after deployment', async accounts => {
  const [owner] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  
  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let activePool
  let defaultPool
  let functionCaller
  let borrowerOperations
  let feeRecipient

  before(async () => {
    const coreContracts = await deploymentHelper.deployLiquityCore()
    const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

    priceFeed = coreContracts.priceFeedTestnet
    ebtcToken = coreContracts.ebtcToken
    sortedCdps = coreContracts.sortedCdps
    cdpManager = coreContracts.cdpManager
    activePool = coreContracts.activePool
    defaultPool = coreContracts.defaultPool
    functionCaller = coreContracts.functionCaller
    borrowerOperations = coreContracts.borrowerOperations

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectCoreContracts(coreContracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, coreContracts)
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

  // DefaultPool in CdpM
  it('Sets the correct DefaultPool address in CdpManager', async () => {
    const defaultPoolAddress = defaultPool.address

    const recordedDefaultPoolAddresss = await cdpManager.defaultPool()

    assert.equal(defaultPoolAddress, recordedDefaultPoolAddresss)
  })

  // LQTY Staking in CdpM
  it('Sets the correct FeeRecipient address in CdpManager', async () => {
    const lqtyStakingAddress = feeRecipient.address

    const recordedLQTYStakingAddress = await cdpManager.feeRecipient()
    assert.equal(lqtyStakingAddress, recordedLQTYStakingAddress)
  })

  // Active Pool

  it('Sets the correct DefaultPool address in ActivePool', async () => {
    const defaultPoolAddress = defaultPool.address

    const recordedDefaultPoolAddress = await activePool.defaultPoolAddress()

    assert.equal(defaultPoolAddress, recordedDefaultPoolAddress)
  })

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

  // Default Pool

  it('Sets the correct CdpManager address in DefaultPool', async () => {
    const cdpManagerAddress = cdpManager.address

    const recordedCdpManagerAddress = await defaultPool.cdpManagerAddress()
    assert.equal(cdpManagerAddress, recordedCdpManagerAddress)
  })

  it('Sets the correct ActivePool address in DefaultPool', async () => {
    const activePoolAddress = activePool.address

    const recordedActivePoolAddress = await defaultPool.activePoolAddress()
    assert.equal(activePoolAddress, recordedActivePoolAddress)
  })

  it('Sets the correct CdpManager address in SortedCdps', async () => {
    const borrowerOperationsAddress = borrowerOperations.address

    const recordedBorrowerOperationsAddress = await sortedCdps.borrowerOperationsAddress()
    assert.equal(borrowerOperationsAddress, recordedBorrowerOperationsAddress)
  })

  it('Sets the correct BorrowerOperations address in SortedCdps', async () => {
    const cdpManagerAddress = cdpManager.address

    const recordedCdpManagerAddress = await sortedCdps.cdpManager()
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

  // setDefaultPool in BO
  it('Sets the correct DefaultPool address in BorrowerOperations', async () => {
    const defaultPoolAddress = defaultPool.address

    const recordedDefaultPoolAddress = await borrowerOperations.defaultPool()
    assert.equal(defaultPoolAddress, recordedDefaultPoolAddress)
  })

  // LQTY Staking in BO
  it('Sets the correct FeeRecipient address in BorrowerOperations', async () => {
    const lqtyStakingAddress = feeRecipient.address

    const recordedLQTYStakingAddress = await borrowerOperations.lqtyStakingAddress()
    assert.equal(lqtyStakingAddress, recordedLQTYStakingAddress)
  })


  // --- LQTY Staking ---

  // Sets ActivePool in FeeRecipient
  it('Sets the correct ActivePool address in FeeRecipient', async () => {
    const activePoolAddress = activePool.address

    const recordedActivePoolAddress = await feeRecipient.activePoolAddress()
    assert.equal(activePoolAddress, recordedActivePoolAddress)
  })

  // Sets EBTCToken in FeeRecipient
  it('Sets the correct ActivePool address in FeeRecipient', async () => {
    const ebtcTokenAddress = ebtcToken.address

    const recordedEBTCTokenAddress = await feeRecipient.ebtcToken()
    assert.equal(ebtcTokenAddress, recordedEBTCTokenAddress)
  })

  // Sets CdpManager in FeeRecipient
  it('Sets the correct ActivePool address in FeeRecipient', async () => {
    const cdpManagerAddress = cdpManager.address

    const recordedCdpManagerAddress = await feeRecipient.cdpManagerAddress()
    assert.equal(cdpManagerAddress, recordedCdpManagerAddress)
  })

  // Sets BorrowerOperations in FeeRecipient
  it('Sets the correct BorrowerOperations address in FeeRecipient', async () => {
    const borrowerOperationsAddress = borrowerOperations.address

    const recordedBorrowerOperationsAddress = await feeRecipient.borrowerOperationsAddress()
    assert.equal(borrowerOperationsAddress, recordedBorrowerOperationsAddress)
  })

  // Sets CollateralToken in FeeRecipient
  it('Sets the correct CollateralToken address in FeeRecipient', async () => {
    const borrowerOperationsAddress = borrowerOperations.address

    const recordedBorrowerOperationsAddress = await feeRecipient.borrowerOperationsAddress()
    assert.equal(borrowerOperationsAddress, recordedBorrowerOperationsAddress)
  })
})
