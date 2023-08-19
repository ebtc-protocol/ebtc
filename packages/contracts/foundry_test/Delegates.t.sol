// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {BalanceSnapshot} from "./utils/BalanceSnapshot.sol";

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
        borrowerOperations.setDelegate(user, delegate, true);

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
        borrowerOperations.setDelegate(user, delegate, true);
        // confirm correct state
        assertTrue(borrowerOperations.isDelegate(user, delegate));

        // unset delegate
        borrowerOperations.setDelegate(user, delegate, false);
        // confirm correct state
        assertFalse(borrowerOperations.isDelegate(user, delegate));

        // set delegate again
        borrowerOperations.setDelegate(user, delegate, true);
        // confirm correct state
        assertTrue(borrowerOperations.isDelegate(user, delegate));

        // set delegate again
        borrowerOperations.setDelegate(user, delegate, true);
        // confirm correct state
        assertTrue(borrowerOperations.isDelegate(user, delegate));

        vm.stopPrank();
    }

    function test_UserCannotSetDelegatesForOthers() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        // attempt set delegate
        // confirm correct state

        // attempt unset delegate
        // confirm correct state

        // attempt set delegate again
        // confirm correct state
    }

    function test_DelegateCanOpenCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.prank(delegate);
        borrowerOperations.openCdp(STANDARD_DEBT, bytes32(0), bytes32(0), STANDARD_COLL);
    }

    function test_DelegateCanWithdrawColl(uint collToWithdraw) public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.assume(collToWithdraw > 0);
        vm.assume(collToWithdraw < cdpManager.getCdpStEthBalance(userCdpId));
        vm.assume(
            cdpManager.getCdpStEthBalance(userCdpId) - collToWithdraw > cdpManager.MIN_NET_COLL()
        );

        vm.prank(delegate);
        borrowerOperations.withdrawColl(userCdpId, collToWithdraw, bytes32(0), bytes32(0));
    }

    function test_DelegateCanAddColl() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.prank(delegate);
        borrowerOperations.addColl(userCdpId, bytes32(0), bytes32(0), 1e17);
    }

    function test_DelegateCanWithdrawEBTC() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.prank(delegate);
        borrowerOperations.withdrawEBTC(userCdpId, 1e17, bytes32(0), bytes32(0));
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
    }

    function test_DelegateCanWAdjustCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        vm.prank(delegate);
        borrowerOperations.adjustCdp(userCdpId, 0, 1e17, true, bytes32(0), bytes32(0));
    }

    function test_DelegateCanWAdjustCdpWithColl() public {
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
    }

    function test_DelegateCanCloseCdp() public {
        (address user, address delegate, bytes32 userCdpId) = _testPreconditions();

        // close Cdp
        console.log("eBTCToken.balanceOf(delegate): ", eBTCToken.balanceOf(delegate));
        console.log("cdpManager.getCdpDebt(userCdpId): ", cdpManager.getCdpDebt(userCdpId));
        assertGe(eBTCToken.balanceOf(delegate), cdpManager.getCdpDebt(userCdpId));

        vm.prank(delegate);
        borrowerOperations.closeCdp(userCdpId);
    }
}
