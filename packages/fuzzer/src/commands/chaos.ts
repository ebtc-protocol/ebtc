import fs from "fs";

import {
  Decimal,
  Difference,
  EBTC_MINIMUM_DEBT,
  Cdp,
  CdpWithPendingRedistribution
} from "@liquity/lib-base";

import { Fixture } from "../fixture";
import { deployer, funder, provider, subgraph } from "../globals";

import {
  checkPoolBalances,
  checkSubgraph,
  checkCdpOrdering,
  connectUsers,
  createRandomWallets,
  getListOfCdpsBeforeRedistribution,
  shortenAddress
} from "../utils";

export interface ChaosParams {
  rounds: number;
  users: number;
  subgraph: boolean;
}

export const chaos = async ({
  rounds: numberOfRounds,
  users: numberOfUsers,
  subgraph: shouldCheckSubgraph
}: ChaosParams) => {
  const [frontend, ...randomUsers] = createRandomWallets(numberOfUsers + 1, provider);

  const [deployerLiquity, funderLiquity, frontendLiquity, ...randomLiquities] = await connectUsers([
    deployer,
    funder,
    frontend,
    ...randomUsers
  ]);

  const fixture = await Fixture.setup(
    deployerLiquity,
    funder,
    funderLiquity,
    frontend.address,
    frontendLiquity
  );

  let previousListOfCdps: CdpWithPendingRedistribution[] | undefined = undefined;

  console.log();
  console.log("// Keys");
  console.log(`[frontend]: ${frontend.privateKey}`);
  randomUsers.forEach(user => console.log(`[${shortenAddress(user.address)}]: ${user.privateKey}`));

  for (let i = 1; i <= numberOfRounds; ++i) {
    console.log();
    console.log(`// Round #${i}`);

    const price = await fixture.setRandomPrice();
    await fixture.liquidateRandomNumberOfCdps(price);

    for (let i = 0; i < randomUsers.length; ++i) {
      const user = randomUsers[i];
      const liquity = randomLiquities[i];

      const x = Math.random();

      if (x < 0.5) {
        const cdp = await liquity.getCdp();

        if (cdp.isEmpty) {
          await fixture.openRandomCdp(user.address, liquity);
        } else {
          if (x < 0.4) {
            await fixture.randomlyAdjustCdp(user.address, liquity, cdp);
          } else {
            await fixture.closeCdp(user.address, liquity, cdp);
          }
        }
      } else if (x < 0.7) {
        const deposit = await liquity.getStabilityDeposit();

        if (deposit.initialEBTC.isZero || x < 0.6) {
          await fixture.depositRandomAmountInStabilityPool(user.address, liquity);
        } else {
          await fixture.withdrawRandomAmountFromStabilityPool(user.address, liquity, deposit);
        }
      } else if (x < 0.9) {
        const stake = await liquity.getLQTYStake();

        if (stake.stakedLQTY.isZero || x < 0.8) {
          await fixture.stakeRandomAmount(user.address, liquity);
        } else {
          await fixture.unstakeRandomAmount(user.address, liquity, stake);
        }
      } else {
        await fixture.redeemRandomAmount(user.address, liquity);
      }

      // await fixture.sweepEBTC(liquity);
      await fixture.sweepLQTY(liquity);

      const listOfCdps = await getListOfCdpsBeforeRedistribution(deployerLiquity);
      const totalRedistributed = await deployerLiquity.getTotalRedistributed();

      checkCdpOrdering(listOfCdps, totalRedistributed, price, previousListOfCdps);
      await checkPoolBalances(deployerLiquity, listOfCdps, totalRedistributed);

      previousListOfCdps = listOfCdps;
    }

    if (shouldCheckSubgraph) {
      const blockNumber = await provider.getBlockNumber();
      await subgraph.waitForBlock(blockNumber);
      await checkSubgraph(subgraph, deployerLiquity);
    }
  }

  fs.appendFileSync("chaos.csv", fixture.summarizeGasStats());
};

export const order = async () => {
  const [deployerLiquity, funderLiquity] = await connectUsers([deployer, funder]);

  const initialPrice = await deployerLiquity.getPrice();
  // let initialNumberOfCdps = await funderLiquity.getNumberOfCdps();

  let [firstCdp] = await funderLiquity.getCdps({
    first: 1,
    sortedBy: "descendingCollateralRatio"
  });

  if (firstCdp.ownerAddress !== funder.address) {
    const funderCdp = await funderLiquity.getCdp();

    const targetCollateralRatio = Decimal.max(
      firstCdp.collateralRatio(initialPrice).add(0.00001),
      1.51
    );

    if (funderCdp.isEmpty) {
      const targetCdp = new Cdp(
        EBTC_MINIMUM_DEBT.mulDiv(targetCollateralRatio, initialPrice),
        EBTC_MINIMUM_DEBT
      );

      const fees = await funderLiquity.getFees();

      await funderLiquity.openCdp(Cdp.recreate(targetCdp, fees.borrowingRate()));
    } else {
      const targetCdp = funderCdp.setCollateral(
        funderCdp.debt.mulDiv(targetCollateralRatio, initialPrice)
      );

      await funderLiquity.adjustCdp(funderCdp.adjustTo(targetCdp));
    }
  }

  [firstCdp] = await funderLiquity.getCdps({
    first: 1,
    sortedBy: "descendingCollateralRatio"
  });

  if (firstCdp.ownerAddress !== funder.address) {
    throw new Error("didn't manage to hoist Funder's Cdp to head of SortedCdps");
  }

  await deployerLiquity.setPrice(0.001);

  let numberOfCdps: number;
  while ((numberOfCdps = await funderLiquity.getNumberOfCdps()) > 1) {
    const numberOfCdpsToLiquidate = numberOfCdps > 10 ? 10 : numberOfCdps - 1;

    console.log(`${numberOfCdps} Cdps left.`);
    await funderLiquity.liquidateUpTo(numberOfCdpsToLiquidate);
  }

  await deployerLiquity.setPrice(initialPrice);

  if ((await funderLiquity.getNumberOfCdps()) !== 1) {
    throw new Error("didn't manage to liquidate every Cdp");
  }

  const funderCdp = await funderLiquity.getCdp();
  const total = await funderLiquity.getTotal();

  const collateralDifference = Difference.between(total.collateral, funderCdp.collateral);
  const debtDifference = Difference.between(total.debt, funderCdp.debt);

  console.log();
  console.log("Discrepancies:");
  console.log(`Collateral: ${collateralDifference}`);
  console.log(`Debt: ${debtDifference}`);
};
