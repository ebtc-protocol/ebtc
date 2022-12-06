import { Wallet } from "@ethersproject/wallet";

import { Decimal, EBTC_MINIMUM_DEBT, Cdp } from "@liquity/lib-base";
import { EthersLiquity } from "@liquity/lib-ethers";

import { deployer, funder, provider } from "../globals";

export interface WarzoneParams {
  cdps: number;
}

export const warzone = async ({ cdps: numberOfCdps }: WarzoneParams) => {
  const deployerLiquity = await EthersLiquity.connect(deployer);

  const price = await deployerLiquity.getPrice();

  for (let i = 1; i <= numberOfCdps; ++i) {
    const user = Wallet.createRandom().connect(provider);
    const userAddress = await user.getAddress();
    const debt = EBTC_MINIMUM_DEBT.add(99999 * Math.random());
    const collateral = debt.mulDiv(1.11 + 3 * Math.random(), price);

    const liquity = await EthersLiquity.connect(user);

    await funder.sendTransaction({
      to: userAddress,
      value: Decimal.from(collateral).hex
    });

    const fees = await liquity.getFees();

    await liquity.openCdp(
      Cdp.recreate(new Cdp(collateral, debt), fees.borrowingRate()),
      { borrowingFeeDecayToleranceMinutes: 0 },
      { gasPrice: 0 }
    );

    if (i % 4 === 0) {
      const ebtcBalance = await liquity.getEBTCBalance();
      await liquity.depositEBTCInStabilityPool(ebtcBalance);
    }

    if (i % 10 === 0) {
      console.log(`Created ${i} Cdps.`);
    }

    //await new Promise(resolve => setTimeout(resolve, 4000));
  }
};
