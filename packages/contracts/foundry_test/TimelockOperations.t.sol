// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {TimelockController} from "@openzeppelin-contracts/governance/TimelockController.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Utilities} from "./utils/Utilities.sol";
import {WethMock} from "../contracts/TestContracts/WethMock.sol";


contract TimelockOperationsTest is eBTCBaseFixture {
    WethMock public mockToken;
    TimelockController public lowSecTimelock;
    TimelockController public highSecTimelock;
    address ecosystem;
    address systemOps;
    address techOps;

    // Governor auth functions
    bytes4 public constant ROLE_NAME_SIG = bytes4(keccak256(bytes("setRoleName(uint8,string)")));
    bytes4 public constant OWNERSHIP_SIG = bytes4(keccak256(bytes("transferOwnership(address)")));
    bytes4 public constant SET_AUTHORITY_SIG = bytes4(keccak256(bytes("setAuthority(address)")));

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Create mock token for sweeping
        mockToken = new WethMock();

        // Create mock multisigs
        ecosystem = _utils.getNextSpecialAddress();
        systemOps = _utils.getNextSpecialAddress();
        techOps = _utils.getNextSpecialAddress();

        // Timelocks deployment, configuration and wiring

        // Deploy High-Sec timelock
        vm.startPrank(defaultGovernance);
        address[] memory highSecManagers = new address[](1);
        highSecManagers[0] = ecosystem;
        highSecTimelock = new TimelockController(7 days, highSecManagers, highSecManagers, address(0));

        // Deploy Low-Sec timelock
        address[] memory lowSecManagers = new address[](3);
        lowSecManagers[0] = ecosystem;
        lowSecManagers[1] = systemOps;
        lowSecManagers[2] = techOps;
        lowSecTimelock = new TimelockController(2 days, lowSecManagers, lowSecManagers, address(0));
        vm.stopPrank();

        // revoke cancelling role from systemOps and techOps as necessary
        vm.startPrank(address(lowSecTimelock));
        lowSecTimelock.revokeRole(lowSecTimelock.CANCELLER_ROLE(), systemOps);
        lowSecTimelock.revokeRole(lowSecTimelock.CANCELLER_ROLE(), techOps);
        vm.stopPrank();

        // Assign all access roles to the timelocks according to spec
        vm.startPrank(defaultGovernance);

        // Grant the High-Sec timelock access to all functions
        authority.setUserRole(address(highSecTimelock), 0, true); // Admin
        // authority.setUserRole(address(highSecTimelock), 1, true); // eBTCToken: mint (timelock shouldn't mint)
        // authority.setUserRole(address(highSecTimelock), 2, true); // eBTCToken: burn (timelock shouldn't burn)
        authority.setUserRole(address(highSecTimelock), 3, true); // CDPManager: all
        authority.setUserRole(address(highSecTimelock), 4, true); // PriceFeed: setFallbackCaller
        authority.setUserRole(address(highSecTimelock), 5, true); // BorrowerOperations+ActivePool: setFeeBps, setFlashLoansPaused, setFeeRecipientAddress
        authority.setUserRole(address(highSecTimelock), 6, true); // ActivePool: sweep tokens & claim fee recipient coll

        // Grant the Low-Sec timelock access as per spec
        authority.setUserRole(address(lowSecTimelock), 3, true); // CDPManager: all
        authority.setUserRole(address(lowSecTimelock), 4, true); // PriceFeed: setFallbackCaller
        authority.setUserRole(address(lowSecTimelock), 5, true); // BorrowerOperations+ActivePool: setFeeBps, setFlashLoansPaused, setFeeRecipientAddress
        authority.setUserRole(address(lowSecTimelock), 6, true); // ActivePool: sweep tokens & claim fee recipient coll

        // Remove roles from defaultGov
        authority.setUserRole(defaultGovernance, 0, false); // Admin
        authority.setUserRole(defaultGovernance, 1, false); // eBTCToken: mint
        authority.setUserRole(defaultGovernance, 2, false); // eBTCToken: burn
        authority.setUserRole(defaultGovernance, 3, false); // CDPManager: all
        authority.setUserRole(defaultGovernance, 4, false); // PriceFeed: setFallbackCaller
        authority.setUserRole(defaultGovernance, 5, false); // BorrowerOperations+ActivePool: setFeeBps, setFlashLoansPaused, setFeeRecipientAddress
        authority.setUserRole(defaultGovernance, 6, false); // ActivePool: sweep tokens & claim fee recipient coll

        // Transfer Governance capabilities to high-sec timelock
        authority.setUserRole(address(highSecTimelock), 7, true);
        authority.setRoleName(7, "Governance");
        _grantAllGovernorCapabilitiesToRole(7);

        // Burn ownership (Altneratively it could be transferred to the high-sec tiemlock for a period of time before burning)
        // authority.transferOwnership(address(0));

        vm.stopPrank();
    }

    function test_timelockConfiguration() public {
        // High sec
        assertTrue(highSecTimelock.hasRole(highSecTimelock.PROPOSER_ROLE(), ecosystem));
        assertTrue(highSecTimelock.hasRole(highSecTimelock.EXECUTOR_ROLE(), ecosystem));
        assertTrue(highSecTimelock.hasRole(highSecTimelock.CANCELLER_ROLE(), ecosystem));
        // Only timelock itself has DEFAULT_ADMIN
        assertTrue(highSecTimelock.hasRole(highSecTimelock.TIMELOCK_ADMIN_ROLE(), address(highSecTimelock)));
        assertFalse(highSecTimelock.hasRole(highSecTimelock.TIMELOCK_ADMIN_ROLE(), ecosystem));

        // Low sec
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.PROPOSER_ROLE(), ecosystem));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.EXECUTOR_ROLE(), ecosystem));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.CANCELLER_ROLE(), ecosystem));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.PROPOSER_ROLE(), systemOps));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.EXECUTOR_ROLE(), systemOps));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.PROPOSER_ROLE(), techOps));
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.EXECUTOR_ROLE(), techOps));
        // Only timelock itself has DEFAULT_ADMIN
        assertTrue(lowSecTimelock.hasRole(lowSecTimelock.TIMELOCK_ADMIN_ROLE(), address(lowSecTimelock)));
        assertFalse(lowSecTimelock.hasRole(lowSecTimelock.TIMELOCK_ADMIN_ROLE(), ecosystem));
        assertFalse(lowSecTimelock.hasRole(lowSecTimelock.TIMELOCK_ADMIN_ROLE(), systemOps));
        assertFalse(lowSecTimelock.hasRole(lowSecTimelock.TIMELOCK_ADMIN_ROLE(), techOps));
    }

    // Test: The lowsec timelock can operate in one of the functions is is given permission over
    function test_lowsecTimelockCanOperate() public {
        uint256 amountInActivePool = 20e18;
        uint256 amountToSweep = 2e18;

        // Send a mock token for sweeping
        vm.prank(address(activePool));
        mockToken.deposit(amountInActivePool);

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool);

        // Sweep through Timelock
        vm.startPrank(techOps);
        _scheduleAndExecuteTimelockTx(
            lowSecTimelock,
            address(activePool),
            abi.encodeCall(
                activePool.sweepToken,
                (address(mockToken), amountToSweep)
            ),
            7 days + 1
        );
        vm.stopPrank();

        // confirm balances
        address feeRecipientAddress = activePool.feeRecipientAddress();

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool - amountToSweep);
        assertEq(mockToken.balanceOf(address(feeRecipientAddress)), amountToSweep);
    }

    function test_highsecTimelockCanOperate() public {
        uint256 amountInActivePool = 20e18;
        uint256 amountToSweep = 2e18;

        // Send a mock token for sweeping
        vm.prank(address(activePool));
        mockToken.deposit(amountInActivePool);

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool);

        // Sweep through Timelock
        vm.startPrank(ecosystem);
        _scheduleAndExecuteTimelockTx(
            highSecTimelock,
            address(activePool),
            abi.encodeCall(
                activePool.sweepToken,
                (address(mockToken), amountToSweep)
            ),
            7 days + 1
        );
        vm.stopPrank();

        // confirm balances
        address feeRecipientAddress = activePool.feeRecipientAddress();

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool - amountToSweep);
        assertEq(mockToken.balanceOf(address(feeRecipientAddress)), amountToSweep);
    }

    function test_onlyHighsecHasAdmin() public {
        // Dummy minter
        address minter = _utils.getNextSpecialAddress();
        assertFalse(authority.doesUserHaveRole(minter, 1)); // No role assigned yet

        // Attempt to perform adming function from lowSec Timelock
        vm.startPrank(techOps);
        _scheduleTimelockTx(
            lowSecTimelock,
            address(authority),
            abi.encodeCall(
                authority.setUserRole,
                (minter, 1, true) // minter
            ),
            2 days + 1
        ); // Can schedule it but executing should revert
        vm.warp(block.timestamp + 2 days + 1);
        vm.expectRevert("TimelockController: underlying transaction reverted");
        _executeTimelockTx(
            lowSecTimelock,
            address(authority),
            abi.encodeCall(
                authority.setUserRole,
                (minter, 1, true) // minter
            )
        );
        vm.stopPrank();

        // Attempt to schedule from highSec timelock with lowsec account (permissions test)
        vm.startPrank(techOps);
        vm.expectRevert();
        _scheduleTimelockTx(
            highSecTimelock,
            address(authority),
            abi.encodeCall(
                authority.setUserRole,
                (minter, 1, true) // minter
            ),
            7 days + 1
        );
        vm.stopPrank();

        // High sec user can use highSec timelock to perform admin operations (extensible minting, for instance)
        vm.startPrank(ecosystem);
        _scheduleAndExecuteTimelockTx(
            highSecTimelock,
            address(authority),
            abi.encodeCall(
                authority.setUserRole,
                (minter, 1, true) // minter
            ),
            7 days + 1
        );
        vm.stopPrank();
        assertTrue(authority.doesUserHaveRole(minter, 1));
    }

    /// @dev Helper function to grant all Governor setter capabilities to a specific role
    /// @dev Assumes default governance still has ownerships and is pranked
    function _grantAllGovernorCapabilitiesToRole(uint8 role) internal {
        // List of all setter function signatures in Governor contract
        bytes4[] memory funcSigs = new bytes4[](9);
        funcSigs[0] = bytes4(keccak256("setRoleName(uint8,string)"));
        funcSigs[1] = bytes4(keccak256("setUserRole(address,uint8,bool)"));
        funcSigs[2] = bytes4(keccak256("setRoleCapability(uint8,address,bytes4,bool)"));
        funcSigs[4] = bytes4(keccak256("setPublicCapability(address,bytes4,bool)"));
        funcSigs[6] = bytes4(keccak256("burnCapability(address,bytes4)"));
        funcSigs[7] = bytes4(keccak256("transferOwnership(address)"));
        funcSigs[8] = bytes4(keccak256("setAuthority(address)"));

        // Grant testRole all setter capabilities on authority
        for (uint256 i = 0; i < funcSigs.length; i++) {
            authority.setRoleCapability(role, address(authority), funcSigs[i], true);
        }
    }

    /// @dev Helper to schedule timelock transaction using default value, predecessor and salt
    /// @dev assumes prank of scheduler
    function _scheduleTimelockTx(TimelockController timelock, address target, bytes memory data, uint256 delay) internal {
        timelock.schedule(
            target,
            0,
            data,
            bytes32(0),
            bytes32(0),
            delay
        );
    }

    /// @dev Helper to schedule timelock transaction using default value, predecessor and salt
    /// @dev assumes prank of executor
    function _executeTimelockTx(TimelockController timelock, address target, bytes memory payload) internal {
        timelock.execute(
            target,
            0,
            payload,
            bytes32(0),
            bytes32(0)
        );
    }

    /// @dev Helper to schedule and execute timelock transaction using default value, predecessor and salt
    /// @dev assumes prank of shceduler/executor
    function _scheduleAndExecuteTimelockTx(TimelockController timelock, address target, bytes memory data, uint256 delay) internal {
        _scheduleTimelockTx(timelock, target, data, delay);
        vm.warp(block.timestamp + delay + 1);
        _executeTimelockTx(timelock, target, data);
    }
}
