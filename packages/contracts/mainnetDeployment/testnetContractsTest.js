const CollateralTokenTester = artifacts.require("./CollateralTokenTester.sol")

const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper

const { dec, assertRevert, toBN, ZERO_ADDRESS } = th

const hre = require("hardhat")


contract('CollateralTokenTester', async accounts => {
    const [owner, alice, bob] = accounts
    let collateralTokenTester

    describe('Unit tests', async () => {
        beforeEach(async () => {
            collateralTokenTester = await CollateralTokenTester.new(owner)
            CollateralTokenTester.setAsDeployed(collateralTokenTester)

            await collateralTokenTester.addUncappedMinter(bob, { from: owner })
        })

        it("Capped user can mint 10e18", async () => {
            await collateralTokenTester.forceDeposit(dec(10, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(10, 18))
        })

        it("Capped user can't mint more than 10e18", async () => {
            await assertRevert(collateralTokenTester.forceDeposit(dec(100, 18), { from: alice }))
            assert.equal(await collateralTokenTester.balanceOf(alice), 0)
        })

        it("Capped user mints can mint less than cap", async () => {
            await collateralTokenTester.forceDeposit(dec(8, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(8, 18))
        })

        it("Uncapped user can mint more than 10e18", async () => {
            await collateralTokenTester.forceDeposit(dec(100, 18), { from: bob })
            assert.equal(await collateralTokenTester.balanceOf(bob), dec(100, 18))
        })

        it("Uncapped user can't mint twice in a day", async () => {
            await collateralTokenTester.forceDeposit(dec(10, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(10, 18))
            await assertRevert(collateralTokenTester.forceDeposit(dec(10, 18), { from: alice }))
        })
    })

    describe('Integration tests', async () => {
        beforeEach(async () => {
            collateralTokenTester = await CollateralTokenTester.new(owner)
            CollateralTokenTester.setAsDeployed(collateralTokenTester)
        })

        it("Uncapped user can mint in different days", async () => {
            await collateralTokenTester.forceDeposit(dec(10, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(10, 18))

            // Slightly more than 24 hours pass
            await th.fastForwardTime(86401, web3.currentProvider)

            await collateralTokenTester.forceDeposit(dec(10, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(20, 18))

            // 12 hours pass
            await th.fastForwardTime(43200, web3.currentProvider)
            await assertRevert(collateralTokenTester.forceDeposit(dec(10, 18), { from: alice }))
        })

        it("User is added and removed from the uncapped list", async () => {
            await collateralTokenTester.addUncappedMinter(alice, { from: owner })

            await collateralTokenTester.forceDeposit(dec(100, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(100, 18))

            await collateralTokenTester.removeUncappedMinter(alice, { from: owner })

            // Alice is now a capped minter but can mint 10e18 more without waiting anytime
            await collateralTokenTester.forceDeposit(dec(10, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(110, 18))

            // Attempting to mint again reverts
            await assertRevert(collateralTokenTester.forceDeposit(dec(10, 18), { from: alice }))
        })

        it("Changing faucet parameters works properly", async () => {
            // Owner changes the deposit cap
            await collateralTokenTester.setMintCap(dec(5, 18), { from: owner })

            // Alice attempts to mint more and it fails
            await assertRevert(collateralTokenTester.forceDeposit(dec(10, 18), { from: alice }))
            // Alice attempts to mint the new cap amount and it works
            await collateralTokenTester.forceDeposit(dec(5, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(5, 18))

            // 12 hours go by and minting reverts for Alice
            await th.fastForwardTime(43200, web3.currentProvider)
            await assertRevert(collateralTokenTester.forceDeposit(dec(5, 18), { from: alice }))

            // Owner changes the cooldown period to 4 hrs
            await collateralTokenTester.setMintCooldown(60 * 60 * 4, { from: owner })

            // Alice can mint
            await collateralTokenTester.forceDeposit(dec(4, 18), { from: alice })
            assert.equal(await collateralTokenTester.balanceOf(alice), dec(9, 18))

            // Owner changes the deposit cap to something larger
            await collateralTokenTester.setMintCap(dec(30, 18), { from: owner })

            // Bob can mint this
            await collateralTokenTester.forceDeposit(dec(30, 18), { from: bob })
            assert.equal(await collateralTokenTester.balanceOf(bob), dec(30, 18))
        })

        it("Setter permissions work properly", async () => {
            await assertRevert(collateralTokenTester.setMintCap(dec(5, 18), { from: bob }))
            await assertRevert(collateralTokenTester.setMintCooldown(60 * 60 * 4, { from: bob }))
            await assertRevert(collateralTokenTester.addUncappedMinter(alice, { from: bob }))
            await assertRevert(collateralTokenTester.removeUncappedMinter(alice, { from: bob }))
        })
    })
})