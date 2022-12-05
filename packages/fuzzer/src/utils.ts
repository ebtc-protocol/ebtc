import { Signer } from "@ethersproject/abstract-signer";
import { Provider } from "@ethersproject/abstract-provider";
import { Wallet } from "@ethersproject/wallet";

import {
  Decimal,
  Decimalish,
  Difference,
  Percent,
  Cdp,
  CdpWithPendingRedistribution,
  ReadableLiquity,
  EBTC_LIQUIDATION_RESERVE
} from "@liquity/lib-base";
import { EthersLiquity, ReadableEthersLiquity } from "@liquity/lib-ethers";
import { SubgraphLiquity } from "@liquity/lib-subgraph";

export const objToString = (o: Record<string, unknown>) =>
  "{ " +
  Object.entries(o)
    .map(([k, v]) => `${k}: ${v}`)
    .join(", ") +
  " }";

export const createRandomWallets = (numberOfWallets: number, provider: Provider) => {
  const accounts = new Array<Wallet>(numberOfWallets);

  for (let i = 0; i < numberOfWallets; ++i) {
    accounts[i] = Wallet.createRandom().connect(provider);
  }

  return accounts;
};

export const createRandomCdp = (price: Decimal) => {
  let randomValue = truncateLastDigits(benford(1000));

  if (Math.random() < 0.5) {
    const collateral = Decimal.from(randomValue);
    const maxDebt = parseInt(price.mul(collateral).toString(0));
    const debt = EBTC_LIQUIDATION_RESERVE.add(truncateLastDigits(maxDebt - benford(maxDebt)));

    return new Cdp(collateral, debt);
  } else {
    const debt = EBTC_LIQUIDATION_RESERVE.add(100 * randomValue);

    const collateral = Decimal.from(
      debt
        .div(price)
        .mul(100 + benford(200))
        .div(100)
        .toString(4)
    );

    return new Cdp(collateral, debt);
  }
};

export const randomCollateralChange = ({ collateral }: Cdp) =>
  Math.random() < 0.5
    ? { withdrawCollateral: collateral.mul(1.1 * Math.random()) }
    : { depositCollateral: collateral.mul(0.5 * Math.random()) };

export const randomDebtChange = ({ debt }: Cdp) =>
  Math.random() < 0.5
    ? { repayEBTC: debt.mul(1.1 * Math.random()) }
    : { borrowEBTC: debt.mul(0.5 * Math.random()) };

export const getListOfCdps = async (liquity: ReadableLiquity) =>
  liquity.getCdps({
    first: await liquity.getNumberOfCdps(),
    sortedBy: "descendingCollateralRatio",
    beforeRedistribution: false
  });

export const getListOfCdpsBeforeRedistribution = async (liquity: ReadableLiquity) =>
  liquity.getCdps({
    first: await liquity.getNumberOfCdps(),
    sortedBy: "descendingCollateralRatio",
    beforeRedistribution: true
  });

export const getListOfCdpOwners = async (liquity: ReadableLiquity) =>
  getListOfCdpsBeforeRedistribution(liquity).then(cdps =>
    cdps.map(cdp => cdp.ownerAddress)
  );

const tinyDifference = Decimal.from("0.000000001");

const sortedByICR = (
  listOfCdps: CdpWithPendingRedistribution[],
  totalRedistributed: Cdp,
  price: Decimalish
) => {
  if (listOfCdps.length < 2) {
    return true;
  }

  let currentCdp = listOfCdps[0].applyRedistribution(totalRedistributed);

  for (let i = 1; i < listOfCdps.length; ++i) {
    const nextCdp = listOfCdps[i].applyRedistribution(totalRedistributed);

    if (
      nextCdp.collateralRatio(price).gt(currentCdp.collateralRatio(price).add(tinyDifference))
    ) {
      return false;
    }

    currentCdp = nextCdp;
  }

  return true;
};

export const listDifference = (listA: string[], listB: string[]) => {
  const setB = new Set(listB);
  return listA.filter(x => !setB.has(x));
};

