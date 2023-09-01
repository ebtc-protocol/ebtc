// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {BalanceSnapshot} from "./utils/BalanceSnapshot.sol";
import "../contracts/Interfaces/IDelegatePermit.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract DelegatesTest is eBTCBaseInvariants {
    // betaGang standard CDP
    uint public constant STANDARD_DEBT = 10 ether;
    uint public constant STANDARD_COLL = 20.2 ether;

    address[] public accounts;
    address[] public tokens;

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();
    }

    function _testPreconditions()
        internal
        returns (address user, address delegate, bytes32 userCdpId)
    {
        collateral.setEthPerShare(1e18);
        priceFeedMock.setPrice(1e18);

        user = _utils.getNextUserAddress();
        delegate = _utils.getNextUserAddress();
        dealCollateral(delegate, STANDARD_COLL * 10);

        vm.prank(delegate);
        collateral.approve(address(borrowerOperations), STANDARD_COLL * 10);

        userCdpId = _openTestCDP(user, STANDARD_COLL, STANDARD_DEBT);

        // open a second CDP so closing is possible
        _openTestCDP(user, STANDARD_COLL, STANDARD_DEBT);

        vm.prank(user);
        eBTCToken.transfer(delegate, STANDARD_DEBT);

        // set delegate
        vm.prank(user);
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.Persistent);

        tokens.push(address(eBTCToken));
        tokens.push(address(collateral));

        accounts.push(user);
        accounts.push(delegate);
    }

    function test_UserCanSetDelegatesForThemselves() public {
        address user = _utils.getNextUserAddress();
        address delegate = _utils.getNextUserAddress();

        vm.startPrank(user);

        // set delegate
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.Persistent);
        // confirm correct state
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );

        // unset delegate
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.None);
        // confirm correct state
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.None
        );

        // set delegate again
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.Persistent);
        // confirm correct state
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );

        // set delegate again
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.Persistent);
        // confirm correct state
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );

        vm.stopPrank();
    }

    function test_UserCannotSetDelegatesForOthers() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.startPrank(user);
        address _otherUser = _utils.getNextUserAddress();

        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.Persistent);
        // confirm correct state
        assertFalse(
            borrowerOperations.getDelegateStatus(_otherUser, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(_otherUser, delegate) ==
                IDelegatePermit.DelegateStatus.None
        );

        vm.stopPrank();
    }

    function test_DelegateCanOpenCdpWithOneTimePermit() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.prank(user);
        borrowerOperations.setDelegateStatus(delegate, IDelegatePermit.DelegateStatus.OneTime);

        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(delegate);
        bytes32 _cdpOpenedByDelegate = borrowerOperations.openCdpFor(
            STANDARD_DEBT,
            bytes32(0),
            bytes32(0),
            STANDARD_COLL,
            user
        );
        assertTrue(sortedCdps.contains(_cdpOpenedByDelegate));
        assertTrue(sortedCdps.getOwnerAddress(_cdpOpenedByDelegate) == user);
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore + 1,
            "CDP number mismatch for user after delegate openCdpFor()"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.None
        );
    }

    function test_DelegateCanOpenCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();
        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(delegate);
        bytes32 _cdpOpenedByDelegate = borrowerOperations.openCdpFor(
            STANDARD_DEBT,
            bytes32(0),
            bytes32(0),
            STANDARD_COLL,
            user
        );
        assertTrue(sortedCdps.contains(_cdpOpenedByDelegate));
        assertTrue(sortedCdps.getOwnerAddress(_cdpOpenedByDelegate) == user);
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore + 1,
            "CDP number mismatch for user after delegate openCdpFor()"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    function test_DelegateCanWithdrawColl(uint collToWithdraw) public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.assume(collToWithdraw > 0);
        vm.assume(collToWithdraw < cdpManager.getCdpStEthBalance(userCdpId));
        vm.assume(
            cdpManager.getCdpStEthBalance(userCdpId) - collToWithdraw > cdpManager.MIN_NET_COLL()
        );

        // FIXME? collateral withdrawn to delegate instead CDP owner?
        uint _balBefore = collateral.balanceOf(delegate);
        vm.prank(delegate);
        borrowerOperations.withdrawColl(userCdpId, collToWithdraw, bytes32(0), bytes32(0));
        assertEq(
            collateral.balanceOf(delegate),
            _balBefore + collToWithdraw,
            "collateral not sent to correct recipient after withdrawColl()"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    /// @dev Delegate should be able to increase collateral of Cdp
    /// @dev coll should come from delegate's account
    function test_DelegateCanAddColl() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();
        uint _cdpColl = cdpManager.getCdpColl(userCdpId);
        uint _collChange = 1e17;

        BalanceSnapshot a = new BalanceSnapshot(tokens, accounts);

        vm.prank(delegate);
        borrowerOperations.addColl(userCdpId, bytes32(0), bytes32(0), _collChange);

        BalanceSnapshot b = new BalanceSnapshot(tokens, accounts);

        assertEq(
            cdpManager.getCdpColl(userCdpId),
            _cdpColl + _collChange,
            "collateral in CDP mismatch after delegate addColl()"
        );

        assertEq(
            a.get(address(collateral), delegate),
            b.get(address(collateral), delegate) + _collChange,
            "delegate stEth balance should have decreased by increased stEth amount"
        );

        assertEq(
            a.get(address(collateral), user),
            b.get(address(collateral), user),
            "user stEth balance should remain the same"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    /// @dev Delegate should be able to increase debt of Cdp
    /// @dev eBTC should go to delegate's account
    function test_DelegateCanWithdrawEBTC() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        // FIXME? debt withdrawn to delegate instead CDP owner?
        uint _balBefore = eBTCToken.balanceOf(delegate);
        uint _debtChange = 1e17;
        vm.prank(delegate);
        borrowerOperations.withdrawEBTC(userCdpId, _debtChange, bytes32(0), bytes32(0));
        assertEq(
            eBTCToken.balanceOf(delegate),
            _balBefore + _debtChange,
            "debt not sent to correct recipient after withdrawEBTC()"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    function test_DelegateCanRepayEBTC() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        uint delegateBalanceBefore = eBTCToken.balanceOf(delegate);
        uint userBalanceBefore = eBTCToken.balanceOf(user);

        vm.prank(delegate);
        borrowerOperations.repayEBTC(userCdpId, 1e17, bytes32(0), bytes32(0));

        assertEq(
            delegateBalanceBefore - eBTCToken.balanceOf(delegate),
            1e17,
            "delegate balance should be used to repay eBTC"
        );
        assertEq(
            userBalanceBefore,
            eBTCToken.balanceOf(user),
            "user balance should remain unchanged"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    function test_DelegateCanAdjustCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        // FIXME? debt withdrawn to delegate instead CDP owner?
        uint _balBefore = eBTCToken.balanceOf(delegate);
        uint _debtChange = 1e17;
        vm.prank(delegate);
        borrowerOperations.adjustCdp(userCdpId, 0, _debtChange, true, bytes32(0), bytes32(0));
        assertEq(
            eBTCToken.balanceOf(delegate),
            _balBefore + _debtChange,
            "debt not sent to correct recipient after adjustCdp(_isDebtIncrease=true)"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    function test_DelegateCanAdjustCdpWithColl() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        BalanceSnapshot a = new BalanceSnapshot(tokens, accounts);

        uint delegateBalanceBefore = eBTCToken.balanceOf(delegate);
        uint userBalanceBefore = eBTCToken.balanceOf(user);

        vm.prank(delegate);
        borrowerOperations.adjustCdpWithColl(
            userCdpId,
            0,
            1e17,
            false,
            bytes32(0),
            bytes32(0),
            1e17
        );

        BalanceSnapshot b = new BalanceSnapshot(tokens, accounts);

        assertEq(
            a.get(address(eBTCToken), delegate) - b.get(address(eBTCToken), delegate),
            1e17,
            "delegate balance should be used to repay eBTC"
        );
        assertEq(
            a.get(address(eBTCToken), user),
            b.get(address(eBTCToken), user),
            "user balance should remain unchanged"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }

    function test_DelegateCanCloseCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        // close Cdp
        console.log("eBTCToken.balanceOf(delegate): ", eBTCToken.balanceOf(delegate));
        console.log("cdpManager.getCdpDebt(userCdpId): ", cdpManager.getCdpDebt(userCdpId));
        assertGe(eBTCToken.balanceOf(delegate), cdpManager.getCdpDebt(userCdpId));

        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(delegate);
        borrowerOperations.closeCdp(userCdpId);
        assertFalse(sortedCdps.contains(userCdpId));
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore - 1,
            "CDP number mismatch for user after delegate closeCdp()"
        );
        assertTrue(
            borrowerOperations.getDelegateStatus(user, delegate) ==
                IDelegatePermit.DelegateStatus.Persistent
        );
    }
}
