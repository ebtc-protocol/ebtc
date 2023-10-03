// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {BalanceSnapshot} from "./utils/BalanceSnapshot.sol";
import {IPositionManagers} from "../contracts/Interfaces/IPositionManagers.sol";

/*
 * Test suite that tests permit sign feature of positionManager
 */
contract PositionManagerPermitTest is eBTCBaseInvariants {
    uint256 internal constant userPrivateKey = 0xabc123;
    uint256 internal constant positionManagerPrivateKey = 0xabc987;
    uint256 internal constant deadline = 1800;

    function setUp() public override {
        super.setUp();
        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function _testPreconditions() internal returns (address user, address positionManager) {
        user = vm.addr(userPrivateKey);
        positionManager = vm.addr(positionManagerPrivateKey);
    }

    ///@dev PositionManager should be valid until deadline
    function test_PermitValidUntilDeadline() public {
        (address user, address positionManager) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .Persistent;

        // set positionManager via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(user, positionManager, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.prank(positionManager);
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            v,
            r,
            s
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) == _approval
        );
    }

    ///@dev signed permit should be valid until explicitly invalidate
    function test_PermitValidUntilExplicitlyInvalidate() public {
        (address user, address positionManager) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .Persistent;

        // set positionManager via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(user, positionManager, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.prank(positionManager);
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            v,
            r,
            s
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) == _approval
        );

        // now we invalidate the permit for the user
        vm.prank(user);
        borrowerOperations.increasePermitNonce();

        vm.expectRevert("BorrowerOperations: Invalid signature");
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            v,
            r,
            s
        );
    }

    ///@dev PositionManager should be invalid after deadline
    function test_PermitInvalidAfterDeadline() public {
        (address user, address positionManager) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _originalStatus = borrowerOperations
            .getPositionManagerApproval(user, positionManager);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .Persistent;

        // set positionManager via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(user, positionManager, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.warp(_deadline + 123);
        vm.expectRevert("BorrowerOperations: Position manager permit expired");
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            v,
            r,
            s
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) == _originalStatus
        );
    }

    ///@dev PositionManager should be invalid if not correct signed
    function test_PermitInvalidIfNotBorrower() public {
        (address user, address positionManager) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _originalStatus = borrowerOperations
            .getPositionManagerApproval(user, positionManager);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .Persistent;

        // set positionManager via digest sign but with wrong signer
        vm.startPrank(positionManager);
        bytes32 digest = _generatePermitSignature(user, positionManager, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(positionManagerPrivateKey, digest);
        vm.stopPrank();

        vm.expectRevert("BorrowerOperations: Invalid signature");
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            v,
            r,
            s
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) == _originalStatus
        );
    }

    ///@dev PositionManager should be invalid if recovered signer is address zero
    function test_PermitInvalidIfZeroAddress() public {
        (address user, address positionManager) = _testPreconditions();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _originalStatus = borrowerOperations
            .getPositionManagerApproval(user, positionManager);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .Persistent;

        // set positionManager via digest sign but with wrong signer
        vm.startPrank(positionManager);
        bytes32 digest = _generatePermitSignature(user, positionManager, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(positionManagerPrivateKey, digest);
        vm.stopPrank();

        // tweak to always get zero address for ecrecover
        // https://gist.github.com/axic/5b33912c6f61ae6fd96d6c4a47afde6d#file-ecverify-sol-L85
        uint8 _wrongV = 17;
        address recoveredAddress = ecrecover(digest, _wrongV, r, s);
        assertTrue(recoveredAddress == address(0x0000000000000000000000000000));
        vm.expectRevert("BorrowerOperations: Invalid signature");
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            _approval,
            _deadline,
            _wrongV,
            r,
            s
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) == _originalStatus
        );
    }

    ///@dev PositionManager should be valid until deadline
    function test_statusFuzzWithValidPermit(uint _approval) public {
        (address user, address positionManager) = _testPreconditions();
        _approval = bound(_approval, 0, 2);

        uint _deadline = (block.timestamp + deadline);
        uint _originalStatus = uint(
            borrowerOperations.getPositionManagerApproval(user, positionManager)
        );

        // set positionManager via digest sign
        vm.startPrank(user);
        bytes32 digest = _generatePermitSignature(
            user,
            positionManager,
            IPositionManagers.PositionManagerApproval(_approval),
            _deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        vm.stopPrank();

        vm.prank(positionManager);
        borrowerOperations.permitPositionManagerApproval(
            user,
            positionManager,
            IPositionManagers.PositionManagerApproval(_approval),
            _deadline,
            v,
            r,
            s
        );
        uint _newStatus = uint(borrowerOperations.getPositionManagerApproval(user, positionManager));
        assertTrue(_newStatus == _approval);
        if (_approval != _originalStatus) {
            assertTrue(_newStatus != _originalStatus);
        }
    }

    function _generatePermitSignature(
        address _signer,
        address _positionManager,
        IPositionManagers.PositionManagerApproval _approval,
        uint _deadline
    ) internal returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                borrowerOperations.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        borrowerOperations.permitTypeHash(),
                        _signer,
                        _positionManager,
                        _approval,
                        borrowerOperations.nonces(_signer),
                        _deadline
                    )
                )
            )
        );
        return digest;
    }
}
