// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";
import {Strings as StringUtils} from "./utils/Strings.sol";

contract HintHelpersTest is eBTCBaseInvariants {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    address payable[] users;

    uint256 public mintAmount = 1e18;
    uint public standardDebt = mintAmount;
    uint public minDebtChange = 1000;
    uint256 private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18
    uint256 crIncrement = 1e16;
    uint256 icrTarget;

    function setUp() public override {
        super.setUp();
        users = _utils.createUsers(1005);
        icrTarget = cdpManager.CCR() + crIncrement;
    }

    /// @dev Create n Cdps with different NICRs
    /// @dev A sorted list of sufficient size allows to test hints / insertions
    /// @return the CDP id and borrower at _rndTarget index of the creation ordering
    function _prepareCdps(uint n, uint _rndTarget) internal returns (bytes32, address) {
        uint256 price = priceFeedMock.fetchPrice();
        bytes32 _ret;
        address _retUsr;
        for (uint i = 0; i < n; i++) {
            uint targetIcr = icrTarget + (crIncrement * i);
            uint stEthCollateral = _utils.calculateCollAmount(standardDebt, price, targetIcr);
            bytes32 _cdpId = _openTestCDP(users[i], stEthCollateral, standardDebt);
            if (_rndTarget == i) {
                _ret = _cdpId;
                _retUsr = users[i];
            }
        }

        if (_ret == bytes32(0)) {
            _ret = sortedCdps.getLast();
            _retUsr = sortedCdps.getOwnerAddress(_ret);
        }
        return (_ret, _retUsr);
    }

    /// @dev return exact position that a CDP of a given ICR should be inserted into the list
    function _getExactHint(uint256 _CR) internal view returns (bytes32 exactHint) {
        console2.log("_targetNicr:", _CR);
        uint256 arrayLength = cdpManager.getActiveCdpsCount();

        // If the list is empty, return a non-existent ID as a hint.
        if (arrayLength == 0) {
            return sortedCdps.nonExistId();
        }

        bytes32 currentCdpId = sortedCdps.getFirst();
        uint256 currentNICR = cdpManager.getCachedNominalICR(currentCdpId);

        // If the CR is greater than or equal to the first node, return the first node as the hint.
        if (_CR >= currentNICR) {
            return currentCdpId;
        }

        // Walk through the list until we find the exact position.
        while (true) {
            bytes32 nextCdpId = sortedCdps.getNext(currentCdpId);

            // If reached the end of the list, return the last CDP as the hint.
            if (nextCdpId == sortedCdps.nonExistId()) {
                return currentCdpId;
            }

            uint256 nextNICR = cdpManager.getCachedNominalICR(nextCdpId);

            // Check if the CR fits between the current and the next CDP.
            if (_CR <= currentNICR && _CR >= nextNICR) {
                return nextCdpId;
            }

            // Move to the next node in the list.
            currentCdpId = nextCdpId;
            currentNICR = nextNICR;
        }
    }

    /// @dev Compare exact hint to approximate hint
    function test_OpenCdp_HintHelperInsert(
        uint n,
        uint targetIcr,
        uint numTrials,
        uint randomSeed
    ) public {
        n = bound(n, 3, 1000);

        // target ICR should be within range or just above
        uint256 _maxICR = cdpManager.CCR() + (crIncrement * n);
        targetIcr = bound(targetIcr, icrTarget, _maxICR);

        numTrials = bound(numTrials, 1, 15);

        _prepareCdps(n, 0);

        uint256 price = priceFeedMock.fetchPrice();
        uint256 _targetNicr = _convertICRToNICR(targetIcr, price);
        (bytes32 approxHint, , ) = hintHelpers.getApproxHint(targetIcr, numTrials, randomSeed);
        bytes32 exactHint = _getExactHint(_targetNicr);

        // Figure out how far apart these two positions are from each other

        // Insert using approxHint - this is to track gas consumption using the profiler
        // TODO: upper and lower hints
        bytes32 _originalLast = sortedCdps.getLast();
        bytes32 _originalFirst = sortedCdps.getFirst();
        uint stEthCollateral = _utils.calculateCollAmount(standardDebt, price, targetIcr);
        bytes32 _newCdpId = _openTestCDPWithHints(
            users[1001],
            stEthCollateral,
            standardDebt,
            approxHint,
            approxHint
        );

        console2.log("n:", n);
        console2.log("targetOpenIcr:", targetIcr);
        console2.log("numTrials:", numTrials);
        console2.log("price:", price);

        _checkExactHintAfterInsertion(_newCdpId, _originalLast, _originalFirst, exactHint);
    }

    /// @dev pick a random CDP, and adjust it to the randomized ICR inputted
    function test_AdjustCdp_HintHelperInsert(uint n, uint targetIcr) public {
        n = bound(n, 3, 1000);

        // target ICR should be within range or just above
        uint256 _maxICR = cdpManager.CCR() + (crIncrement * n);
        targetIcr = bound(targetIcr, icrTarget, _maxICR);

        uint256 _rndTarget = _utils.generateRandomNumber(0, n - 1, users[n]);

        (bytes32 _targetCDP, address _targetCDPOwner) = _prepareCdps(n, _rndTarget);

        uint256 price = priceFeedMock.fetchPrice();

        bytes32 _originalLast = sortedCdps.getLast();
        bytes32 _originalFirst = sortedCdps.getFirst();
        uint256 _targetExistColl = cdpManager.getSyncedCdpCollShares(_targetCDP);
        uint256 _targetExistDebt = cdpManager.getSyncedCdpDebt(_targetCDP);

        console2.log("n:", n);
        console2.log("targetAdjustIcr:", targetIcr);
        console2.log("price:", price);
        console2.log("_rndTarget:", _rndTarget);
        console2.log("_targetCDP:", StringUtils.bytes32ToString(_targetCDP));
        console2.log("_targetExistColl:", _targetExistColl);
        console2.log("_targetExistDebt:", _targetExistDebt);
        {
            bytes32 exactHint;
            uint256 _targetNewNICR;
            uint256 _targetCDPCurICR = cdpManager.getSyncedICR(_targetCDP, price);
            vm.startPrank(_targetCDPOwner);
            if (_targetCDPCurICR < targetIcr) {
                // repay some debt to increase ICR
                uint256 _newDebt = (_targetExistColl * price) / targetIcr;
                uint256 _debtDelta = _targetExistDebt - _newDebt;
                _debtDelta = _debtDelta > minDebtChange ? _debtDelta : minDebtChange;
                _targetNewNICR = _calculateNICRWithAdjustment(
                    _targetExistColl,
                    _targetExistDebt,
                    0,
                    false,
                    _debtDelta,
                    false
                );
                exactHint = _getExactHint(_targetNewNICR);
                eBTCToken.approve(address(borrowerOperations), type(uint256).max);
                borrowerOperations.repayDebt(_targetCDP, _debtDelta, exactHint, exactHint);
            } else if (_targetCDPCurICR > targetIcr) {
                // borrow some debt to decrease ICR
                uint256 _newDebt = (_targetExistColl * price) / targetIcr;
                uint256 _debtDelta = _newDebt - _targetExistDebt;
                _debtDelta = _debtDelta > minDebtChange ? _debtDelta : minDebtChange;
                _targetNewNICR = _calculateNICRWithAdjustment(
                    _targetExistColl,
                    _targetExistDebt,
                    0,
                    false,
                    _debtDelta,
                    true
                );
                exactHint = _getExactHint(_targetNewNICR);
                borrowerOperations.withdrawDebt(_targetCDP, _debtDelta, exactHint, exactHint);
            } else {
                // simply add some collateral
                uint256 _colDelta = 10e18;
                dealCollateral(_targetCDPOwner, _colDelta);
                _targetNewNICR = _calculateNICRWithAdjustment(
                    _targetExistColl,
                    _targetExistDebt,
                    _colDelta,
                    true,
                    0,
                    false
                );
                exactHint = _getExactHint(_targetNewNICR);
                borrowerOperations.addColl(_targetCDP, exactHint, exactHint, _colDelta);
            }
            vm.stopPrank();
            _checkExactHintAfterInsertion(_targetCDP, _originalLast, _originalFirst, exactHint);
        }
    }

    /// @dev Compare exact hint for partial redemption
    function test_PartiallyRedeem_HintHelperReInsert(
        uint n,
        uint redeemedDebt,
        uint randomSeed
    ) public {
        n = bound(n, 3, 1000);

        redeemedDebt = bound(redeemedDebt, crIncrement, standardDebt - crIncrement);

        _prepareCdps(n, 0);

        uint256 price = priceFeedMock.fetchPrice();
        (bytes32 firstRedempHint, uint256 partialRedempNICR, , ) = hintHelpers.getRedemptionHints(
            redeemedDebt,
            price,
            0
        );

        uint256 _targetExistColl = cdpManager.getSyncedCdpCollShares(firstRedempHint);
        uint256 _targetExistDebt = cdpManager.getSyncedCdpDebt(firstRedempHint);
        require(redeemedDebt < _targetExistDebt, "not partial redemption!");

        uint256 _targetNicr = _calculateNICRWithAdjustment(
            _targetExistColl,
            _targetExistDebt,
            (redeemedDebt * 1e18) / price,
            false,
            redeemedDebt,
            false
        );
        bytes32 exactHint = _getExactHint(_targetNicr);

        bytes32 _originalLast = sortedCdps.getLast();
        bytes32 _originalFirst = sortedCdps.getFirst();

        // get redemption hints
        {
            (bytes32 approxHint, , ) = hintHelpers.getApproxHint(_targetNicr, 14, randomSeed);
            (bytes32 upperHint, bytes32 lowerHint) = sortedCdps.findInsertPosition(
                _targetNicr,
                approxHint,
                approxHint
            );
            _syncSystemDebtTwapToSpotValue();
            vm.startPrank(sortedCdps.getOwnerAddress(firstRedempHint));
            cdpManager.redeemCollateral(
                redeemedDebt,
                firstRedempHint,
                upperHint,
                lowerHint,
                partialRedempNICR,
                0,
                1e18
            );
            vm.stopPrank();
        }

        console2.log("n:", n);
        console2.log("redeemedDebt:", redeemedDebt);
        console2.log("price:", price);

        _checkExactHintAfterInsertion(firstRedempHint, _originalLast, _originalFirst, exactHint);
    }

    /// @dev Compare exact hint for partial liquidation
    function test_PartiallyLiquidate_HintHelperReInsert(
        uint n,
        uint repaidDebt,
        uint randomSeed
    ) public {
        n = bound(n, 3, 1000);

        repaidDebt = bound(repaidDebt, crIncrement, (standardDebt - 30 * crIncrement));

        _prepareCdps(n, 0);

        bytes32 _originalLast = sortedCdps.getLast();
        bytes32 _originalFirst = sortedCdps.getFirst();

        uint256 price = priceFeedMock.fetchPrice();
        bytes32 targetCdpId = _originalLast;

        uint256 _targetExistColl = cdpManager.getSyncedCdpCollShares(targetCdpId);
        uint256 _targetExistDebt = cdpManager.getSyncedCdpDebt(targetCdpId);
        require(repaidDebt < _targetExistDebt, "not partial liquidation!");

        // price drops to liquidate target CDP
        price =
            (price * (cdpManager.MCR() - crIncrement)) /
            cdpManager.getSyncedICR(targetCdpId, price);
        priceFeedMock.setPrice(price);
        price = priceFeedMock.fetchPrice();
        require(cdpManager.getSyncedICR(targetCdpId, price) < cdpManager.MCR(), "!not liquidatable");

        uint256 _targetNicr = _calculateNICRWithAdjustment(
            _targetExistColl,
            _targetExistDebt,
            (repaidDebt * cdpManager.getSyncedICR(targetCdpId, price)) / price,
            false,
            repaidDebt,
            false
        );
        bytes32 exactHint = _getExactHint(_targetNicr);

        // get liquidation hints
        {
            (bytes32 approxHint, , ) = hintHelpers.getApproxHint(_targetNicr, 14, randomSeed);
            (bytes32 upperHint, bytes32 lowerHint) = sortedCdps.findInsertPosition(
                _targetNicr,
                approxHint,
                approxHint
            );
            vm.startPrank(sortedCdps.getOwnerAddress(targetCdpId));
            cdpManager.partiallyLiquidate(targetCdpId, repaidDebt, upperHint, lowerHint);
            vm.stopPrank();
        }

        console2.log("n:", n);
        console2.log("repaidDebt:", repaidDebt);
        console2.log("price:", price);

        _checkExactHintAfterInsertion(targetCdpId, _originalLast, _originalFirst, exactHint);
    }

    function _calculateNICRWithAdjustment(
        uint256 _existColl,
        uint256 _existDebt,
        uint256 _collDelta,
        bool _collIncrease,
        uint256 _debtDelta,
        bool _debtIncrease
    ) internal returns (uint256) {
        uint256 _newColl = _collIncrease ? _existColl + _collDelta : _existColl - _collDelta;
        uint256 _newDebt = _debtIncrease ? _existDebt + _debtDelta : _existDebt - _debtDelta;
        require(_newDebt >= minDebtChange, "!too small debt");
        return (_newColl * 1e20) / _newDebt;
    }

    /// @dev NICR use different precision
    function _convertICRToNICR(uint256 _icr, uint256 _price) internal returns (uint256) {
        return (_icr * 1e20) / _price;
    }

    function _checkExactHintAfterInsertion(
        bytes32 _insertedCdpId,
        bytes32 _originalLast,
        bytes32 _originalFirst,
        bytes32 exactHint
    ) internal {
        uint256 _insertedCdpNICR = cdpManager.getSyncedNominalICR(_insertedCdpId);
        console2.log("_insertedCdpNICR:", _insertedCdpNICR);
        console2.log("exactHint:", StringUtils.bytes32ToString(exactHint));
        console2.log("_exactHintNICR:", cdpManager.getSyncedNominalICR(exactHint));

        if (sortedCdps.getLast() == _insertedCdpId) {
            console2.log("_originalLast:", StringUtils.bytes32ToString(_originalLast));
            console2.log("_originalLastNICR:", cdpManager.getSyncedNominalICR(_originalLast));
            require(
                (sortedCdps.getPrev(_insertedCdpId) == _originalLast ||
                    _originalLast == _insertedCdpId),
                "!New Last"
            );
        } else if (sortedCdps.getFirst() == _insertedCdpId) {
            console2.log("_originalFirst:", StringUtils.bytes32ToString(_originalFirst));
            console2.log("_originalFirstNICR:", cdpManager.getSyncedNominalICR(_originalFirst));
            require(
                (sortedCdps.getNext(_insertedCdpId) == _originalFirst ||
                    _originalFirst == _insertedCdpId),
                "!New First"
            );
        } else {
            bytes32 _next = sortedCdps.getNext(_insertedCdpId);
            console2.log("_next:", StringUtils.bytes32ToString(_next));
            console2.log("_nextNICR:", cdpManager.getSyncedNominalICR(_next));

            bytes32 _prev = sortedCdps.getPrev(_insertedCdpId);
            console2.log("_prev:", StringUtils.bytes32ToString(_prev));
            uint256 _prevNICR = cdpManager.getSyncedNominalICR(_prev);
            console2.log("_prevNICR:", _prevNICR);
            require(
                _insertedCdpId == exactHint ||
                    _next == exactHint ||
                    (_prevNICR == _insertedCdpNICR && _prev == exactHint),
                "!New position mismatch exact hint"
            );
        }
    }
}
