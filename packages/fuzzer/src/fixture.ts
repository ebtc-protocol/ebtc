import { Signer } from "@ethersproject/abstract-signer";

import {
  Decimal,
  Decimalish,
  LQTYStake,
  EBTC_MINIMUM_DEBT,
  StabilityDeposit,
  TransactableLiquity,
  Cdp,
  CdpAdjustmentParams
} from "@liquity/lib-base";

import { EthersLiquity as Liquity } from "@liquity/lib-ethers";

import {
  createRandomCdp,
  shortenAddress,
  benford,
  getListOfCdpOwners,
  listDifference,
  getListOfCdps,
  randomCollateralChange,
  randomDebtChange,
  objToString
} from "./utils";

import { GasHistogram } from "./GasHistogram";

type _GasHistogramsFrom<T> = {
  [P in keyof T]: T[P] extends (...args: never[]) => Promise<infer R> ? GasHistogram<R> : never;
};

type GasHistograms = Pick<
  _GasHistogramsFrom<TransactableLiquity>,
  | "openCdp"
  | "adjustCdp"
  | "closeCdp"
  | "redeemEBTC"
  | "depositEBTCInStabilityPool"
  | "withdrawEBTCFromStabilityPool"
  | "stakeLQTY"
  | "unstakeLQTY"
>;

export class Fixture {
  private readonly deployerLiquity: Liquity;
  private readonly funder: Signer;
  private readonly funderLiquity: Liquity;
  private readonly funderAddress: string;
  private readonly frontendAddress: string;
  private readonly gasHistograms: GasHistograms;

  private price: Decimal;

  totalNumberOfLiquidations = 0;

  private constructor(
    deployerLiquity: Liquity,
    funder: Signer,
    funderLiquity: Liquity,
    funderAddress: string,
    frontendAddress: string,
    price: Decimal
  ) {
    this.deployerLiquity = deployerLiquity;
    this.funder = funder;
    this.funderLiquity = funderLiquity;
    this.funderAddress = funderAddress;
    this.frontendAddress = frontendAddress;
    this.price = price;

    this.gasHistograms = {
      openCdp: new GasHistogram(),
      adjustCdp: new GasHistogram(),
      closeCdp: new GasHistogram(),
      redeemEBTC: new GasHistogram(),
      depositEBTCInStabilityPool: new GasHistogram(),
      withdrawEBTCFromStabilityPool: new GasHistogram(),
      stakeLQTY: new GasHistogram(),
      unstakeLQTY: new GasHistogram()
    };
  }

  static async setup(
    deployerLiquity: Liquity,
    funder: Signer,
    funderLiquity: Liquity,
    frontendAddress: string,
    frontendLiquity: Liquity
  ) {
    const funderAddress = await funder.getAddress();
    const price = await deployerLiquity.getPrice();

    await frontendLiquity.registerFrontend(Decimal.from(10).div(11));

    return new Fixture(
      deployerLiquity,
      funder,
      funderLiquity,
      funderAddress,
      frontendAddress,
      price
    );
  }

  private async sendEBTCFromFunder(toAddress: string, amount: Decimalish) {
    amount = Decimal.from(amount);

    const ebtcBalance = await this.funderLiquity.getEBTCBalance();

    if (ebtcBalance.lt(amount)) {
      const cdp = await this.funderLiquity.getCdp();
      const total = await this.funderLiquity.getTotal();
      const fees = await this.funderLiquity.getFees();

      const targetCollateralRatio =
        cdp.isEmpty || !total.collateralRatioIsBelowCritical(this.price)
          ? 1.51
          : Decimal.max(cdp.collateralRatio(this.price).add(0.00001), 1.11);

      let newCdp = cdp.isEmpty ? Cdp.create({ depositCollateral: 1, borrowEBTC: 0 }) : cdp;
      newCdp = newCdp.adjust({ borrowEBTC: amount.sub(ebtcBalance).mul(2) });

      if (newCdp.debt.lt(EBTC_MINIMUM_DEBT)) {
        newCdp = newCdp.setDebt(EBTC_MINIMUM_DEBT);
      }

      newCdp = newCdp.setCollateral(newCdp.debt.mulDiv(targetCollateralRatio, this.price));

      if (cdp.isEmpty) {
        const params = Cdp.recreate(newCdp, fees.borrowingRate());
        console.log(`[funder] openCdp(${objToString(params)})`);
        await this.funderLiquity.openCdp(params);
      } else {
        let newTotal = total.add(newCdp).subtract(cdp);

        if (
          !total.collateralRatioIsBelowCritical(this.price) &&
          newTotal.collateralRatioIsBelowCritical(this.price)
        ) {
          newTotal = newTotal.setCollateral(newTotal.debt.mulDiv(1.51, this.price));
          newCdp = cdp.add(newTotal).subtract(total);
        }

        const params = cdp.adjustTo(newCdp, fees.borrowingRate());
        console.log(`[funder] adjustCdp(${objToString(params)})`);
        await this.funderLiquity.adjustCdp(params);
      }
    }

    await this.funderLiquity.sendEBTC(toAddress, amount);
  }

