// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {BalanceSnapshot} from "./utils/BalanceSnapshot.sol";
import "../contracts/Interfaces/IPositionManagers.sol";

/*
 * Test suite that tests exactly one thing: opening CDPs
 * It tests different cases and also does random testing against random coll amounts and amount of users
 */
contract PositionManagersTest is eBTCBaseInvariants {
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
        returns (address user, address positionManager, bytes32 userCdpId)
    {
        collateral.setEthPerShare(1e18);
        priceFeedMock.setPrice(1e18);

        user = _utils.getNextUserAddress();
        positionManager = _utils.getNextUserAddress();
        dealCollateral(positionManager, STANDARD_COLL * 10);

        vm.prank(positionManager);
        collateral.approve(address(borrowerOperations), STANDARD_COLL * 10);

        userCdpId = _openTestCDP(user, STANDARD_COLL, STANDARD_DEBT);

        // open a second CDP so closing is possible
        _openTestCDP(user, STANDARD_COLL, STANDARD_DEBT);

        vm.prank(user);
        eBTCToken.transfer(positionManager, STANDARD_DEBT);

        // set positionManager
        vm.prank(user);
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.Persistent
        );

        tokens.push(address(eBTCToken));
        tokens.push(address(collateral));

        accounts.push(user);
        accounts.push(positionManager);
    }

    function test_UserCanSetPositionManagersForThemselves() public {
        address user = _utils.getNextUserAddress();
        address positionManager = _utils.getNextUserAddress();

        vm.startPrank(user);

        // set positionManager
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.Persistent
        );
        // confirm correct state
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );

        // unset positionManager
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.None
        );
        // confirm correct state
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.None
        );

        // set positionManager again
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.Persistent
        );
        // confirm correct state
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );

        // set positionManager again
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.Persistent
        );
        // confirm correct state
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );

        vm.stopPrank();
    }

    function test_UserCannotSetPositionManagersForOthers() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        vm.startPrank(user);
        address _otherUser = _utils.getNextUserAddress();

        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.Persistent
        );
        // confirm correct state
        assertFalse(
            borrowerOperations.getPositionManagerApproval(_otherUser, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(_otherUser, positionManager) ==
                IPositionManagers.PositionManagerApproval.None
        );

        vm.stopPrank();
    }

    function test_PositionManagerCanOpenCdpWithOneTimePermit() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        vm.prank(user);
        borrowerOperations.setPositionManagerApproval(
            positionManager,
            IPositionManagers.PositionManagerApproval.OneTime
        );

        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(positionManager);
        bytes32 _cdpOpenedByPositionManager = borrowerOperations.openCdpFor(
            STANDARD_DEBT,
            bytes32(0),
            bytes32(0),
            STANDARD_COLL,
            user
        );
        assertTrue(sortedCdps.contains(_cdpOpenedByPositionManager));
        assertTrue(sortedCdps.getOwnerAddress(_cdpOpenedByPositionManager) == user);
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore + 1,
            "CDP number mismatch for user after positionManager openCdpFor()"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.None
        );
    }

    function test_PositionManagerCanOpenCdp() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();
        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(positionManager);
        bytes32 _cdpOpenedByPositionManager = borrowerOperations.openCdpFor(
            STANDARD_DEBT,
            bytes32(0),
            bytes32(0),
            STANDARD_COLL,
            user
        );
        assertTrue(sortedCdps.contains(_cdpOpenedByPositionManager));
        assertTrue(sortedCdps.getOwnerAddress(_cdpOpenedByPositionManager) == user);
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore + 1,
            "CDP number mismatch for user after positionManager openCdpFor()"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    function test_PositionManagerCanWithdrawColl(uint collToWithdraw) public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        collToWithdraw = bound(
            collToWithdraw,
            borrowerOperations.MIN_CHANGE(),
            _getCdpStEthBalance(userCdpId) - cdpManager.MIN_NET_STETH_BALANCE() - 1
        );

        uint price = priceFeedMock.fetchPrice();
        uint newICR = hintHelpers.computeCR(
            _getCdpStEthBalance(userCdpId) - collToWithdraw,
            cdpManager.getCdpDebt(userCdpId),
            price
        );

        vm.assume(newICR >= borrowerOperations.MCR());

        // FIXME? collateral withdrawn to positionManager instead CDP owner?
        uint _balBefore = collateral.balanceOf(positionManager);
        vm.prank(positionManager);
        borrowerOperations.withdrawColl(userCdpId, collToWithdraw, bytes32(0), bytes32(0));
        assertEq(
            collateral.balanceOf(positionManager),
            _balBefore + collToWithdraw,
            "collateral not sent to correct recipient after withdrawColl()"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    /// @dev PositionManager should be able to increase collateral of Cdp
    /// @dev coll should come from positionManager's account
    function test_PositionManagerCanAddColl() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();
        uint _cdpColl = cdpManager.getCdpCollShares(userCdpId);
        uint _collChange = 1e17;

        BalanceSnapshot a = new BalanceSnapshot(tokens, accounts);

        vm.prank(positionManager);
        borrowerOperations.addColl(userCdpId, bytes32(0), bytes32(0), _collChange);

        BalanceSnapshot b = new BalanceSnapshot(tokens, accounts);

        assertEq(
            cdpManager.getCdpCollShares(userCdpId),
            _cdpColl + _collChange,
            "collateral in CDP mismatch after positionManager addColl()"
        );

        assertEq(
            a.get(address(collateral), positionManager),
            b.get(address(collateral), positionManager) + _collChange,
            "positionManager stEth balance should have decreased by increased stEth amount"
        );

        assertEq(
            a.get(address(collateral), user),
            b.get(address(collateral), user),
            "user stEth balance should remain the same"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    /// @dev PositionManager should be able to increase debt of Cdp
    /// @dev eBTC should go to positionManager's account
    function test_PositionManagerCanwithdrawDebt() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        // FIXME? debt withdrawn to positionManager instead CDP owner?
        uint _balBefore = eBTCToken.balanceOf(positionManager);
        uint _debtChange = 1e17;
        vm.prank(positionManager);
        borrowerOperations.withdrawDebt(userCdpId, _debtChange, bytes32(0), bytes32(0));
        assertEq(
            eBTCToken.balanceOf(positionManager),
            _balBefore + _debtChange,
            "debt not sent to correct recipient after withdrawDebt()"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    function test_PositionManagerCanrepayDebt() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        uint positionManagerBalanceBefore = eBTCToken.balanceOf(positionManager);
        uint userBalanceBefore = eBTCToken.balanceOf(user);

        vm.prank(positionManager);
        borrowerOperations.repayDebt(userCdpId, 1e17, bytes32(0), bytes32(0));

        assertEq(
            positionManagerBalanceBefore - eBTCToken.balanceOf(positionManager),
            1e17,
            "positionManager balance should be used to repay eBTC"
        );
        assertEq(
            userBalanceBefore,
            eBTCToken.balanceOf(user),
            "user balance should remain unchanged"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    function test_PositionManagerCanAdjustCdp() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        // FIXME? debt withdrawn to positionManager instead CDP owner?
        uint _balBefore = eBTCToken.balanceOf(positionManager);
        uint _debtChange = 1e17;
        vm.prank(positionManager);
        borrowerOperations.adjustCdp(userCdpId, 0, _debtChange, true, bytes32(0), bytes32(0));
        assertEq(
            eBTCToken.balanceOf(positionManager),
            _balBefore + _debtChange,
            "debt not sent to correct recipient after adjustCdp(_isDebtIncrease=true)"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    function test_PositionManagerCanAdjustCdpWithColl() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        BalanceSnapshot a = new BalanceSnapshot(tokens, accounts);

        uint positionManagerBalanceBefore = eBTCToken.balanceOf(positionManager);
        uint userBalanceBefore = eBTCToken.balanceOf(user);

        vm.prank(positionManager);
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
            a.get(address(eBTCToken), positionManager) - b.get(address(eBTCToken), positionManager),
            1e17,
            "positionManager balance should be used to repay eBTC"
        );
        assertEq(
            a.get(address(eBTCToken), user),
            b.get(address(eBTCToken), user),
            "user balance should remain unchanged"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }

    function test_PositionManagerCanCloseCdp() public {
        (address user, address positionManager, bytes32 userCdpId) = _testPreconditions();

        // close Cdp
        console.log("eBTCToken.balanceOf(positionManager): ", eBTCToken.balanceOf(positionManager));
        console.log("cdpManager.getCdpDebt(userCdpId): ", cdpManager.getCdpDebt(userCdpId));
        assertGe(eBTCToken.balanceOf(positionManager), cdpManager.getCdpDebt(userCdpId));

        uint _cdpOfUserBefore = sortedCdps.cdpCountOf(user);
        vm.prank(positionManager);
        borrowerOperations.closeCdp(userCdpId);
        assertFalse(sortedCdps.contains(userCdpId));
        assertEq(
            sortedCdps.cdpCountOf(user),
            _cdpOfUserBefore - 1,
            "CDP number mismatch for user after positionManager closeCdp()"
        );
        assertTrue(
            borrowerOperations.getPositionManagerApproval(user, positionManager) ==
                IPositionManagers.PositionManagerApproval.Persistent
        );
    }
}
