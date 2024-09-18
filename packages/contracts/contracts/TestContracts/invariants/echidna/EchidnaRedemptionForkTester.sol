// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./EchidnaAsserts.sol";
import "./EchidnaForkAssertions.sol";
import "../TargetFunctions.sol";

// Run locally with: `echidna contracts/TestContracts/invariants/echidna/EchidnaRedemptionForkTester.sol --contract EchidnaRedemptionForkTester --test-mode property --rpc-url YOUR_RPC_URL --config fuzzTests/echidna_config.yaml`
contract EchidnaRedemptionForkTester is EchidnaAsserts, EchidnaForkAssertions, TargetFunctions {
    constructor() payable {
        // Timestamp and block height setup in `_setUpFork()`

        // https://etherscan.io/tx/0xca4f2e9a7e8cc82969e435091576dbd8c8bfcc008e89906857056481e0542f23
        _setUpFork();
        _setUpActorsFork();

        // If the accounting hasn't been synced since the last rebase
        bytes32 currentCdp = sortedCdps.getFirst();

        while (currentCdp != bytes32(0)) {
            hevm.prank(address(borrowerOperations));
            cdpManager.syncAccounting(currentCdp);
            currentCdp = sortedCdps.getNext(currentCdp);
        }

        // Previous cumulative CDPs per each rebase
        // Will need to be adjusted
        // @audit Need to add the explanation for this - it will definitely not hold forever and is not accurate
        // Affects `invariant_GENERAL_18`
        // This is not going to be reliably testable on fork tests in any case
        vars.cumulativeCdpsAtTimeOfRebase = 200;

        // These are the fuzzed parameters
        // @audit We could do a version where the proposed gov transaction is provided and we do it as a low-level call
        hevm.prank(defaultGovernance);
        // First we set the Redemption Fee Floor
        try cdpManager.setRedemptionFeeFloor(25e15) {} catch {
            t(false, "SetRedemptionFeeFloor failed");
        }

        hevm.prank(defaultGovernance);
        // We unpause the redemptions 
        try cdpManager.setRedemptionsPaused(false) {} catch {
            t(false, "Redemptions did not unpause successfully");
        }

        // Sets up at least one actor with a CDP on the fork
        // the fuzzer still has the ability open cdps, but this allows the tests to start with an open cdp
        _setUpCdpFork();
    }

    // This overrides the PriceOracle's last good price
    function setPrice(uint256 newPrice) public override {
        _before(bytes32(0));

        hevm.store(
            address(priceFeedMock),
            0x0000000000000000000000000000000000000000000000000000000000000002,
            bytes32(0)
        );

        // Load last good price
        uint256 oldPrice = uint256(
            hevm.load(
                address(priceFeedMock),
                0x0000000000000000000000000000000000000000000000000000000000000001
            )
        );
        // New Price
        newPrice = between(
            newPrice,
            (oldPrice * 1e18) / MAX_PRICE_CHANGE_PERCENT,
            (oldPrice * MAX_PRICE_CHANGE_PERCENT) / 1e18
        );

        // Set new price by etching last good price
        hevm.store(
            address(priceFeedMock),
            0x0000000000000000000000000000000000000000000000000000000000000001,
            bytes32(newPrice)
        );

        cdpManager.syncGlobalAccountingAndGracePeriod();

        _after(bytes32(0));
    }

    // Don't need to etch storage, mocking it as a call from default governance should be enough
    // as the timelock logic happens in the TimelockController, and governance params only care about who is the caller
    function setGovernanceParameters(uint256 parameter, uint256 value) public override {
        parameter = between(parameter, 0, 6);

        if (parameter == 0) {
            value = between(value, cdpManager.MINIMUM_GRACE_PERIOD(), type(uint128).max);
            hevm.prank(defaultGovernance);
            cdpManager.setGracePeriod(uint128(value));
        } else if (parameter == 1) {
            value = between(value, 0, activePool.getFeeRecipientClaimableCollShares());
            _before(bytes32(0));
            hevm.prank(defaultGovernance);
            activePool.claimFeeRecipientCollShares(value);
            _after(bytes32(0));
            // If there was something to claim
            if (value > 0) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/22
                // Claiming will increase the balance
                // Strictly GT
                gt(vars.feeRecipientCollSharesBalAfter, vars.feeRecipientCollSharesBalBefore, F_01);
                gte(vars.feeRecipientTotalCollAfter, vars.feeRecipientTotalCollBefore, F_01);
            }
        } else if (parameter == 2) {
            value = between(value, 0, cdpManager.MAX_REWARD_SPLIT());
            hevm.prank(defaultGovernance);
            cdpManager.setStakingRewardSplit(value);
        } else if (parameter == 3) {
            // Do not change redemption floor again
        } else if (parameter == 4) {
            value = between(
                value,
                cdpManager.MIN_MINUTE_DECAY_FACTOR(),
                cdpManager.MAX_MINUTE_DECAY_FACTOR()
            );
            hevm.prank(defaultGovernance);
            cdpManager.setMinuteDecayFactor(value);
        } else if (parameter == 5) {
            value = between(value, 0, cdpManager.DECIMAL_PRECISION());
            hevm.prank(defaultGovernance);
            cdpManager.setBeta(value);
        } else if (parameter == 6) {
            // Do not set redemptions false again
        }
    }

    function setEthPerShare(uint256 newValue) public override {
        _before(bytes32(0));
        // Our approach is to to increase the amount of ether without increasing the number of shares
        // We load the bulk share of staked ether, then modify it, then change the value in the slot directly.
        uint256 oldValue = uint256(
            hevm.load(
                address(collateral),
                0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
            )
        );

        newValue = between(
            newValue,
            (oldValue * 1e18) / MAX_REBASE_PERCENT,
            (oldValue * MAX_REBASE_PERCENT) / 1e18
        );

        hevm.store(
            address(collateral),
            0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483,
            bytes32(newValue)
        );
        cdpManager.syncGlobalAccountingAndGracePeriod();

        _after(bytes32(0));
    }
}