export const listOfCdpsShouldBeEqual = (
  listA: CdpWithPendingRedistribution[],
  listB: CdpWithPendingRedistribution[]
) => {
  if (listA.length !== listB.length) {
    throw new Error("length of cdp lists is different");
  }

  const mapB = new Map(listB.map(cdp => [cdp.ownerAddress, cdp]));

  listA.forEach(cdpA => {
    const cdpB = mapB.get(cdpA.ownerAddress);

    if (!cdpB) {
      throw new Error(`${cdpA.ownerAddress} has no cdp in listB`);
    }

    if (!cdpA.equals(cdpB)) {
      throw new Error(`${cdpA.ownerAddress} has different cdps in listA & listB`);
    }
  });
};

export const checkCdpOrdering = (
  listOfCdps: CdpWithPendingRedistribution[],
  totalRedistributed: Cdp,
  price: Decimal,
  previousListOfCdps?: CdpWithPendingRedistribution[]
) => {
  if (!sortedByICR(listOfCdps, totalRedistributed, price)) {
    if (previousListOfCdps) {
      console.log();
      console.log("// List of Cdps before:");
      dumpCdps(previousListOfCdps, totalRedistributed, price);

      console.log();
      console.log("// List of Cdps after:");
    }

    dumpCdps(listOfCdps, totalRedistributed, price);
    throw new Error("ordering is broken");
  }
};

export const checkPoolBalances = async (
  liquity: ReadableEthersLiquity,
  listOfCdps: CdpWithPendingRedistribution[],
  totalRedistributed: Cdp
) => {
  const activePool = await liquity._getActivePool();
  const defaultPool = await liquity._getDefaultPool();

  const [activeTotal, defaultTotal] = listOfCdps.reduce(
    ([activeTotal, defaultTotal], cdpActive) => {
      const cdpTotal = cdpActive.applyRedistribution(totalRedistributed);
      const cdpDefault = cdpTotal.subtract(cdpActive);

      return [activeTotal.add(cdpActive), defaultTotal.add(cdpDefault)];
    },
    [new Cdp(), new Cdp()]
  );

  const diffs = [
    Difference.between(activePool.collateral, activeTotal.collateral),
    Difference.between(activePool.debt, activeTotal.debt),
    Difference.between(defaultPool.collateral, defaultTotal.collateral),
    Difference.between(defaultPool.debt, defaultTotal.debt)
  ];

  if (!diffs.every(diff => diff.absoluteValue?.lt(tinyDifference))) {
    console.log();
    console.log(`  ActivePool:    ${activePool}`);
    console.log(`  Total active:  ${activeTotal}`);
    console.log();
    console.log(`  DefaultPool:   ${defaultPool}`);
    console.log(`  Total default: ${defaultTotal}`);
    console.log();

    throw new Error("discrepancy between Cdps & Pools");
  }
};

const numbersEqual = (a: number, b: number) => a === b;
const decimalsEqual = (a: Decimal, b: Decimal) => a.eq(b);
const cdpsEqual = (a: Cdp, b: Cdp) => a.equals(b);

const cdpsRoughlyEqual = (cdpA: Cdp, cdpB: Cdp) =>
  [
    [cdpA.collateral, cdpB.collateral],
    [cdpA.debt, cdpB.debt]
  ].every(([a, b]) => Difference.between(a, b).absoluteValue?.lt(tinyDifference));

class EqualityCheck<T> {
  private name: string;
  private get: (l: ReadableLiquity) => Promise<T>;
  private equals: (a: T, b: T) => boolean;

  constructor(
    name: string,
    get: (l: ReadableLiquity) => Promise<T>,
    equals: (a: T, b: T) => boolean
  ) {
    this.name = name;
    this.get = get;
    this.equals = equals;
  }

  async allEqual(liquities: ReadableLiquity[]) {
    const [a, ...rest] = await Promise.all(liquities.map(l => this.get(l)));

    if (!rest.every(b => this.equals(a, b))) {
      throw new Error(`Mismatch in ${this.name}`);
    }
  }
}