  async setRandomPrice() {
    this.price = this.price.add(200 * Math.random() + 100).div(2);
    console.log(`[deployer] setPrice(${this.price})`);
    await this.deployerLiquity.setPrice(this.price);

    return this.price;
  }

  async liquidateRandomNumberOfCdps(price: Decimal) {
    const ebtcInStabilityPoolBefore = await this.deployerLiquity.getEBTCInStabilityPool();
    console.log(`// Stability Pool balance: ${ebtcInStabilityPoolBefore}`);

    const cdpsBefore = await getListOfCdps(this.deployerLiquity);

    if (cdpsBefore.length === 0) {
      console.log("// No Cdps to liquidate");
      return;
    }

    const cdpOwnersBefore = cdpsBefore.map(cdp => cdp.ownerAddress);
    const lastCdp = cdpsBefore[cdpsBefore.length - 1];

    if (!lastCdp.collateralRatioIsBelowMinimum(price)) {
      console.log("// No Cdps to liquidate");
      return;
    }

    const maximumNumberOfCdpsToLiquidate = Math.floor(50 * Math.random()) + 1;
    console.log(`[deployer] liquidateUpTo(${maximumNumberOfCdpsToLiquidate})`);
    await this.deployerLiquity.liquidateUpTo(maximumNumberOfCdpsToLiquidate);

    const cdpOwnersAfter = await getListOfCdpOwners(this.deployerLiquity);
    const liquidatedCdps = listDifference(cdpOwnersBefore, cdpOwnersAfter);

    if (liquidatedCdps.length > 0) {
      for (const liquidatedCdp of liquidatedCdps) {
        console.log(`// Liquidated ${shortenAddress(liquidatedCdp)}`);
      }
    }

    this.totalNumberOfLiquidations += liquidatedCdps.length;

    const ebtcInStabilityPoolAfter = await this.deployerLiquity.getEBTCInStabilityPool();
    console.log(`// Stability Pool balance: ${ebtcInStabilityPoolAfter}`);
  }

  async openRandomCdp(userAddress: string, liquity: Liquity) {
    const total = await liquity.getTotal();
    const fees = await liquity.getFees();

    let newCdp: Cdp;

    const cannotOpen = (newCdp: Cdp) =>
      newCdp.debt.lt(EBTC_MINIMUM_DEBT) ||
      (total.collateralRatioIsBelowCritical(this.price)
        ? !newCdp.isOpenableInRecoveryMode(this.price)
        : newCdp.collateralRatioIsBelowMinimum(this.price) ||
          total.add(newCdp).collateralRatioIsBelowCritical(this.price));

    // do {
    newCdp = createRandomCdp(this.price);
    // } while (cannotOpen(newCdp));

    await this.funder.sendTransaction({
      to: userAddress,
      value: newCdp.collateral.hex
    });

    const params = Cdp.recreate(newCdp, fees.borrowingRate());

    if (cannotOpen(newCdp)) {
      console.log(
        `// [${shortenAddress(userAddress)}] openCdp(${objToString(params)}) expected to fail`
      );

      await this.gasHistograms.openCdp.expectFailure(() =>
        liquity.openCdp(params, undefined, { gasPrice: 0 })
      );
    } else {
      console.log(`[${shortenAddress(userAddress)}] openCdp(${objToString(params)})`);

      await this.gasHistograms.openCdp.expectSuccess(() =>
        liquity.send.openCdp(params, undefined, { gasPrice: 0 })
      );
    }
  }

