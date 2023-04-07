const deploymentHelper = require("../../utils/deploymentHelpers.js")
const testHelpers = require("../../utils/testHelpers.js")


const th = testHelpers.TestHelper
const assertRevert = th.assertRevert
const toBN = th.toBN
const dec = th.dec

contract('Deploying the external contracts: FeeRecipient', async accounts => {
  const [liquityAG, A, B] = accounts;
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  let LQTYContracts

  const oneMillion = toBN(1000000)
  const digits = toBN(1e18)
  const thirtyTwo = toBN(32)
  const expectedCISupplyCap = thirtyTwo.mul(oneMillion).mul(digits)

  beforeEach(async () => {
    // Deploy all contracts from the first account
    LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)
    feeRecipient = LQTYContracts.feeRecipient

    //feeRecipient has not yet had its setters called, so is not yet
    // connected to the rest of the system
  })

  describe('FeeRecipient deployment', async accounts => {
    it("Stores the deployer's address", async () => {
      const storedDeployerAddress = await feeRecipient.owner()

      assert.equal(liquityAG, storedDeployerAddress)
    })
  })
})
