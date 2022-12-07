import { EthersLiquity } from "@liquity/lib-ethers";

import { deployer, subgraph } from "../globals";

import {
  checkSubgraph,
  checkCdpOrdering,
  dumpCdps,
  getListOfCdpsBeforeRedistribution
} from "../utils";

export const checkSorting = async () => {
  const deployerLiquity = await EthersLiquity.connect(deployer);
  const listOfCdps = await getListOfCdpsBeforeRedistribution(deployerLiquity);
  const totalRedistributed = await deployerLiquity.getTotalRedistributed();
  const price = await deployerLiquity.getPrice();

  checkCdpOrdering(listOfCdps, totalRedistributed, price);

  console.log("All Cdps are sorted.");
};

export const checkSubgraphCmd = async () => {
  const deployerLiquity = await EthersLiquity.connect(deployer);

  await checkSubgraph(subgraph, deployerLiquity);

  console.log("Subgraph looks fine.");
};

export const dumpCdpsCmd = async () => {
  const deployerLiquity = await EthersLiquity.connect(deployer);
  const listOfCdps = await getListOfCdpsBeforeRedistribution(deployerLiquity);
  const totalRedistributed = await deployerLiquity.getTotalRedistributed();
  const price = await deployerLiquity.getPrice();

  dumpCdps(listOfCdps, totalRedistributed, price);
};
