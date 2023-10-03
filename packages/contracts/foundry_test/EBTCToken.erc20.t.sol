// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {SigUtils} from "./utils/SigUtils.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test around basic erc20 functionality which are missing in JS suite
 * and get tested in isolation in this file for further coverage
 */
contract EBTCTokenErc20Test is eBTCBaseFixture {
    SigUtils internal sigUtils;

    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;

    address internal owner;
    address internal spender;

    uint256 constant FAKE_MINTING_AMOUNT = 10_000e18;

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        sigUtils = new SigUtils(eBTCToken.domainSeparator());

        // actors
        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);

        // mint few tokens for both actors
        deal(address(eBTCToken), owner, FAKE_MINTING_AMOUNT);
        deal(address(eBTCToken), spender, FAKE_MINTING_AMOUNT);
        deal(address(eBTCToken), address(activePool), 5e18);
    }

    // -------- EIP-2612 permit corner cases --------

    /// @notice This test checks if the permit function reverts when the nonce is invalid.
    function testRevert_invalidNonce() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 1, // owner nonce stored on-chain is 0
            deadline: block.timestamp
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert("EBTC: invalid signature");
        eBTCToken.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    /// @notice This test checks if the permit function reverts when the specified owner and signer are different (invalid).
    function testRevert_invalidSigner() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: block.timestamp
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(spenderPrivateKey, digest);

        vm.expectRevert("EBTC: invalid signature");
        eBTCToken.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);
    }

    /// @notice This test checks if the transferFrom function reverts after the permit function is used to add an allowance lower than the tranfer amount.
    function testRevert_transferFromPostPermitLowerAllowance() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: FAKE_MINTING_AMOUNT / 2,
            nonce: 0,
            deadline: block.timestamp
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        eBTCToken.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        eBTCToken.transferFrom(owner, spender, FAKE_MINTING_AMOUNT);
    }

    /// @notice This test checks if the transferFrom function successfully completes after a valid allowance is given via permit.
    function test_transferFromPostPermit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: FAKE_MINTING_AMOUNT,
            nonce: 0,
            deadline: block.timestamp
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        eBTCToken.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        eBTCToken.transferFrom(owner, spender, FAKE_MINTING_AMOUNT);

        assertEq(eBTCToken.balanceOf(owner), 0);
        assertEq(eBTCToken.balanceOf(spender), FAKE_MINTING_AMOUNT * 2);
        assertEq(eBTCToken.allowance(owner, spender), 0);
    }

    // -------- `increaseAllowance` for address(0) --------

    /// @notice This test checks if the increaseAllowance function reverts when the spender address is the zero address.
    function testRevert_increaseAllowanceZeroAddr() public {
        vm.prank(address(owner));
        vm.expectRevert();
        eBTCToken.increaseAllowance(address(0), 1 wei);
    }

    // -------- `decreaseAllowance` when not prev approve --------

    /// @notice This test checks if the decreaseAllowance function reverts when there was no prior approval for the given spender.
    function testRevert_decreaseAllowanceNotPriorApprove() public {
        vm.prank(address(owner));
        vm.expectRevert("ERC20: decreased allowance below zero");
        eBTCToken.decreaseAllowance(address(cdpManager), 1 wei);
    }
}
