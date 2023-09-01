// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {BalanceSnapshot} from "./utils/BalanceSnapshot.sol";
import {IDelegatePermit} from "../contracts/Interfaces/IDelegatePermit.sol";

/*
 * Test suite that tests permit sign feature of delegate
 */
contract DelegatePermitTest is eBTCBaseInvariants {
    uint256 internal constant userPrivateKey = 0xabc123;
    uint256 internal constant delegatePrivateKey = 0xabc987;
    uint256 internal constant deadline = 1800;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function _testPreconditions() internal returns (address user, address delegate) {
        user = vm.addr(userPrivateKey);
        delegate = vm.addr(delegatePrivateKey);
    }

    ///@dev Delegate should be valid until deadline
    function test_PermitValidUntilDeadline() public {
        (address user, address delegate) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IDelegatePermit.DelegateStatus _status = IDelegatePermit.DelegateStatus.Persistent;

        // set delegate via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(user, delegate, _status, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.prank(delegate);
        borrowerOperations.permitDelegate(user, delegate, _status, _deadline, v, r, s);
        assertTrue(borrowerOperations.getDelegateStatus(user, delegate) == _status);
    }

    ///@dev Delegate should be invalid after deadline
    function test_PermitInvalidAfterDeadline() public {
        (address user, address delegate) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IDelegatePermit.DelegateStatus _originalStatus = borrowerOperations.getDelegateStatus(
            user,
            delegate
        );
        IDelegatePermit.DelegateStatus _status = IDelegatePermit.DelegateStatus.Persistent;

        // set delegate via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(user, delegate, _status, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.warp(_deadline + 123);
        vm.expectRevert("BorrowerOperations: Delegate permit expired");
        borrowerOperations.permitDelegate(user, delegate, _status, _deadline, v, r, s);
        assertTrue(borrowerOperations.getDelegateStatus(user, delegate) == _originalStatus);
    }

    ///@dev Delegate should be invalid if not correct signed
    function test_PermitInvalidIfNotBorrower() public {
        (address user, address delegate) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IDelegatePermit.DelegateStatus _originalStatus = borrowerOperations.getDelegateStatus(
            user,
            delegate
        );
        IDelegatePermit.DelegateStatus _status = IDelegatePermit.DelegateStatus.Persistent;

        // set delegate via digest sign but with wrong signer
        vm.startPrank(delegate);
        bytes32 digest = _generatePermitSignature(user, delegate, _status, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatePrivateKey, digest);
        vm.stopPrank();

        vm.expectRevert("BorrowerOperations: Invalid signature");
        borrowerOperations.permitDelegate(user, delegate, _status, _deadline, v, r, s);
        assertTrue(borrowerOperations.getDelegateStatus(user, delegate) == _originalStatus);
    }

    ///@dev Delegate should be invalid if recovered signer is address zero
    function test_PermitInvalidIfZeroAddress() public {
        (address user, address delegate) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IDelegatePermit.DelegateStatus _originalStatus = borrowerOperations.getDelegateStatus(
            user,
            delegate
        );
        IDelegatePermit.DelegateStatus _status = IDelegatePermit.DelegateStatus.Persistent;

        // set delegate via digest sign but with wrong signer
        vm.startPrank(delegate);
        bytes32 digest = _generatePermitSignature(user, delegate, _status, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatePrivateKey, digest);
        vm.stopPrank();

        // tweak to always get zero address for ecrecover
        // https://gist.github.com/axic/5b33912c6f61ae6fd96d6c4a47afde6d#file-ecverify-sol-L85
        uint8 _wrongV = 17;
        address recoveredAddress = ecrecover(digest, _wrongV, r, s);
        assertTrue(recoveredAddress == address(0x0000000000000000000000000000));
        vm.expectRevert("BorrowerOperations: Invalid signature");
        borrowerOperations.permitDelegate(user, delegate, _status, _deadline, _wrongV, r, s);
        assertTrue(borrowerOperations.getDelegateStatus(user, delegate) == _originalStatus);
    }

    ///@dev Delegate should be valid until deadline
    function test_statusFuzzWithValidPermit(uint _status) public {
        (address user, address delegate) = _testPreconditions();
        vm.assume(_status <= 2);

        uint _deadline = (block.timestamp + deadline);
        uint _originalStatus = uint(borrowerOperations.getDelegateStatus(user, delegate));

        // set delegate via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(
            user,
            delegate,
            IDelegatePermit.DelegateStatus(_status),
            _deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.prank(delegate);
        borrowerOperations.permitDelegate(
            user,
            delegate,
            IDelegatePermit.DelegateStatus(_status),
            _deadline,
            v,
            r,
            s
        );
        uint _newStatus = uint(borrowerOperations.getDelegateStatus(user, delegate));
        assertTrue(_newStatus == _status);
        if (_status != _originalStatus) {
            assertTrue(_newStatus != _originalStatus);
        }
    }

    function _generatePermitSignature(
        address _signer,
        address _delegate,
        IDelegatePermit.DelegateStatus _status,
        uint _deadline
    ) internal returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                borrowerOperations.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        0xc32b434a2c378fdc15ea44c7ebd4ef778f1d0036638943e9f1e9785cb2f18401,
                        _signer,
                        _delegate,
                        _status,
                        borrowerOperations.nonces(_signer),
                        _deadline
                    )
                )
            )
        );
        return digest;
    }
}