const checks = [
  new EqualityCheck("numberOfCdps", l => l.getNumberOfCdps(), numbersEqual),
  new EqualityCheck("price", l => l.getPrice(), decimalsEqual),
  new EqualityCheck("total", l => l.getTotal(), cdpsRoughlyEqual),
  new EqualityCheck("totalRedistributed", l => l.getTotalRedistributed(), cdpsEqual),
  new EqualityCheck("tokensInStabilityPool", l => l.getEBTCInStabilityPool(), decimalsEqual)
];

export const checkSubgraph = async (subgraph: SubgraphLiquity, l1Liquity: ReadableLiquity) => {
  await Promise.all(checks.map(check => check.allEqual([subgraph, l1Liquity])));

  const l1ListOfCdps = await getListOfCdpsBeforeRedistribution(l1Liquity);
  const subgraphListOfCdps = await getListOfCdpsBeforeRedistribution(subgraph);
  listOfCdpsShouldBeEqual(l1ListOfCdps, subgraphListOfCdps);

  const totalRedistributed = await subgraph.getTotalRedistributed();
  const price = await subgraph.getPrice();

  if (!sortedByICR(subgraphListOfCdps, totalRedistributed, price)) {
    console.log();
    console.log("// List of Cdps returned by subgraph:");
    dumpCdps(subgraphListOfCdps, totalRedistributed, price);
    throw new Error("subgraph sorting broken");
  }
};

export const shortenAddress = (address: string) => address.substr(0, 6) + "..." + address.substr(-4);

const cdpToString = (
  cdpWithPendingRewards: CdpWithPendingRedistribution,
  totalRedistributed: Cdp,
  price: Decimalish
) => {
  const cdp = cdpWithPendingRewards.applyRedistribution(totalRedistributed);
  const rewards = cdp.subtract(cdpWithPendingRewards);

  return (
    `[${shortenAddress(cdpWithPendingRewards.ownerAddress)}]: ` +
    `ICR = ${new Percent(cdp.collateralRatio(price)).toString(2)}, ` +
    `ICR w/o reward = ${new Percent(cdpWithPendingRewards.collateralRatio(price)).toString(2)}, ` +
    `coll = ${cdp.collateral.toString(2)}, ` +
    `debt = ${cdp.debt.toString(2)}, ` +
    `coll reward = ${rewards.collateral.toString(2)}, ` +
    `debt reward = ${rewards.debt.toString(2)}`
  );
};

export const dumpCdps = (
  listOfCdps: CdpWithPendingRedistribution[],
  totalRedistributed: Cdp,
  price: Decimalish
) => {
  if (listOfCdps.length === 0) {
    return;
  }

  let currentCdp = listOfCdps[0];
  console.log(`   ${cdpToString(currentCdp, totalRedistributed, price)}`);

  for (let i = 1; i < listOfCdps.length; ++i) {
    const nextCdp = listOfCdps[i];

    if (
      nextCdp
        .applyRedistribution(totalRedistributed)
        .collateralRatio(price)
        .sub(tinyDifference)
        .gt(currentCdp.applyRedistribution(totalRedistributed).collateralRatio(price))
    ) {
      console.log(`!! ${cdpToString(nextCdp, totalRedistributed, price)}`.red);
    } else {
      console.log(`   ${cdpToString(nextCdp, totalRedistributed, price)}`);
    }

    currentCdp = nextCdp;
  }
};

export const benford = (max: number) => Math.floor(Math.exp(Math.log(max) * Math.random()));

const truncateLastDigits = (n: number) => {
  if (n > 100000) {
    return 1000 * Math.floor(n / 1000);
  } else if (n > 10000) {
    return 100 * Math.floor(n / 100);
  } else if (n > 1000) {
    return 10 * Math.floor(n / 10);
  } else {
    return n;
  }
};

export const connectUsers = (users: Signer[]) =>
  Promise.all(users.map(user => EthersLiquity.connect(user)));
