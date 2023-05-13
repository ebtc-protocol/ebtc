const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")
const CdpManagerTester = artifacts.require("CdpManagerTester")

const th = testHelpers.TestHelper
const timeValues = testHelpers.TimeValues

const dec = th.dec
const toBN = th.toBN
const assertRevert = th.assertRevert

/* The majority of access control tests are contained in this file. However, tests for restrictions 
on the Liquity admin address's capabilities during the first year are found in:

test/launchSequenceTest/DuringLockupPeriodTest.js */

contract('Access Control: Liquity functions with the caller restricted to Liquity contract(s)', async accounts => {

  const [owner, alice, bob, carol] = accounts;
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let coreContracts

  let priceFeed
  let ebtcToken
  let sortedCdps
  let cdpManager
  let nameRegistry
  let activePool
  let functionCaller
  let borrowerOperations

  let feeRecipient

  before(async () => {
    coreContracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = coreContracts.feeRecipient;
    
    priceFeed = coreContracts.priceFeed
    ebtcToken = coreContracts.ebtcToken
    sortedCdps = coreContracts.sortedCdps
    cdpManager = coreContracts.cdpManager
    nameRegistry = coreContracts.nameRegistry
    activePool = coreContracts.activePool
    functionCaller = coreContracts.functionCaller
    borrowerOperations = coreContracts.borrowerOperations

    feeRecipient = LQTYContracts.feeRecipient

    await deploymentHelper.connectCoreContracts(coreContracts, LQTYContracts)

    for (account of accounts.slice(0, 10)) {
      await th.openCdp(coreContracts, { extraEBTCAmount: toBN(dec(20000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: account } })
    }
  })

  describe('CdpManager', async accounts => {
    // applyPendingRewards
    it("applyPendingRewards(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.applyPendingRewards(bob, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // updateRewardSnapshots
    it("updateRewardSnapshots(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.updateCdpRewardSnapshots(bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert" )
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // removeStake
    it("removeStake(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.removeStake(bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // updateStakeAndTotalStakes
    it("updateStakeAndTotalStakes(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.updateStakeAndTotalStakes(bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // closeCdp
    it("closeCdp(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.closeCdp(bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // addCdpOwnerToArray
    it("addCdpOwnerToArray(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.addCdpIdToArray(th.DUMMY_BYTES32, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // setCdpStatus
    it("setCdpStatus(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.setCdpStatus(bob, 1, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // increaseCdpColl
    it("increaseCdpColl(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.increaseCdpColl(bob, 100, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // decreaseCdpColl
    it("decreaseCdpColl(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.decreaseCdpColl(bob, 100, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // increaseCdpDebt
    it("increaseCdpDebt(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.increaseCdpDebt(bob, 100, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })

    // decreaseCdpDebt
    it("decreaseCdpDebt(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      try {
        const txAlice = await cdpManager.decreaseCdpDebt(bob, 100, { from: alice })
        
      } catch (err) {
         assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is not the BorrowerOperations contract")
      }
    })
  })

  describe('ActivePool', async accounts => {
    // sendETH
    it("sendStEthColl(): reverts when called by an account that is not BO nor CdpM", async () => {
      // Attempt call from alice
      try {
        const txAlice = await activePool.sendStEthColl(alice, 100, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, "Caller is neither BorrowerOperations nor CdpManager")
      }
    })

    // increaseEBTC	
    it("increaseEBTCDebt(): reverts when called by an account that is not BO nor CdpM", async () => {
      // Attempt call from alice
      try {
        const txAlice = await activePool.increaseEBTCDebt(100, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, "Caller is neither BorrowerOperations nor CdpManager")
      }
    })

    // decreaseEBTC
    it("decreaseEBTCDebt(): reverts when called by an account that is not BO nor CdpM", async () => {
      // Attempt call from alice
      try {
        const txAlice = await activePool.decreaseEBTCDebt(100, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, "Caller is neither BorrowerOperations nor CdpManager")
      }
    })

    // fallback (payment)	
    it("fallback(): reverts when called by an account that is not Borrower Operations nor Default Pool", async () => {
      // Attempt call from alice
      try {
        const txAlice = await web3.eth.sendTransaction({ from: alice, to: activePool.address, value: 100 })
        
      } catch (err) {
        assert.include(err.message, "revert")// no receive or fallback function
      }
    })
  })

  describe('EBTCToken', async accounts => {
    //    mint
    it("mint(): reverts when called by an account that is not BorrowerOperations", async () => {
      // Attempt call from alice
      const txAlice = ebtcToken.mint(bob, 100, { from: alice })
      await th.assertRevert(txAlice, "Caller is not BorrowerOperations")
    })

    // burn
    it("burn(): reverts when called by an account that is not BO nor CdpM nor SP", async () => {
      // Attempt call from alice
      try {
        const txAlice = await ebtcToken.burn(bob, 100, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is neither BorrowerOperations nor CdpManager nor StabilityPool")
      }
    })

    // returnFromPool
    it("returnFromPool(): reverts when called by an account that is not CdpManager", async () => {
      // Attempt call from alice
      try {
        const txAlice = await ebtcToken.returnFromPool(activePool.address, bob, 100, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        // assert.include(err.message, "Caller is neither CdpManager")
      }
    })
  })

  describe('SortedCdps', async accounts => {
    // --- onlyBorrowerOperations ---
    //     insert
    it("insert(): reverts when called by an account that is not BorrowerOps or CdpM", async () => {
      // Attempt call from alice
      try {
        const txAlice = await sortedCdps.insert(bob, '150000000000000000000', bob, bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, " Caller is neither BO nor CdpM")
      }
    })

    // --- onlyCdpManager ---
    // remove
    it("remove(): reverts when called by an account that is not CdpManager", async () => {
      // Attempt call from alice
      try {
        const txAlice = await sortedCdps.remove(bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, " Caller is not the CdpManager")
      }
    })

    // --- onlyCdpMorBM ---
    // reinsert
    it("reinsert(): reverts when called by an account that is neither BorrowerOps nor CdpManager", async () => {
      // Attempt call from alice
      try {
        const txAlice = await sortedCdps.reInsert(bob, '150000000000000000000', bob, bob, { from: alice })
        
      } catch (err) {
        assert.include(err.message, "revert")
        assert.include(err.message, "Caller is neither BO nor CdpM")
      }
    })
  })
})


