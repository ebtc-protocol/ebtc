# Flashloan POC

These 2 checks in the flashloan are incorrect:

```solidity
        require(
            collateral.balanceOf(address(this)) >= collateral.getPooledEthByShares(systemCollShares),
            "ActivePool: Must repay Balance"
        );
        require(collateral.sharesOf(address(this)) >= systemCollShares, "ActivePool: Must repay Share");
```

That's because the contract has a balance that is higher than these

You can also flashloan a value that is greater than `systemCollShares`

It may be best to prevent that, and cap the amount to `systemCollShares`

That said, the check that is saving the system is the check for lack of rate changes

Since the rate for stETH cannot change, the repayment value must be as high as the borrowed value + the fee

## Mitigation (TODO: Talk to spearbit during mitigation phase)

We could:
- Cap the amount borrowable to systemCollShares
- Remove the other checks