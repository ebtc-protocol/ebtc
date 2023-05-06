pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;
import {console2 as console} from "forge-std/console2.sol";

import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract CdpManagerLiquidationTest is eBTCBaseInvariants {
    address payable[] users;

    uint public constant DECIMAL_PRECISION = 1e18;

    address private splitFeeRecipient;
    mapping(bytes32 => uint) private _targetCdpPrevCollUnderlyings;
    mapping(bytes32 => uint) private _targetCdpPrevColls;
    mapping(bytes32 => uint) private _targetCdpPrevFeeApplied;

    struct LocalFeeSplitVar {
        uint _prevStFeePerUnitg;
        uint _prevTotalCollUnderlying;
    }

    ////////////////////////////////////////////////////////////////////////////
    // Staking Split Fee Invariants for ebtc system
    // - cdp_manager_fee1： global variable stFeePerUnitg is increasing upon rebasing up
    // - cdp_manager_fee2： global collateral is increasing upon rebasing up
    // - cdp_manager_fee3： active individual CDP collateral is increasing upon rebasing up
    // - cdp_manager_fee4： active individual CDP is associated with fee split according to its stake
    ////////////////////////////////////////////////////////////////////////////

    function _assert_cdp_manager_invariant_fee1(LocalFeeSplitVar memory _var) internal {
        assertGt(
            cdpManager.stFeePerUnitg(),
            _var._prevStFeePerUnitg,
            "System Invariant: cdp_manager_fee1"
        );
    }

    function _assert_cdp_manager_invariant_fee2(LocalFeeSplitVar memory _var) internal {
        assertGt(
            collateral.getPooledEthByShares(cdpManager.getEntireSystemColl()),
            _var._prevTotalCollUnderlying,
            "System Invariant: cdp_manager_fee2"
        );
    }

    function _assert_cdp_manager_invariant_fee3(LocalFeeSplitVar memory _var) internal {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        for (uint i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpManager.CdpIds(i));
            assertGt(
                collateral.getPooledEthByShares(_cdpState.coll),
                _targetCdpPrevCollUnderlyings[cdpManager.CdpIds(i)],
                "System Invariant: cdp_manager_fee3"
            );
        }
    }

    function _assert_cdp_manager_invariant_fee4(LocalFeeSplitVar memory _var) internal {
        uint _cdpCount = cdpManager.getCdpIdsCount();
        uint _prevTotalStake;
        for (uint i = 0; i < _cdpCount; ++i) {
            CdpState memory _cdpState = _getEntireDebtAndColl(cdpManager.CdpIds(i));
            uint _diffColl = _targetCdpPrevColls[cdpManager.CdpIds(i)] - _cdpState.coll;

            require(
                _utils.assertApproximateEq(
                    _diffColl,
                    _targetCdpPrevFeeApplied[cdpManager.CdpIds(i)],
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
        uint _stFeePerUnitg = cdpManager.stFeePerUnitg();
        uint _stFeePerUnitgError = cdpManager.stFeePerUnitgError();
        uint _totalStake = cdpManager.totalStakes();
        (uint _feeSplitDistributed, uint _newColl) = cdpManager.getAccumulatedFeeSplitApplied(
            _cdpId,
            _stFeePerUnitg,
            _stFeePerUnitgError,
            _totalStake
        );

        _targetCdpPrevFeeApplied[_cdpId] = _feeSplitDistributed / 1e18;

        vm.startPrank(_user);
        borrowerOperations.withdrawEBTC(_cdpId, 1, _cdpId, _cdpId);
        vm.stopPrank();
    }

    function _takeSplitFee(uint _totalColl, uint _expectedFee) internal {
        uint _feeBalBefore = collateral.balanceOf(splitFeeRecipient);
        cdpManager.claimStakingSplitFee();
        uint _feeBalAfter = collateral.balanceOf(splitFeeRecipient);
        uint _totalCollAfter = cdpManager.getEntireSystemColl();
        uint _feeBalDiff = _feeBalAfter - _feeBalBefore;
        require(
            _utils.assertApproximateEq(
                collateral.getPooledEthByShares(_totalColl - _totalCollAfter),
                _feeBalDiff,
                _tolerance
            ),
            "!SplitFeeInRecipient"
        );
        require(
            _utils.assertApproximateEq(
                collateral.getPooledEthByShares(_expectedFee),
                _feeBalDiff,
                _tolerance
            ),
            "!ExpectedSplitFee"
        );
    }

    function _populateCdpStatus(bytes32 _cdpId) internal {
        CdpState memory _cdpState = _getEntireDebtAndColl(_cdpId);
        _targetCdpPrevColls[_cdpId] = _cdpState.coll;
        _targetCdpPrevCollUnderlyings[_cdpId] = collateral.getPooledEthByShares(_cdpState.coll);
    }

    function _ensureDebtAmountValidity(uint _debtAmt) internal {
        vm.assume(_debtAmt > 1e18);
        vm.assume(_debtAmt < 10000e18);
    }

    // Test staking fee split with multiple rebasing up
    function testRebasingUps(uint256 debtAmt) public {
        _ensureDebtAmountValidity(debtAmt);

        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt, _curPrice, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt);

        uint _loop = 10;
        for (uint i = 0; i < _loop; ++i) {
            // get original status for the system
            uint _stFeePerUnitg = cdpManager.stFeePerUnitg();
            uint _totalColl = cdpManager.getEntireSystemColl();
            uint _totalCollUnderlying = collateral.getPooledEthByShares(_totalColl);

            // prepare CDP status for invariant check
            _populateCdpStatus(cdpId1);

            // ensure index sync interval
            skip(1 days);

            // Rebasing up
            uint _curIndex = collateral.getPooledEthByShares(1e18);
            uint _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            (uint _expectedFee, , ) = cdpManager.calcFeeUponStakingReward(_newIndex, _curIndex);

            // take fee split
            _takeSplitFee(_totalColl, _expectedFee);

            // apply split fee upon user operations
            _applySplitFee(cdpId1, users[0]);

            _ensureSystemInvariants();
            LocalFeeSplitVar memory _var = LocalFeeSplitVar(_stFeePerUnitg, _totalCollUnderlying);
            _ensureSystemInvariants_RebasingUp(_var);
        }
    }

    // Test staking fee split with multiple rebasing up for multiple CDPs
    function testRebasingUpsWithMultipleCDPs(
        uint256 debtAmt1,
        uint256 debtAmt2,
        uint256 debtAmt3
    ) public {
        _ensureDebtAmountValidity(debtAmt1);
        _ensureDebtAmountValidity(debtAmt2);
        _ensureDebtAmountValidity(debtAmt3);

        uint _curPrice = priceFeedMock.getPrice();
        uint256 coll1 = _utils.calculateCollAmount(debtAmt1, _curPrice, 297e16);
        uint256 coll2 = _utils.calculateCollAmount(debtAmt2, _curPrice, 297e16);
        uint256 coll3 = _utils.calculateCollAmount(debtAmt3, _curPrice, 297e16);

        bytes32 cdpId1 = _openTestCDP(users[0], coll1, debtAmt1);
        bytes32 cdpId2 = _openTestCDP(users[1], coll2, debtAmt2);
        bytes32 cdpId3 = _openTestCDP(users[2], coll3, debtAmt3);

        uint _loop = 10;
        for (uint i = 0; i < _loop; ++i) {
            // get original status for the system
            uint _stFeePerUnitg = cdpManager.stFeePerUnitg();
            uint _totalColl = cdpManager.getEntireSystemColl();
            uint _totalCollUnderlying = collateral.getPooledEthByShares(_totalColl);

            // prepare CDP status for invariant check
            _populateCdpStatus(cdpId1);
            _populateCdpStatus(cdpId2);
            _populateCdpStatus(cdpId3);

            // ensure index sync interval
            skip(1 days);

            // Rebasing up
            uint _curIndex = collateral.getPooledEthByShares(1e18);
            uint _newIndex = _curIndex + 5e16;
            collateral.setEthPerShare(_newIndex);
            (uint _expectedFee, , ) = cdpManager.calcFeeUponStakingReward(_newIndex, _curIndex);

            // take fee split
            _takeSplitFee(_totalColl, _expectedFee);

            // apply split fee upon user operations
            _applySplitFee(cdpId1, users[0]);
            _applySplitFee(cdpId2, users[1]);
            _applySplitFee(cdpId3, users[2]);

            _ensureSystemInvariants();
            LocalFeeSplitVar memory _var = LocalFeeSplitVar(_stFeePerUnitg, _totalCollUnderlying);
            _ensureSystemInvariants_RebasingUp(_var);
        }
    }
}
