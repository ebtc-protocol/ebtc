# Whale Sniper POC

This exploit is possible exclusively thanks to the removal of the Linked List

This allows liquidating CDPs out of order

Because a full liquidation will allow to fully liquidate a CDP that is fairly healthy while in recovery mode, the attacker can effectively snipe any high TVL whale and liquidate them, as long as the whale has a TCR that is below 125%


## POC

### Preconditions

- Victim levers up to at least 125% (ICR < CCR)

- stETH gains some yield, that is yet to be split

- Attacker deposits enough Collateral and levers up (ICR < CCR) to bring the TCR close to CCR

- Attacker calls `claimStakingSplitFee`, triggering RM

- Attacker liquidates the Whale fully

- Attacker pockets 10% premium + caller incentive at no cost


### Minimized POCs

-> Demonstrate that TCR will go down when claiming fees - ONE
-> Demonstrate that you can bring TCR down to 125.000000000 and claiming after will cause the system to enter RM - 
-> Demonstrate you can liquidate the whale 


## Mitigation (TODO: Ask Spearbit)
uint _tcr = _checkDeltaIndexAndClaimFee(vars.price);

This check is ineffective

We should instead ALWAYS claim the fee split, to ensure that CR cannot be manipulated by a caller


## Considerations

Something similar could be set up in both Liquity and eBTC by sandwhiching an oracle update

Alternatively (easier), if the same block proposer were to be able to offer 2 blocks in a row


## Gotchas:
        cdpManager.updateCdpDebtRedistributionIndex(_cdpId);

Is already re-synching the index