  async randomlyAdjustCdp(userAddress: string, liquity: Liquity, cdp: Cdp) {
    const total = await liquity.getTotal();
    const fees = await liquity.getFees();
    const x = Math.random();

    const params: CdpAdjustmentParams<Decimal> =
      x < 0.333
        ? randomCollateralChange(cdp)
        : x < 0.666
        ? randomDebtChange(cdp)
        : { ...randomCollateralChange(cdp), ...randomDebtChange(cdp) };

    const cannotAdjust = (cdp: Cdp, params: CdpAdjustmentParams<Decimal>) => {
      if (
        params.withdrawCollateral?.gte(cdp.collateral) ||
        params.repayEBTC?.gt(cdp.debt.sub(EBTC_MINIMUM_DEBT))
      ) {
        return true;
      }

      const adjusted = cdp.adjust(params, fees.borrowingRate());

      return (
        (params.withdrawCollateral?.nonZero || params.borrowEBTC?.nonZero) &&
        (adjusted.collateralRatioIsBelowMinimum(this.price) ||
          (total.collateralRatioIsBelowCritical(this.price)
            ? adjusted._nominalCollateralRatio.lt(cdp._nominalCollateralRatio)
            : total.add(adjusted).subtract(cdp).collateralRatioIsBelowCritical(this.price)))
      );
    };

    if (params.depositCollateral) {
      await this.funder.sendTransaction({
        to: userAddress,
        value: params.depositCollateral.hex
      });
    }

    if (params.repayEBTC) {
      await this.sendEBTCFromFunder(userAddress, params.repayEBTC);
    }

    if (cannotAdjust(cdp, params)) {
      console.log(
        `// [${shortenAddress(userAddress)}] adjustCdp(${objToString(params)}) expected to fail`
      );

      await this.gasHistograms.adjustCdp.expectFailure(() =>
        liquity.adjustCdp(params, undefined, { gasPrice: 0 })
      );
    } else {
      console.log(`[${shortenAddress(userAddress)}] adjustCdp(${objToString(params)})`);

      await this.gasHistograms.adjustCdp.expectSuccess(() =>
        liquity.send.adjustCdp(params, undefined, { gasPrice: 0 })
      );
    }
  }

  async closeCdp(userAddress: string, liquity: Liquity, cdp: Cdp) {
    const total = await liquity.getTotal();

    if (total.collateralRatioIsBelowCritical(this.price)) {
      // Cannot close Cdp during recovery mode
      console.log("// Skipping closeCdp() in recovery mode");
      return;
    }

    await this.sendEBTCFromFunder(userAddress, cdp.netDebt);

    console.log(`[${shortenAddress(userAddress)}] closeCdp()`);

    await this.gasHistograms.closeCdp.expectSuccess(() =>
      liquity.send.closeCdp({ gasPrice: 0 })
    );
  }

  async redeemRandomAmount(userAddress: string, liquity: Liquity) {
    const total = await liquity.getTotal();

    if (total.collateralRatioIsBelowMinimum(this.price)) {
      console.log("// Skipping redeemEBTC() when TCR < MCR");
      return;
    }

    const amount = benford(10000);
    await this.sendEBTCFromFunder(userAddress, amount);

    console.log(`[${shortenAddress(userAddress)}] redeemEBTC(${amount})`);

    try {
      await this.gasHistograms.redeemEBTC.expectSuccess(() =>
        liquity.send.redeemEBTC(amount, undefined, { gasPrice: 0 })
      );
    } catch (error) {
      if (error instanceof Error && error.message.includes("amount too low to redeem")) {
        console.log("// amount too low to redeem");
      } else {
        throw error;
      }
    }
  }

