// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/LiquityMath.sol";
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

    // -------- `returnFromPool` happy path - called from `cdpManager` --------

    function test_returnFromPool() public {
        uint256 poolInitialBal = 0;

        vm.prank(address(cdpManager));
        eBTCToken.returnFromPool(address(activePool), owner, 5e18);

        assertGt(eBTCToken.balanceOf(owner), FAKE_MINTING_AMOUNT);
        assertLt(poolInitialBal, 5e18);
    }

    // -------- `increaseAllowance` for address(0) --------

    function testRevert_increaseAllowanceZeroAddr() public {
        vm.prank(address(owner));
        vm.expectRevert();
        eBTCToken.increaseAllowance(address(0), 1 ether);
    }

    // -------- `decreaseAllowance` when not prev approve --------

    function testRevert_decreaseAllowanceNotPriorApprove() public {
        vm.prank(address(owner));
        vm.expectRevert("ERC20: decreased allowance below zero");
        eBTCToken.decreaseAllowance(address(cdpManager), 1 ether);
    }
}

// helper for hash creation and signing
contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(Permit memory _permit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Permit memory _permit) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_permit)));
    }
}
