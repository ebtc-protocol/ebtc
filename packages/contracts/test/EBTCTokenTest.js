const deploymentHelper = require("../utils/deploymentHelpers.js")
const testHelpers = require("../utils/testHelpers.js")

const { keccak256 } = require('@ethersproject/keccak256');
const { defaultAbiCoder } = require('@ethersproject/abi');
const { toUtf8Bytes } = require('@ethersproject/strings');
const { pack } = require('@ethersproject/solidity');
const { hexlify } = require("@ethersproject/bytes");
const { ecsign, ecrecover, privateToPublic, pubToAddress } = require('ethereumjs-util');

const { toBN, assertRevert, assertAssert, dec, ZERO_ADDRESS } = testHelpers.TestHelper

const hre = require("hardhat");

const sign = (digest, privateKey) => {
  return ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(privateKey.slice(2), 'hex'))
}

const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
)

// Gets the EIP712 domain separator
const getDomainSeparator = (name, contractAddress, chainId, version)  => {
  return keccak256(defaultAbiCoder.encode(['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'], 
  [ 
    keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
    keccak256(toUtf8Bytes(name)), 
    keccak256(toUtf8Bytes(version)),
    parseInt(chainId), contractAddress.toLowerCase()
  ]))
}

// Returns the EIP712 hash which should be signed by the user
// in order to make a call to `permit`
const getPermitDigest = ( name, address, chainId, version,
                          owner, spender, value , 
                          nonce, deadline ) => {

  const DOMAIN_SEPARATOR = getDomainSeparator(name, address, chainId, version)
  return keccak256(pack(['bytes1', 'bytes1', 'bytes32', 'bytes32'],
    ['0x19', '0x01', DOMAIN_SEPARATOR, 
      keccak256(defaultAbiCoder.encode(
        ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
        [PERMIT_TYPEHASH, owner, spender, value, nonce, deadline])),
    ]))
}

