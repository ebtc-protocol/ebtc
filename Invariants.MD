## Deposit Invariants
At all times, the total stETH balance of the system exceeds the deposits

More specifically the total balance is greater than or equal to the deposits + the accrued interest (- the fee)

TODO: ADD INVARIANT FORMULA / CHANGE THIS ONE BELOW PLS

STETH = Sum(ScaledRebaseNetFee(CDP_UserColl)) + Fees + Default Coll

At all times, the total debt is equal to the sum of all debts from all CDP

DEBT = Sum(CDP_DEBT)

## Risk Invariants

If the system is above Recovery Mode, no user action alone can bring the system to recovery mode without an oracle price change

As a Individual Leveraged to the maximum (110 CR), I can only be liquidated if:
- The oracle price changes in such a way that my CR goes below 110
- Other depositors bring the system CR to 125 (edge of Recovery Mode), then the Oracle Price updates to a lower value, causing every CDP below RM to be liquidatable


As an attacker, without a price change, I can never profit from performing any operation
(e.g. Starting with X tokens, leads me to have X tokens at most)

As a user, receiving attacks, without a price change, my position can never reduce in absolute value (Redemption moves value but doesn't reduces it)

As a user, receiving attacks, without a price change, in case of a slash or a upwards rebase, the value of my position changes exclusively based on the rebase that happened to the collateral

As a user, receiving attacks, without a price change, I can only be liquidated if the underlying value of shares of stETH decreases to cause my position to go below the liquidation threshold

## Use Case Invariants

I cannot ever open a CDP that can be liquidated

I must repay all debt to close a CDP

Each time I change my ICR, the TCR changes by an impact that is equal to the relative weight of collateral and debt from my position

At all times TCR = SUM(ICR) for all CDPs


## Redemption Invariant

Redemptions, at best, offer PRICE - BASE_FEE for any amount

There is no way for a redemption to gain more than PRICE - BASE_FEE of collateral back
