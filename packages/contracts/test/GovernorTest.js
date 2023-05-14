const deploymentHelper = require("../utils/deploymentHelpers.js")
const { TestHelper: th, MoneyValues: mv } = require("../utils/testHelpers.js")
const { toBN, dec, ZERO_ADDRESS } = th

const EBTCToken = artifacts.require("./EBTCToken.sol")
const GovernorTester = artifacts.require("./GovernorTester.sol");

const assertRevert = th.assertRevert

contract('Governor - access control entrypoint to permissioned functions', async accounts => {
  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)
  const [
    owner,
    alice, bob, carol, dennis, erin, freddy, greta, harry, ida,
    whale, defaulter_1, defaulter_2, defaulter_3, defaulter_4,
    A, B, C, D, E, F, G, H, I
  ] = accounts;

  let contracts
  let cdpManager
  let priceFeed
  let sortedCdps
  let collSurplusPool;
  let collToken;
  let governorTester;

  const openCdp = async (params) => th.openCdp(contracts, params)

  beforeEach(async () => {      
    contracts = await deploymentHelper.deployTesterContractsHardhat()
    let LQTYContracts = {}
    LQTYContracts.feeRecipient = contracts.feeRecipient;

    priceFeed = contracts.priceFeedTestnet
    sortedCdps = contracts.sortedCdps
    debtToken = contracts.ebtcToken;
    activePool = contracts.activePool;
    borrowerOperations = contracts.borrowerOperations;
    collSurplusPool = contracts.collSurplusPool;
    collToken = contracts.collateral;

    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
	
    // setup roles & users
    governorTester = await GovernorTester.new(owner);
    _funcSig1 = await governorTester.FUNC_SIG1();
  })
  
  it("Governor owner could call any function while non-authorized user could not", async() => {	  	  
      let _role1 = 1;  	  
      await governorTester.someFunc1({from: owner});  
      await assertRevert(governorTester.someFunc1({from: alice}), "Auth: UNAUTHORIZED");
      await assertRevert(governorTester.setPublicCapability(governorTester.address, _funcSig1, true, {from: alice}), "Auth: UNAUTHORIZED");
      await assertRevert(governorTester.setRoleCapability(_role1, governorTester.address, _funcSig1, true, {from: alice}), "Auth: UNAUTHORIZED");
      await assertRevert(governorTester.setUserRole(alice, _role1, true, {from: alice}), "Auth: UNAUTHORIZED");
      await assertRevert(governorTester.setRoleName(_role1, "abcde", {from: alice}), "Auth: UNAUTHORIZED");
  })
  
  it("Governor owner could transfer ownership to other address", async() => {	  	  
      let _role1 = 1;  	
      assert.isTrue(owner == (await governorTester.owner()));  
      await assertRevert(governorTester.someFunc1({from: alice}), "Auth: UNAUTHORIZED");
      await assertRevert(governorTester.transferOwnership(alice, {from: alice}), "Auth: UNAUTHORIZED");
      await governorTester.transferOwnership(alice, {from: owner});	
      assert.isTrue(alice == (await governorTester.owner()));  
      await governorTester.someFunc1({from: alice});  	
      await governorTester.setPublicCapability(governorTester.address, _funcSig1, true, {from: alice});
      await governorTester.setRoleCapability(_role1, governorTester.address, _funcSig1, true, {from: alice});
      await governorTester.setUserRole(alice, _role1, true, {from: alice});  
  })
  
  it("Governor could switch authority", async() => {	  
      let _role1 = 1;  	  	 	
      assert.isTrue(governorTester.address == (await governorTester.authority())); 	  
      let _newAuthority = await GovernorTester.new(alice);  
      await governorTester.setAuthority(_newAuthority.address, {from: owner});	
      assert.isTrue(_newAuthority.address == (await governorTester.authority())); 
	  
      // check new authority to grant permission
      await assertRevert(governorTester.someFunc1({from: alice}), "Auth: UNAUTHORIZED");
      await _newAuthority.setPublicCapability(governorTester.address, _funcSig1, true, {from: alice});
	  assert.isTrue((await _newAuthority.canCall(alice, governorTester.address, _funcSig1)));    
      await governorTester.someFunc1({from: alice});  
  })
  
  it("Good naming to role", async() => {	  
      let _role1 = 1;  	  
      let _role1Name = "Role1";  
      await governorTester.setRoleName(_role1, _role1Name, {from: owner});  
      assert.isTrue(_role1Name == (await governorTester.getRoleName(_role1)));
  })
  
  it("Non-authorized user could call target public function if enabled", async() => {	  
      await governorTester.setPublicCapability(governorTester.address, _funcSig1, true, {from: owner});  
      await governorTester.someFunc1({from: alice});  
	 
      // revoke publicity now 
      await governorTester.setPublicCapability(governorTester.address, _funcSig1, false, {from: owner}); 
      await assertRevert(governorTester.someFunc1({from: alice}), "Auth: UNAUTHORIZED");
  })
  
  it("Authorized users could call target function if enabled", async() => {	
      let _role1 = 1;  
      await governorTester.setRoleCapability(_role1, governorTester.address, _funcSig1, true, {from: owner});  
      let _role1CanCallFunc1 = await governorTester.doesRoleHaveCapability(_role1, governorTester.address, _funcSig1);
      assert.isTrue(_role1CanCallFunc1);
      let _enabledFunctions = await governorTester.getEnabledFunctionsInTarget(governorTester.address);
      assert.isTrue(_enabledFunctions.length == 1);
      assert.isTrue(_enabledFunctions[0] == _funcSig1);
	  
      // authorize alice & bob
      await governorTester.setUserRole(alice, _role1, true, {from: owner});  
      await governorTester.setUserRole(bob, _role1, true, {from: owner});  
      await governorTester.someFunc1({from: alice});   
      await governorTester.someFunc1({from: bob});  
	  
      // check roles
      let _role1Users = await governorTester.getUsersByRole(_role1);
      assert.isTrue(_role1Users.length == 2);
      assert.isTrue(_role1Users[0] == alice);
      assert.isTrue(_role1Users[1] == bob);
      let _aliceRoles = await governorTester.getRolesForUser(alice);
      assert.isTrue(_aliceRoles.length == 1);
      assert.isTrue(_aliceRoles[0] == _role1);
      let _bobRoles = await governorTester.getRolesForUser(bob);
      assert.isTrue(_bobRoles.length == 1);
      assert.isTrue(_bobRoles[0] == _role1);
	 
      // revoke authorization for alice now  
      await governorTester.setUserRole(alice, _role1, false, {from: owner});  
      await assertRevert(governorTester.someFunc1({from: alice}), "Auth: UNAUTHORIZED"); 
      _aliceRoles = await governorTester.getRolesForUser(alice);
      assert.isTrue(_aliceRoles.length == 0);
	  
      // revoke authorization for role1 now  
      await governorTester.setRoleCapability(_role1, governorTester.address, _funcSig1, false, {from: owner});  
      _enabledFunctions = await governorTester.getEnabledFunctionsInTarget(governorTester.address);
      assert.isTrue(_enabledFunctions.length == 0);
      _role1CanCallFunc1 = await governorTester.doesRoleHaveCapability(_role1, governorTester.address, _funcSig1);
      assert.isFalse(_role1CanCallFunc1);
      await assertRevert(governorTester.someFunc1({from: bob}), "Auth: UNAUTHORIZED");
  })
  
  it("Multiple roles could be authorized to call same function", async() => {	
      let _role1 = 1;  
      let _role2 = 2;  
      await governorTester.setRoleCapability(_role1, governorTester.address, _funcSig1, true, {from: owner});  
      await governorTester.setRoleCapability(_role2, governorTester.address, _funcSig1, true, {from: owner});
      let _role1CanCallFunc1 = await governorTester.doesRoleHaveCapability(_role1, governorTester.address, _funcSig1);
      let _role2CanCallFunc1 = await governorTester.doesRoleHaveCapability(_role2, governorTester.address, _funcSig1);
      assert.isTrue(_role1CanCallFunc1);
      assert.isTrue(_role2CanCallFunc1); 
	  
      // check authorized roles
      let _dataBytes = await governorTester.getByteMapFromRoles([_role1, _role2]);
      assert.isTrue(_dataBytes == (await governorTester.getRolesWithCapability(governorTester.address, _funcSig1)));
      let _roleIds = await governorTester.getRolesFromByteMap(_dataBytes);
      assert.isTrue(_roleIds.length == 2);
      assert.isTrue(_roleIds[0] == _role1);
      assert.isTrue(_roleIds[1] == _role2);
	  
      // assigne both roles to alice	  
      await governorTester.setUserRole(alice, _role1, true, {from: owner});  
      await governorTester.setUserRole(alice, _role2, true, {from: owner});  
      await governorTester.someFunc1({from: alice});   
	  
      // revoke role from alice now but still with another role
      await governorTester.setUserRole(alice, _role1, false, {from: owner});   
      await governorTester.someFunc1({from: alice});    
  })
  
})