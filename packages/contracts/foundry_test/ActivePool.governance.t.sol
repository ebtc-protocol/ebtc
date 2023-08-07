pragma solidity 0.8.17;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseFixture} from "./BaseFixture.sol";
import {WethMock} from "../contracts/TestContracts/WethMock.sol";

contract ActivePoolGovernanceTest is eBTCBaseFixture {
    WethMock public mockToken;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();

        // Create mock token for sweeping
        mockToken = new WethMock();
    }

    function test_AuthorizedUserCanSweepTokens(uint amountInActivePool, uint amountToSweep) public {
        vm.assume(amountInActivePool > 0);
        vm.assume(amountInActivePool <= type(uint96).max);

        vm.assume(amountToSweep <= amountInActivePool);

        // Send a mock token for sweeping
        vm.prank(address(activePool));
        mockToken.deposit(amountInActivePool);

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool);

        // grant random user role
        address user = _utils.getNextUserAddress();
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 6, true);

        // user can sweep
        vm.prank(user);
        activePool.sweepToken(address(mockToken), amountToSweep);

        // confirm balances
        address feeRecipientAddress = activePool.feeRecipientAddress();

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool - amountToSweep);
        assertEq(mockToken.balanceOf(address(feeRecipientAddress)), amountToSweep);
    }

    function test_UnauthorizedUserCannotSweepTokens(
        uint amountInActivePool,
        uint amountToSweep
    ) public {
        vm.assume(amountInActivePool > 0);
        vm.assume(amountInActivePool <= type(uint96).max);

        vm.assume(amountToSweep <= amountInActivePool);

        // Send a mock token for sweeping
        vm.prank(address(activePool));
        mockToken.deposit(amountInActivePool);

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool);

        // random user cannot sweep
        address user = _utils.getNextUserAddress();
        vm.prank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.sweepToken(address(mockToken), amountToSweep);

        // confirm balances
        address feeRecipientAddress = activePool.feeRecipientAddress();

        assertEq(mockToken.balanceOf(address(activePool)), amountInActivePool);
        assertEq(mockToken.balanceOf(address(feeRecipientAddress)), 0);
    }

    function test_AuthorizedUserCannotSweepCollateral(uint amountToSweep) public {
        uint activePoolCollateralBefore = collateral.balanceOf(address(activePool));
        vm.assume(amountToSweep >= activePoolCollateralBefore);

        // grant random user role
        address user = _utils.getNextUserAddress();
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 6, true);

        // user cannot sweep collateral
        vm.prank(user);
        vm.expectRevert("ActivePool: Cannot Sweep Collateral");
        activePool.sweepToken(address(collateral), amountToSweep);

        // confirm balances
        assertEq(collateral.balanceOf(address(activePool)), activePoolCollateralBefore);
    }

    function test_UnauthorizedUserCannotSweepCollateral(uint amountToSweep) public {
        uint activePoolCollateralBefore = collateral.balanceOf(address(activePool));
        vm.assume(amountToSweep >= activePoolCollateralBefore);

        // random user cannot sweep collateral
        address user = _utils.getNextUserAddress();
        vm.prank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.sweepToken(address(collateral), amountToSweep);

        // confirm balances
        assertEq(collateral.balanceOf(address(activePool)), activePoolCollateralBefore);
    }

    function test_AuthorizedUserCanClaimOutstandingFeesToFeeRecipient(uint outstandingFees) public {
        vm.assume(outstandingFees > 0);
        vm.assume(outstandingFees <= type(uint64).max);
        address feeRecipientAddress = activePool.feeRecipientAddress();

        _sendCollateralToActivePoolAndAllocateAsClaimableFee(outstandingFees);

        // grant random user role
        address user = _utils.getNextUserAddress();
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 6, true);

        // user can call
        uint availableFees = activePool.getFeeRecipientClaimableCollShares();

        console.log("availableFees", availableFees);
        console.log(
            "activePool.getFeeRecipientClaimableCollShares()1",
            activePool.getFeeRecipientClaimableCollShares()
        );
        console.log(
            "collateral.balanceOf(feeRecipientAddress)1",
            collateral.sharesOf(feeRecipientAddress)
        );

        vm.prank(user);
        activePool.claimFeeRecipientCollShares(availableFees);

        uint claimableColl = activePool.getFeeRecipientClaimableCollShares();
        uint feeRecipientColl = collateral.sharesOf(feeRecipientAddress);

        console.log("activePool.getFeeRecipientClaimableCollShares()2", claimableColl);
        console.log("collateral.balanceOf(feeRecipientAddress)2", feeRecipientColl);

        assertEq(claimableColl, 0, "claimable coll remaining should be 0");
        assertEq(feeRecipientColl, availableFees, "fee recipient should gain claimable shares");
    }

    function test_UnauthorizedUserCannotClaimOutstandingFeesToFeeRecipient(
        uint outstandingFees
    ) public {
        vm.assume(outstandingFees > 0);
        vm.assume(outstandingFees <= type(uint64).max);
        address feeRecipientAddress = activePool.feeRecipientAddress();

        _sendCollateralToActivePoolAndAllocateAsClaimableFee(outstandingFees);

        // grant random user role
        address user = _utils.getNextUserAddress();

        // user can call
        uint availableFees = activePool.getFeeRecipientClaimableCollShares();

        vm.prank(user);
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.claimFeeRecipientCollShares(availableFees);

        uint claimableColl = activePool.getFeeRecipientClaimableCollShares();
        uint feeRecipientColl = collateral.sharesOf(feeRecipientAddress);

        assertEq(
            claimableColl,
            availableFees,
            "claimable coll remaining should be the same as before call"
        );
        assertEq(feeRecipientColl, 0, "fee recipient should not gain claimable shares");
    }

    function test_UserWithPermissionCanSetRecipientAddressToValidAddress(
        address _newRecipient
    ) public {
        vm.assume(_newRecipient != address(0));
        address user = _utils.getNextUserAddress();

        // grant permission to set the recipient address
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 5, true);

        // user sets recipient address
        vm.prank(user);
        activePool.setFeeRecipientAddress(_newRecipient);
        assertEq(_newRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToValidAddress(
        address _newRecipient
    ) public {
        vm.assume(_newRecipient != address(0));

        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        vm.prank(user);
        activePool.setFeeRecipientAddress(_newRecipient);
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithPermissionCannotSetRecipientAddressToZeroAddress() public {
        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // grant permission to set the recipient address
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 5, true);

        // user sets recipient address
        vm.prank(user);
        vm.expectRevert("ActivePool: Cannot set fee recipient to zero address");
        activePool.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }

    function test_UserWithoutPermissionCannotSetRecipientAddressToZeroAddress() public {
        address oldFeeRecipient = activePool.feeRecipientAddress();
        address user = _utils.getNextUserAddress();

        // user sets recipient address
        vm.expectRevert("Auth: UNAUTHORIZED");
        activePool.setFeeRecipientAddress(address(0));
        assertEq(oldFeeRecipient, activePool.feeRecipientAddress());
    }

    function _sendCollateralToActivePoolAndAllocateAsClaimableFee(uint amount) internal {
        // send actual tokens to activePool
        uint ethAmount = collateral.getPooledEthByShares(amount);

        vm.deal(address(activePool), ethAmount);

        vm.prank(address(activePool));
        collateral.deposit{value: ethAmount}();

        assertGe(
            collateral.balanceOf(address(activePool)),
            ethAmount,
            "at least ethAmount balance of coll should be in activePool"
        );
        assertGe(
            collateral.sharesOf(address(activePool)),
            amount,
            "at least amount of shares should be in activePool"
        );

        // allocate as system colalteral before allocating as fee
        vm.prank(address(borrowerOperations));
        activePool.receiveCollShares(amount);
        assertGe(
            activePool.getSystemCollShares(),
            amount,
            "at least amount of shares should be allocated as system coll"
        );

        // allocate from system -> claimable fee
        vm.prank(address(cdpManager));
        activePool.allocateSystemCollSharesToFeeRecipient(amount);
        assertGe(
            activePool.getFeeRecipientClaimableCollShares(),
            amount,
            "at lesat amount of shares should be allocated as claimable coll"
        );
    }
}