contract('EBTCToken', async accounts => {
  const [owner, alice, bob, carol, dennis] = accounts;
  
  const hhAccounts = hre.config.networks.hardhat.accounts;
  const walletA = ethers.Wallet.fromMnemonic(hhAccounts.mnemonic, hhAccounts.path + `/1`);// the 1st-indexed address in accounts
  console.log('A=' + walletA.address + ':' + walletA.privateKey);

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(accounts.length - 3, accounts.length)

  // the second account our hardhatenv creates (for Alice)
  // from https://github.com/liquity/dev/blob/main/packages/contracts/hardhatAccountsList2k.js#L3
  const alicePrivateKey = walletA.privateKey

  let chainId
  let ebtcTokenOriginal
  let ebtcTokenTester
  let gasPool
  let cdpManager
  let borrowerOperations

  let tokenName
  let tokenVersion

  const testCorpus = ({ withProxy = false }) => {
    beforeEach(async () => {
      contracts = await deploymentHelper.deployTesterContractsHardhat()
      let LQTYContracts = {}
      LQTYContracts.feeRecipient = contracts.feeRecipient;

      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)

      ebtcTokenOriginal = contracts.ebtcToken
      if (withProxy) {
        const users = [ alice, bob, carol, dennis ]
        await deploymentHelper.deployProxyScripts(contracts, LQTYContracts, owner, users)
      }

      ebtcTokenTester = contracts.ebtcToken
      // for some reason this doesn’t work with coverage network
      //chainId = await web3.eth.getChainId()
      chainId = await ebtcTokenOriginal.getChainId()

      gasPool = contracts.gasPool
      cdpManager = contracts.cdpManager
      borrowerOperations = contracts.borrowerOperations

      tokenVersion = await ebtcTokenOriginal.version()
      tokenName = await ebtcTokenOriginal.name()

      // mint some tokens
      if (withProxy) {
        await ebtcTokenOriginal.unprotectedMint(ebtcTokenTester.getProxyAddressFromUser(alice), 150)
        await ebtcTokenOriginal.unprotectedMint(ebtcTokenTester.getProxyAddressFromUser(bob), 100)
        await ebtcTokenOriginal.unprotectedMint(ebtcTokenTester.getProxyAddressFromUser(carol), 50)
      } else {
        await ebtcTokenOriginal.unprotectedMint(alice, 150)
        await ebtcTokenOriginal.unprotectedMint(bob, 100)
        await ebtcTokenOriginal.unprotectedMint(carol, 50)
      }
    })

    it('balanceOf(): gets the balance of the account', async () => {
      const aliceBalance = (await ebtcTokenTester.balanceOf(alice)).toNumber()
      const bobBalance = (await ebtcTokenTester.balanceOf(bob)).toNumber()
      const carolBalance = (await ebtcTokenTester.balanceOf(carol)).toNumber()

      assert.equal(aliceBalance, 150)
      assert.equal(bobBalance, 100)
      assert.equal(carolBalance, 50)
    })

    it('totalSupply(): gets the total supply', async () => {
      const total = (await ebtcTokenTester.totalSupply()).toString()
      assert.equal(total, '300') // 300
    })

    it("name(): returns the token's name", async () => {
      const name = await ebtcTokenTester.name()
      assert.equal(name, "EBTC Stablecoin")
    })

    it("symbol(): returns the token's symbol", async () => {
      const symbol = await ebtcTokenTester.symbol()
      assert.equal(symbol, "EBTC")
    })

    it("decimal(): returns the number of decimal digits used", async () => {
      const decimals = await ebtcTokenTester.decimals()
      assert.equal(decimals, "18")
    })

    it("allowance(): returns an account's spending allowance for another account's balance", async () => {
      await ebtcTokenTester.approve(alice, 100, {from: bob})

      const allowance_A = await ebtcTokenTester.allowance(bob, alice)
      const allowance_D = await ebtcTokenTester.allowance(bob, dennis)

      assert.equal(allowance_A, 100)
      assert.equal(allowance_D, '0')
    })

    it("approve(): approves an account to spend the specified amount", async () => {
      const allowance_A_before = await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_before, '0')

      await ebtcTokenTester.approve(alice, 100, {from: bob})

      const allowance_A_after = await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_after, 100)
    })

    if (!withProxy) {
      it("approve(): reverts when spender param is address(0)", async () => {
        const txPromise = ebtcTokenTester.approve(ZERO_ADDRESS, 100, {from: bob})
        await assertAssert(txPromise)
      })

      it("approve(): reverts when owner param is address(0)", async () => {
        const txPromise = ebtcTokenTester.callInternalApprove(ZERO_ADDRESS, alice, dec(1000, 18), {from: bob})
        await assertAssert(txPromise)
      })
    }

    it("transferFrom(): successfully transfers from an account which is it approved to transfer from", async () => {
      const allowance_A_0 = await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_0, '0')

      await ebtcTokenTester.approve(alice, 50, {from: bob})

      // Check A's allowance of Bob's funds has increased
      const allowance_A_1= await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_1, 50)


      assert.equal(await ebtcTokenTester.balanceOf(carol), 50)

      // Alice transfers from bob to Carol, using up her allowance
      await ebtcTokenTester.transferFrom(bob, carol, 50, {from: alice})
      assert.equal(await ebtcTokenTester.balanceOf(carol), 100)

       // Check A's allowance of Bob's funds has decreased
      const allowance_A_2= await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_2, '0')

      // Check bob's balance has decreased
      assert.equal(await ebtcTokenTester.balanceOf(bob), 50)

      // Alice tries to transfer more tokens from bob's account to carol than she's allowed
      const txPromise = ebtcTokenTester.transferFrom(bob, carol, 50, {from: alice})
      await assertRevert(txPromise)
    })

    it("transfer(): increases the recipient's balance by the correct amount", async () => {
      assert.equal(await ebtcTokenTester.balanceOf(alice), 150)

      await ebtcTokenTester.transfer(alice, 37, {from: bob})

      assert.equal(await ebtcTokenTester.balanceOf(alice), 187)
    })

    it("transfer(): reverts if amount exceeds sender's balance", async () => {
      assert.equal(await ebtcTokenTester.balanceOf(bob), 100)

      const txPromise = ebtcTokenTester.transfer(alice, 101, {from: bob})
      await assertRevert(txPromise)
    })

    it('transfer(): transferring to a blacklisted address reverts', async () => {
      await assertRevert(ebtcTokenTester.transfer(ebtcTokenTester.address, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(ZERO_ADDRESS, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(cdpManager.address, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(borrowerOperations.address, 1, { from: alice }))
    })

    it("increaseAllowance(): increases an account's allowance by the correct amount", async () => {
      const allowance_A_Before = await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_Before, '0')

      await ebtcTokenTester.increaseAllowance(alice, 100, {from: bob} )

      const allowance_A_After = await ebtcTokenTester.allowance(bob, alice)
      assert.equal(allowance_A_After, 100)
    })

    if (!withProxy) {
      it('mint(): issues correct amount of tokens to the given address', async () => {
        const alice_balanceBefore = await ebtcTokenTester.balanceOf(alice)
        assert.equal(alice_balanceBefore, 150)

        await ebtcTokenTester.unprotectedMint(alice, 100)

        const alice_BalanceAfter = await ebtcTokenTester.balanceOf(alice)
        assert.equal(alice_BalanceAfter, 250)
      })

      it('burn(): burns correct amount of tokens from the given address', async () => {
        const alice_balanceBefore = await ebtcTokenTester.balanceOf(alice)
        assert.equal(alice_balanceBefore, 150)

        await ebtcTokenTester.unprotectedBurn(alice, 70)

        const alice_BalanceAfter = await ebtcTokenTester.balanceOf(alice)
        assert.equal(alice_BalanceAfter, 80)
      })

      // TODO: Rewrite this test - it should check the actual ebtcTokenTester's balance.
      it('unprotectedSendToPool(): changes balances of Gas pool and user by the correct amounts', async () => {
        const gasPool_BalanceBefore = await ebtcTokenTester.balanceOf(gasPool.address)
        const bob_BalanceBefore = await ebtcTokenTester.balanceOf(bob)
        assert.equal(gasPool_BalanceBefore, 0)
        assert.equal(bob_BalanceBefore, 100)

        await ebtcTokenTester.unprotectedSendToPool(bob, gasPool.address, 75)

        const gasPool_BalanceAfter = await ebtcTokenTester.balanceOf(gasPool.address)
        const bob_BalanceAfter = await ebtcTokenTester.balanceOf(bob)
        assert.equal(gasPool_BalanceAfter, 75)
        assert.equal(bob_BalanceAfter, 25)
      })

      it('burn(): should revert if caller is neither BorrowerOperations nor CdpManager', async () => {
        await assertRevert(ebtcTokenTester.burn(bob, 75, {from: owner}), 'EBTC: Caller is neither BorrowerOperations nor CdpManager')
      })
    }

    it('transfer(): transferring to a blacklisted address reverts', async () => {
      await assertRevert(ebtcTokenTester.transfer(ebtcTokenTester.address, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(ZERO_ADDRESS, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(cdpManager.address, 1, { from: alice }))
      await assertRevert(ebtcTokenTester.transfer(borrowerOperations.address, 1, { from: alice }))
    })

    it('decreaseAllowance(): decreases allowance by the expected amount', async () => {
      await ebtcTokenTester.approve(bob, dec(3, 18), { from: alice })
      assert.equal((await ebtcTokenTester.allowance(alice, bob)).toString(), dec(3, 18))
      await ebtcTokenTester.decreaseAllowance(bob, dec(1, 18), { from: alice })
      assert.equal((await ebtcTokenTester.allowance(alice, bob)).toString(), dec(2, 18))
    })

    it('decreaseAllowance(): fails trying to decrease more than previously allowed', async () => {
      await ebtcTokenTester.approve(bob, dec(3, 18), { from: alice })
      assert.equal((await ebtcTokenTester.allowance(alice, bob)).toString(), dec(3, 18))
      await assertRevert(ebtcTokenTester.decreaseAllowance(bob, dec(4, 18), { from: alice }), 'ERC20: decreased allowance below zero')
      assert.equal((await ebtcTokenTester.allowance(alice, bob)).toString(), dec(3, 18))
    })

    // EIP2612 tests

    if (!withProxy) {
      it("version(): returns the token contract's version", async () => {
        const version = await ebtcTokenTester.version()
        assert.equal(version, "1")
      })

      it('Initializes PERMIT_TYPEHASH correctly', async () => {
        assert.equal(await ebtcTokenTester.permitTypeHash(), PERMIT_TYPEHASH)
      })

      it('Initializes DOMAIN_SEPARATOR correctly', async () => {
        assert.equal(await ebtcTokenTester.domainSeparator(),
                     getDomainSeparator(tokenName, ebtcTokenTester.address, chainId, tokenVersion))
      })

      it('Initial nonce for a given address is 0', async function () {
        assert.equal(toBN(await ebtcTokenTester.nonces(alice)).toString(), '0');
      });

      // Create the approval tx data
      const approve = {
        owner: alice,
        spender: bob,
        value: 1,
      }

      const buildPermitTx = async (deadline) => {
        const nonce = (await ebtcTokenTester.nonces(approve.owner)).toString()

        // Get the EIP712 digest
        const digest = getPermitDigest(
          tokenName, ebtcTokenTester.address,
          chainId, tokenVersion,
          approve.owner, approve.spender,
          approve.value, nonce, deadline
        )

        const { v, r, s } = sign(digest, alicePrivateKey)

        const tx = ebtcTokenTester.permit(
          approve.owner, approve.spender, approve.value,
          deadline, v, hexlify(r), hexlify(s)
        )

        return { v, r, s, tx }
      }

      it('permits and emits an Approval event (replay protected)', async () => {
        const deadline = 100000000000000

        // Approve it
        const { v, r, s, tx } = await buildPermitTx(deadline)
        const receipt = await tx
        const event = receipt.logs[0]

        // Check that approval was successful
        assert.equal(event.event, 'Approval')
        assert.equal(await ebtcTokenTester.nonces(approve.owner), 1)
        assert.equal(await ebtcTokenTester.allowance(approve.owner, approve.spender), approve.value)

        // Check that we can not use re-use the same signature, since the user's nonce has been incremented (replay protection)
        await assertRevert(ebtcTokenTester.permit(
          approve.owner, approve.spender, approve.value,
          deadline, v, r, s), 'EBTC: invalid signature')

        // Check that the zero address fails
        await assertAssert(ebtcTokenTester.permit('0x0000000000000000000000000000000000000000',
                                                  approve.spender, approve.value, deadline, '0x99', r, s))
      })

      it('permits(): fails with expired deadline', async () => {
        const deadline = 1

        const { v, r, s, tx } = await buildPermitTx(deadline)
        await assertRevert(tx, 'EBTC: expired deadline')
      })

      it('permits(): fails with the wrong signature', async () => {
        const deadline = 100000000000000

        const { v, r, s } = await buildPermitTx(deadline)

        const tx = ebtcTokenTester.permit(
          carol, approve.spender, approve.value,
          deadline, v, hexlify(r), hexlify(s)
        )

        await assertRevert(tx, 'EBTC: invalid signature')
      })
    }
  }
  describe('Basic token functions, without Proxy', async () => {
    testCorpus({ withProxy: false })
  })

  describe('Basic token functions, with Proxy', async () => {
    testCorpus({ withProxy: true })
  })
})



contract('Reset chain state', async accounts => {})
