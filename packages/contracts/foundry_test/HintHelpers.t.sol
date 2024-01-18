// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseInvariants} from "./BaseInvariants.sol";

contract HintHelpersTest is eBTCBaseInvariants {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    address payable[] users;

    uint256 public mintAmount = 1e18;
    uint public standardDebt = mintAmount;
    uint256 private ICR_COMPARE_TOLERANCE = 1000000; //in the scale of 1e18
    uint256 crIncrement = 1e17;

    function setUp() public override {
        super.setUp();
        users = createUsers(1005);
    }

    /// @dev Create n Cdps with different NICRs 
    /// @dev A sorted list of sufficient size allows to test hints / insertions
    function _prepareCdps(uint n) internal {
        uint256 price = priceFeedMock.fetchPrice();
        uint256 mcr = cdpManager.MCR() + 1e17;
        

        for (uint i = 0; i < n; i++) {
            uint targetIcr = mcr + (crIncrement * i);
            uint stEthCollateral = _utils.calculateCollAmount(standardDebt, price, targetIcr);
            _openTestCDP(users[i], stEthCollateral, standardDebt);
        }
    }

    /// @dev return exact position that a CDP of a given ICR should be inserted into the list
    function _getExactHint(uint256 _CR) external view returns (bytes32 exactHint) {
    uint256 arrayLength = cdpManager.getActiveCdpsCount();

    // If the list is empty, return a non-existent ID as a hint.
    if (arrayLength == 0) {
        return sortedCdps.nonExistId();
    }

    bytes32 currentCdpId = sortedCdps.getFirst();
    uint256 currentNICR = cdpManager.getSyncedNominalICR(currentCdpId);

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

        uint256 nextNICR = cdpManager.getSyncedNominalICR(nextCdpId);

        // Check if the CR fits between the current and the next CDP.
        if (_CR < currentNICR && _CR >= nextNICR) {
            return nextCdpId;
        }

        // Move to the next node in the list.
        currentCdpId = nextCdpId;
        currentNICR = nextNICR;
    }
}


    /// @dev Comapare exact hint to approxinate hint
    function test_OpenCdp_HintHelperInsert(uint n, uint targetIcr, uint numTrials, uint randomSeed) public {
        vm.assume(n > 3);
        vm.assume(n < 1000);

        // target ICR should be within range or just above
        vm.assume(targetIcr >= cdpManager.MCR());
        vm.assume(targetIcr <= mcr + (crIncrement * n+1));

        vm.assume(numTrials <= 15);

        _prepareCdps(n);

        bytes32 exactHint = _getExactHint(targetIcr);
        bytes32 approxHint = hintHelpers.getApproxHint(targetIcr, numTrials, randomSeed);

        // Figure out how far apart these two positions are from eachother

        // Insert using approxHint - this is to track gas consumption using the profiler
        // TODO: upper and lower hints
        uint256 price = priceFeedMock.fetchPrice();
        uint stEthCollateral = _utils.calculateCollAmount(standardDebt, price, targetIcr);
        _openTestCDPWithHints(users[1001], stEthCollateral, standardDebt, approxHint, approxHint);
    }

    /// @dev pick a random CDP, and adjust it to the randomized ICR inputted
    function test_AdjustCdp_HintHelperInsert(uint n, uint targetIcr) public {

    }
}
