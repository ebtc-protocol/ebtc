// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaDoomsdayTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        _setUp();
        _setUpActors();
        _setupVictim();
    }

    address VICTIM = address(0x5000000000000005);
    address DAO = address(0xb453d);
    bytes32[] victimCdps;

    // NOTE: Customized setup for victim
    function _setupVictim() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        address[] memory callers = new address[](2);
        callers[0] = address(borrowerOperations);
        callers[1] = address(activePool);
        address[] memory addresses = new address[](2);
        addresses[0] = VICTIM;
        addresses[1] = DAO;
        Actor[] memory actorsArray = new Actor[](2);
        for (uint i = 0; i < 2; i++) {
            actors[addresses[i]] = new Actor(tokens, callers);
            (success, ) = address(actors[addresses[i]]).call{value: INITIAL_ETH_BALANCE}("");
            assert(success);
            (success, ) = actors[addresses[i]].proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                INITIAL_COLL_BALANCE
            );
            assert(success);
        }

        priceFeedMock.setPrice(1e8); /// TODO: Does this price make any sense?

        // DAO Seeds one CDP so victim can always close
        actor = actors[DAO];
        (success, ) = _openCdp(1e21, 1e8);
        assert(success);
    }

    function _openCdp(uint256 _col, uint256 _EBTCAmount) internal returns (bool, bytes32) {
        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        {
            uint price = priceFeedMock.getPrice();

            uint256 requiredCollAmount = (_EBTCAmount * cdpManager.CCR()) / (price);
            uint256 minCollAmount = max(
                cdpManager.MIN_NET_STETH_BALANCE() + borrowerOperations.LIQUIDATOR_REWARD(),
                requiredCollAmount
            );
            uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
            _col = between(requiredCollAmount, minCollAmount, maxCollAmount);
        }

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        t(success, "Approve never fails");

        {
            (success, returnData) = actor.proxy(
                address(borrowerOperations),
                abi.encodeWithSelector(
                    BorrowerOperations.openCdp.selector,
                    _EBTCAmount,
                    bytes32(0),
                    bytes32(0),
                    _col
                )
            );
        }

        bytes32 newCdpId;
        if (success) {
            newCdpId = abi.decode(returnData, (bytes32));
        }

        return (success, newCdpId);
    }

    /// NOTE: Terrible code re-use but hopefully easy to understand
    function victimOpenCdp(uint256 _col, uint256 _EBTCAmount) external {
        // Impersonate
        actor = actors[VICTIM];

        (bool success, bytes32 newCdpId) = _openCdp(_col, _EBTCAmount);

        if (success) {
            victimCdps.push(newCdpId); // Set as closable
        }
    }

    function victimCanAlwaysWithdraw() external {
        // We CRLens the withdrawal
        actor = actors[VICTIM];

        // Check if RM
        cdpManager.syncGlobalAccountingAndGracePeriod();

        if (cdpManager.lastGracePeriodStartTimestamp() != cdpManager.UNSET_TIMESTAMP()) {
            return; // Skip if in RM since you can't close in RM
        }

        // If this cannot be done at any time, then the invariant is broken
        for (uint256 i; i < victimCdps.length; i++) {
            _closeCdp(victimCdps[i]);
        }

        delete victimCdps; // Reset
    }

    function _closeCdp(bytes32 cdpId) internal {
        if (cdpManager.getCdpStatus(cdpId) != 1) {
            return; // CDP May have been redeemed or closed for some other reason, in those cases we ignore
        }
        (bool success, ) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, cdpId)
        );

        t(success, "Closing must always succeed");
    }
}
