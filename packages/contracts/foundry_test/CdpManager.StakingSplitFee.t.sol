pragma solidity 0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    address private splitFeeRecipient;
    mapping(bytes32 => uint256) private _targetCdpPrevCollUnderlyings;
    mapping(bytes32 => uint256) private _targetCdpPrevColls;
    mapping(bytes32 => uint256) private _targetCdpPrevFeeApplied;

    // used to compare two values, in 1e18 scale
    uint private _compareTolerance = 1000000;

    struct LocalFeeSplitVar {
        uint256 _prevSystemStEthFeePerUnitIndex;
        uint256 _prevTotalCollUnderlying;
    }

    ////////////////////////////////////////////////////////////////////////////
    // Staking Split Fee Invariants for ebtc system
    // - cdp_manager_fee1： global variable systemStEthFeePerUnitIndex is increasing upon rebasing up
    // - cdp_manager_fee2： global collateral is increasing upon rebasing up
    // - cdp_manager_fee3： active individual CDP collateral is increasing upon rebasing up
    // - cdp_manager_fee4： active individual CDP is associated with fee split according to its stake
    ////////////////////////////////////////////////////////////////////////////

    function _assert_cdp_manager_invariant_fee1(LocalFeeSplitVar memory _var) internal {
        assertGt(
            cdpManager.systemStEthFeePerUnitIndex(),
            _var._prevSystemStEthFeePerUnitIndex,
            "System Invariant: cdp_manager_fee1"
        );
    }

    function _assert_cdp_manager_invariant_fee2(LocalFeeSplitVar memory _var) internal {
        assertGt(
            collateral.getPooledEthByShares(cdpManager.getSystemCollShares()),
            _var._prevTotalCollUnderlying,
            "System Invariant: cdp_manager_fee2"
        );
    }

    function _assert_cdp_manager_invariant_fee3(LocalFeeSplitVar memory _var) internal {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();

        for (uint256 i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getSyncedDebtAndCollShares(cdpIds[i]);
            assertGt(
                collateral.getPooledEthByShares(_cdpState.coll),
                _targetCdpPrevCollUnderlyings[cdpIds[i]],
                "System Invariant: cdp_manager_fee3"
            );
        }
    }

    function _assert_cdp_manager_invariant_fee4(LocalFeeSplitVar memory _var) internal view {
        uint256 _cdpCount = cdpManager.getActiveCdpsCount();
        bytes32[] memory cdpIds = hintHelpers.sortedCdpsToArray();

        for (uint256 i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getSyncedDebtAndCollShares(cdpIds[i]);
            uint256 _diffColl = _targetCdpPrevColls[cdpIds[i]] - _cdpState.coll;

            require(
                _utils.assertApproximateEq(
                    _diffColl,
                    _targetCdpPrevFeeApplied[cdpIds[i]],
                    _tolerance
                ),
                "!SplitFeeInCdp"
            );
        }
    }

    function _ensureSystemInvariants_RebasingUp(LocalFeeSplitVar memory _var) internal {
        _assert_cdp_manager_invariant_fee1(_var);
        _assert_cdp_manager_invariant_fee2(_var);
        _assert_cdp_manager_invariant_fee3(_var);
        _assert_cdp_manager_invariant_fee4(_var);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Tests
    ////////////////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        connectCoreContracts();
        connectLQTYContractsToCore();

        users = _utils.createUsers(3);

        splitFeeRecipient = address(feeRecipient);
    }

    function _applySplitFee(bytes32 _cdpId, address _user) internal {
        uint256 _systemStEthFeePerUnitIndex = cdpManager.systemStEthFeePerUnitIndex();
        (uint256 _feeSplitDistributed, ) = cdpManager.getAccumulatedFeeSplitApplied(
            _cdpId,
            _systemStEthFeePerUnitIndex
        );

        _targetCdpPrevFeeApplied[_cdpId] = _feeSplitDistributed / 1e18;

        vm.startPrank(_user);
        borrowerOperations.withdrawDebt(_cdpId, minChange, _cdpId, _cdpId);
        vm.stopPrank();
    }

    /// @dev Expect internal accounting allocated to fee recipient to change, and actual token balance to stay the same.
    /// @dev token balance would change when fee coll is claimed to fee recipient in getFeeRecipientClaimableCollShares()
    function _takeSplitFee(uint256 _totalColl, uint256 _expectedFee) internal {
        uint256 _totalCollBefore = _totalColl;
        uint256 _collateralTokensInActivePoolBefore = collateral.balanceOf(address(activePool));
        uint256 _internalAccountingCollBefore = activePool.getSystemCollShares();
        uint256 _feeBalBefore = collateral.balanceOf(splitFeeRecipient);
        uint256 _feeInternalAccountingBefore = activePool.getFeeRecipientClaimableCollShares();

        cdpManager.syncGlobalAccountingAndGracePeriod();

        uint256 _totalCollAfter = cdpManager.getSystemCollShares();
        uint256 _collateralTokensInActivePoolAfter = collateral.balanceOf(address(activePool));
        uint256 _internalAccountingCollAfter = activePool.getSystemCollShares();
        uint256 _feeBalAfter = collateral.balanceOf(splitFeeRecipient);
        uint256 _feeInternalAccountingAfter = activePool.getFeeRecipientClaimableCollShares();

        /**
        This split only updates internal accounting, all tokens remain in ActivePool, tokens are actually transfered by a pull model function to feeRecipient.
            - The amount of tokens in ActivePool stays the same
            - The amount of tokens in FeeRecipient stays the same

            - The internal accounting value of stETH allocated to system coll decreases by the fee
            - The total system collateral as read by CDPManager reflects this change
            - The internal accounting value of stETH allocated to FeeRecipient increases by the fee
        */

        require(
            _utils.assertApproximateEq(
                _collateralTokensInActivePoolBefore,
                _collateralTokensInActivePoolAfter,
                _tolerance
            ),
            "Total Collateral tokens in ActivePool should not change after split fee allocation"
        );

        require(
            _utils.assertApproximateEq(_feeBalAfter - _feeBalBefore, 0, _tolerance),
            "Split fee allocation should not change token balance of fee recipient"
        );

        require(
            _utils.assertApproximateEq(
                collateral.getPooledEthByShares(_expectedFee),
                collateral.getPooledEthByShares(
                    _internalAccountingCollBefore - _internalAccountingCollAfter
                ),
                _tolerance
            ),
            "System Collateral internal accounting ActivePool should decrease by the expected fee"
        );

        require(
            _utils.assertApproximateEq(
                collateral.getPooledEthByShares(_expectedFee),
                collateral.getPooledEthByShares(_totalCollBefore - _totalCollAfter),
                _tolerance
            ),
            "Total system collateral as read by CDPManager should change in-line with internal accounting, decreasing by the expected fee"
        );

        require(
            _utils.assertApproximateEq(
                collateral.getPooledEthByShares(_expectedFee),
                collateral.getPooledEthByShares(
                    _feeInternalAccountingAfter - _feeInternalAccountingBefore
                ),
                _tolerance
            ),
            "The amount of shares of the expected fee should be equal to the internal accounting allocated to fee recipient"
        );
    }

    function _populateCdpStatus(bytes32 _cdpId) internal {
        CdpState memory _cdpState = _getSyncedDebtAndCollShares(_cdpId);
        _targetCdpPrevColls[_cdpId] = _cdpState.coll;
        _targetCdpPrevCollUnderlyings[_cdpId] = collateral.getPooledEthByShares(_cdpState.coll);
    }

    // Test staking fee split with multiple rebasing up
    function testRebasingUps(uint256 debtAmt) public {
        debtAmt = bound(debtAmt, 1e18, 10000e18);

        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        uint256 _loop = 10;
        for (uint256 i = 0; i < _loop; ++i) {
            // get original status for the system
            uint256 _systemStEthFeePerUnitIndex = cdpManager.systemStEthFeePerUnitIndex();
            uint256 _totalColl = cdpManager.getSystemCollShares();
            uint256 _totalCollUnderlying = collateral.getPooledEthByShares(_totalColl);

            // prepare CDP status for invariant check
            _populateCdpStatus(cdpId1);

            // ensure index sync interval
            skip(1 days);

            // Rebasing up
            uint256 _curIndex = collateral.getPooledEthByShares(1e18);
            uint256 _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            (uint256 _expectedFee, , ) = cdpManager.calcFeeUponStakingReward(_newIndex, _curIndex);

            // take fee split
            _takeSplitFee(_totalColl, _expectedFee);

            // apply split fee upon user operations
            _applySplitFee(cdpId1, users[0]);

            _ensureSystemInvariants();
            LocalFeeSplitVar memory _var = LocalFeeSplitVar(
                _systemStEthFeePerUnitIndex,
                _totalCollUnderlying
            );
            _ensureSystemInvariants_RebasingUp(_var);
        }
    }

    // Test staking fee split with multiple rebasing up for multiple CDPs
    function testRebasingUpsWithMultipleCDPs(
        uint256 debtAmt1,
        uint256 debtAmt2,
        uint256 debtAmt3
    ) public {
        debtAmt1 = bound(debtAmt1, 1e18, 10000e18);
        debtAmt2 = bound(debtAmt2, 1e18, 10000e18);
        debtAmt3 = bound(debtAmt3, 1e18, 10000e18);

        uint256 _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);
        uint256 coll3 = _utils.calculateCollAmount(debtAmt3, _curPrice, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt1);
        bytes32 cdpId2 = _openTestCDP(users[1], coll2, debtAmt2);
        bytes32 cdpId3 = _openTestCDP(users[2], coll3, debtAmt3);

        uint256 _loop = 10;
        for (uint256 i = 0; i < _loop; ++i) {
            // get original status for the system
            uint256 _systemStEthFeePerUnitIndex = cdpManager.systemStEthFeePerUnitIndex();
            uint256 _totalColl = cdpManager.getSystemCollShares();
            uint256 _totalCollUnderlying = collateral.getPooledEthByShares(_totalColl);

            // prepare CDP status for invariant check
            _populateCdpStatus(cdpId1);
            _populateCdpStatus(cdpId2);
            _populateCdpStatus(cdpId3);

            // ensure index sync interval
            skip(1 days);

            // Rebasing up
            uint256 _curIndex = collateral.getPooledEthByShares(1e18);
            uint256 _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            (uint256 _expectedFee, , ) = cdpManager.calcFeeUponStakingReward(_newIndex, _curIndex);

            // take fee split
            _takeSplitFee(_totalColl, _expectedFee);

            // apply split fee upon user operations
            _applySplitFee(cdpId1, users[0]);
            _applySplitFee(cdpId2, users[1]);
            _applySplitFee(cdpId3, users[2]);

            _ensureSystemInvariants();
            LocalFeeSplitVar memory _var = LocalFeeSplitVar(
                _systemStEthFeePerUnitIndex,
                _totalCollUnderlying
            );
            _ensureSystemInvariants_RebasingUp(_var);
        }
    }

    function test_ZeroPecentStakingSplitFee_CdpOperations(uint256 debtAmt) public {
        debtAmt = bound(debtAmt, 1e18, 10000e18);

        uint256 price = priceFeedMock.getPrice();
        uint256 stEthBalance = _utils.calculateCollAmount(debtAmt, price, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], stEthBalance, debtAmt);

        // Set staking split fee to 0%
        vm.prank(defaultGovernance);
        cdpManager.setStakingRewardSplit(0);

        // rebase
        uint256 stEthIndex0 = collateral.getPooledEthByShares(1e18);
        collateral.setEthPerShare(stEthIndex0 * 1.1e18);
        uint256 stEthIndex1 = collateral.getPooledEthByShares(1e18);

        uint256 expectedUserCdpStEthBalance1 = _getCdpStEthBalance(cdpId1);
        uint256 expectedFeeRecipientBalance1 = activePool.getFeeRecipientClaimableCollShares();

        // accrue
        vm.startPrank(users[0]);
        cdpManager.syncAccounting(cdpId1);

        // fee recipient claimable balance should remain unchanged
        // entirety of rebase value increase should accrue to user cdp
        assertEq(_getCdpStEthBalance(cdpId1), expectedUserCdpStEthBalance1);
        assertEq(activePool.getFeeRecipientClaimableCollShares(), expectedFeeRecipientBalance1);

        vm.stopPrank();
    }

    function test_OneHundredPercentStakingSplitFee_CdpOperations(uint256 debtAmt) public {
        // Open Cdp
        debtAmt = bound(debtAmt, 1e18, 10000e18);

        uint256 price = priceFeedMock.getPrice();
        uint256 stEthBalance = _utils.calculateCollAmount(debtAmt, price, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], stEthBalance, debtAmt);

        // Set staking split fee to 100%
        uint256 _maxSplit = cdpManager.MAX_REWARD_SPLIT();
        vm.prank(defaultGovernance);
        cdpManager.setStakingRewardSplit(_maxSplit);

        // rebase
        uint256 stEthIndex0 = collateral.getPooledEthByShares(1e18);
        collateral.setEthPerShare((stEthIndex0 * 15e17) / 1e18);
        uint256 stEthIndex1 = collateral.getPooledEthByShares(1e18);

        (uint256 _expectedSplitFee, , ) = cdpManager.calcFeeUponStakingReward(
            stEthIndex1,
            stEthIndex0
        );
        uint256 _beforeUserCdpCollShare1 = cdpManager.getCdpCollShares(cdpId1);
        uint256 _beforeFeeRecipientShare1 = activePool.getFeeRecipientClaimableCollShares();

        // accrue
        vm.startPrank(users[0]);
        cdpManager.syncAccounting(cdpId1);

        // entirety of rebase value increase should go to fee recipient claimable balance
        _utils.assertApproximateEq(
            cdpManager.getCdpCollShares(cdpId1),
            _beforeUserCdpCollShare1 - _expectedSplitFee,
            _compareTolerance
        );
        _utils.assertApproximateEq(
            activePool.getFeeRecipientClaimableCollShares(),
            _beforeFeeRecipientShare1 + _expectedSplitFee,
            _compareTolerance
        );
    }

    function test_StaggeredCdpAccuralWithMultipleRebases(uint256 debtAmt) public {
        /**
            open identical Cdp 1+2
            rebase
            accure 1, but not 2

            verify state:
              - check expected virtual status of both via lens and synced values before
              - do accrual of 1
              - check expected virtual status of both via lens and synced values after
              - confirm real values are as expected (1 is same as virtual, 2 is as before the operation)

            rebase
            accrue both
            should be identical
         */
        (bytes32 cdpId1, bytes32 cdpId2) = _createTwoIdenticalCDPs(debtAmt);

        // first rebase and only sync one CDP
        uint256 stEthIndex1 = _rebaseAndCheckSplitFee(
            collateral.getPooledEthByShares(1e18),
            125e16,
            true,
            cdpId1,
            cdpId2
        );

        // second rebase and sync both CDPs
        _rebaseAndCheckSplitFee(stEthIndex1, 125e16, false, cdpId1, cdpId2);
    }

    function test_StaggeredCdpAccuralWithMultipleRebases_WithStakingSplitFeeChanges(
        uint256 debtAmt
    ) public {
        /**
            open identical Cdp 1+2
            set staking split fee to 80%
            rebase
            accure 1, but not 2
            set staking split fee to 10%
            rebase
            accrue both
            should be identical
         */
        (bytes32 cdpId1, bytes32 cdpId2) = _createTwoIdenticalCDPs(debtAmt);

        // first rebase and only sync one CDP
        vm.prank(defaultGovernance);
        cdpManager.setStakingRewardSplit(8_000);
        uint256 stEthIndex1 = _rebaseAndCheckSplitFee(
            collateral.getPooledEthByShares(1e18),
            125e16,
            true,
            cdpId1,
            cdpId2
        );

        // second rebase and sync both CDPs
        vm.prank(defaultGovernance);
        cdpManager.setStakingRewardSplit(1_000);
        _rebaseAndCheckSplitFee(stEthIndex1, 125e16, false, cdpId1, cdpId2);
    }

    function _createTwoIdenticalCDPs(uint256 debtAmt) internal returns (bytes32, bytes32) {
        debtAmt = bound(debtAmt, 1e18, 10000e18);
        uint256 stEthBalance = _utils.calculateCollAmount(debtAmt, priceFeedMock.getPrice(), 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], stEthBalance, debtAmt);
        bytes32 cdpId2 = _openTestCDP(users[1], stEthBalance, debtAmt);
        return (cdpId1, cdpId2);
    }

    function _syncIndividualCdp(bytes32 _cdpId) internal {
        vm.prank(users[2]);
        cdpManager.syncAccounting(_cdpId);
    }

    function _checkCollShareAfterSplitFee(
        bytes32 _cdpId,
        uint256 _expectedCollShare,
        uint256 _expectedPerUnit
    ) internal {
        (uint256 _scaledFee, ) = cdpManager.getAccumulatedFeeSplitApplied(_cdpId, _expectedPerUnit);
        uint256 _appliedFee = _scaledFee / 1e18;

        // sync given CDP
        uint256 _beforeCdpCollShare = cdpManager.getCdpCollShares(_cdpId);
        _syncIndividualCdp(_cdpId);
        uint256 _afterCdpCollShare = cdpManager.getCdpCollShares(_cdpId);

        // check collateral share after split fee applied against Lens or Synced view result
        assertEq(_expectedCollShare, _afterCdpCollShare);
        _utils.assertApproximateEq(
            _beforeCdpCollShare - _appliedFee,
            _afterCdpCollShare,
            _compareTolerance
        );
    }

    function _rebaseAndCheckSplitFee(
        uint256 _startStETHIndex,
        uint256 _rebaseIncrease,
        bool _syncOnlyOneCdp,
        bytes32 cdpId1,
        bytes32 cdpId2
    ) internal returns (uint256) {
        // rebase to get staking reward
        collateral.setEthPerShare((_startStETHIndex * _rebaseIncrease) / 1e18);

        // calculate expected split fee and delta value for perUnit index
        (uint256 _expectedSplitFee, uint256 _deltaPerUnit, ) = cdpManager.calcFeeUponStakingReward(
            collateral.getPooledEthByShares(1e18),
            _startStETHIndex
        );
        uint256 _expectedPerUnit = cdpManager.systemStEthFeePerUnitIndex() + _deltaPerUnit;
        uint256 _expectedCdp1CollShare = cdpManager.getSyncedCdpCollShares(cdpId1);
        uint256 _expectedCdp2CollShare = cdpManager.getSyncedCdpCollShares(cdpId2);
        uint256 _beforeFeeRecipientShare = activePool.getFeeRecipientClaimableCollShares();

        // sync CDP and check
        {
            _checkCollShareAfterSplitFee(cdpId1, _expectedCdp1CollShare, _expectedPerUnit);
            if (!_syncOnlyOneCdp) {
                _checkCollShareAfterSplitFee(cdpId2, _expectedCdp2CollShare, _expectedPerUnit);
            }

            // ONLY holds if two identical CDP
            _utils.assertApproximateEq(_expectedCdp1CollShare, _expectedCdp2CollShare, 123);

            // check fee receipient claimable balance
            _utils.assertApproximateEq(
                activePool.getFeeRecipientClaimableCollShares(),
                _beforeFeeRecipientShare + _expectedSplitFee,
                _compareTolerance
            );
        }
        return collateral.getPooledEthByShares(1e18);
    }
}
