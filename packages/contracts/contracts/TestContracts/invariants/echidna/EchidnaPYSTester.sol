// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaProperties.sol";
import "../TargetFunctions.sol";

contract EchidnaPYSTester is EchidnaAsserts, EchidnaProperties, TargetFunctions {
    constructor() payable {
        yieldControlAddress = address(0x5000000000000005);
        yieldTargetAddress =  address(0x6000000000000006);

        _setUp();
        _setUpActors();
        _setupYieldActors();
    }

    // NOTE: Customized setup for a Yield Control actor and a Yield Target actor
    function _setupYieldActors() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        address[] memory callers = new address[](2);
        callers[0] = address(borrowerOperations);
        callers[1] = address(activePool);
        address[] memory addresses = new address[](2);

        addresses[0] = yieldTargetAddress;
        Actor[] memory actorsArray = new Actor[](2);
        // Just add Yield target, leaving as loop because we may want to make this more complex later
        for (uint i = 0; i < 1; i++) {
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

        // We set up our Control Address with an initial amount of collateral
        // NOT as an actor (exposes control to outside tx)
        (success, ) = yieldControlAddress.call{value: INITIAL_ETH_BALANCE}("");
        hevm.prank(yieldControlAddress);
        collateral.deposit{value: INITIAL_COLL_BALANCE - 0.2 ether}();

        // Set the PYS at 0
        TargetFunctions.setGovernanceParameters(2, 0);

        priceFeedMock.setPrice(1e8); /// TODO: Does this price make any sense?

        // The Yield Target opens a CDP. We want to follow their Yield Story
        // At the moment we aren't letting them do anything else
        actor = actors[yieldTargetAddress];
        // Small eBTC amount to prevent liquidations for now
        (success, yieldTargetCdpId) = _openCdp(INITIAL_COLL_BALANCE, 1e4);
        assert(success);
    }

    // From EchidnaDoomsDayTester
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

        // We don't want the actor to do other things in this case (yet)
        actors[yieldTargetAddress].setRestrictedMode(true);

        return (success, newCdpId);
    }

    // We override just the part of set Governance parameters that might set the stakingRewardSplit
    // This allows testing against 0 if we wish it
    function setGovernanceParameters(uint256 parameter, uint256 value) public override {
        /*if (parameter == 2) {
            parameter++;
        }*/

        // Allows us flexibility that other params can still change.
        // For now we just want the PYS to be 0
        TargetFunctions.setGovernanceParameters(parameter, value);
    }

    // WIP: Ideas with regards to tracking PYS as it changes
    // Assuming only upwards rebases for now
    function setEthPerShare(uint256 _newEthPerShare) public override {
        _before(yieldTargetCdpId);

        TargetFunctions.setEthPerShare(_newEthPerShare);
        // Sync the accounting for our tracked cdp after rebase
        hevm.prank(address(borrowerOperations));
        cdpManager.syncGlobalAccounting();

        _after(yieldTargetCdpId);
    }
}