  async depositRandomAmountInStabilityPool(userAddress: string, liquity: Liquity) {
    const amount = benford(20000);

    await this.sendEBTCFromFunder(userAddress, amount);

    console.log(`[${shortenAddress(userAddress)}] depositEBTCInStabilityPool(${amount})`);

    await this.gasHistograms.depositEBTCInStabilityPool.expectSuccess(() =>
      liquity.send.depositEBTCInStabilityPool(amount, this.frontendAddress, {
        gasPrice: 0
      })
    );
  }

  async withdrawRandomAmountFromStabilityPool(
    userAddress: string,
    liquity: Liquity,
    deposit: StabilityDeposit
  ) {
    const [lastCdp] = await liquity.getCdps({
      first: 1,
      sortedBy: "ascendingCollateralRatio"
    });

    const amount = deposit.currentEBTC.mul(1.1 * Math.random()).add(10 * Math.random());

    const cannotWithdraw = (amount: Decimal) =>
      amount.nonZero && lastCdp.collateralRatioIsBelowMinimum(this.price);

    if (cannotWithdraw(amount)) {
      console.log(
        `// [${shortenAddress(userAddress)}] ` +
          `withdrawEBTCFromStabilityPool(${amount}) expected to fail`
      );

      await this.gasHistograms.withdrawEBTCFromStabilityPool.expectFailure(() =>
        liquity.withdrawEBTCFromStabilityPool(amount, { gasPrice: 0 })
      );
    } else {
      console.log(`[${shortenAddress(userAddress)}] withdrawEBTCFromStabilityPool(${amount})`);

      await this.gasHistograms.withdrawEBTCFromStabilityPool.expectSuccess(() =>
        liquity.send.withdrawEBTCFromStabilityPool(amount, { gasPrice: 0 })
      );
    }
  }

  async stakeRandomAmount(userAddress: string, liquity: Liquity) {
    const lqtyBalance = await this.funderLiquity.getLQTYBalance();
    const amount = lqtyBalance.mul(Math.random() / 2);

    await this.funderLiquity.sendLQTY(userAddress, amount);

    if (amount.eq(0)) {
      console.log(`// [${shortenAddress(userAddress)}] stakeLQTY(${amount}) expected to fail`);

      await this.gasHistograms.stakeLQTY.expectFailure(() =>
        liquity.stakeLQTY(amount, { gasPrice: 0 })
      );
    } else {
      console.log(`[${shortenAddress(userAddress)}] stakeLQTY(${amount})`);

      await this.gasHistograms.stakeLQTY.expectSuccess(() =>
        liquity.send.stakeLQTY(amount, { gasPrice: 0 })
      );
    }
  }

  async unstakeRandomAmount(userAddress: string, liquity: Liquity, stake: LQTYStake) {
    const amount = stake.stakedLQTY.mul(1.1 * Math.random()).add(10 * Math.random());

    console.log(`[${shortenAddress(userAddress)}] unstakeLQTY(${amount})`);

    await this.gasHistograms.unstakeLQTY.expectSuccess(() =>
      liquity.send.unstakeLQTY(amount, { gasPrice: 0 })
    );
  }

  async sweepEBTC(liquity: Liquity) {
    const ebtcBalance = await liquity.getEBTCBalance();

    if (ebtcBalance.nonZero) {
      await liquity.sendEBTC(this.funderAddress, ebtcBalance, { gasPrice: 0 });
    }
  }

  async sweepLQTY(liquity: Liquity) {
    const lqtyBalance = await liquity.getLQTYBalance();

    if (lqtyBalance.nonZero) {
      await liquity.sendLQTY(this.funderAddress, lqtyBalance, { gasPrice: 0 });
    }
  }

  summarizeGasStats(): string {
    return Object.entries(this.gasHistograms)
      .map(([name, histo]) => {
        const results = histo.getResults();

        return (
          `${name},outOfGas,${histo.outOfGasFailures}\n` +
          `${name},failure,${histo.expectedFailures}\n` +
          results
            .map(([intervalMin, frequency]) => `${name},success,${frequency},${intervalMin}\n`)
            .join("")
        );
      })
      .join("");
  }
}
