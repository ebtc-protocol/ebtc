const externalAddrs  = {
  // https://data.chain.link/eth-usd
  CHAINLINK_ETHBTC_PROXY: "0xAc559F25B1619171CbC396a50854A3240b6A4e99",
  // https://docs.tellor.io/tellor/integration/reference-page
  TELLOR_MASTER:"0xB3B662644F8d3138df63D2F43068ea621e2981f9",
  // https://uniswap.org/docs/v2/smart-contracts/factory/
  UNISWAP_V2_FACTORY: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  UNISWAP_V2_ROUTER02: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  // https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
  WETH_ERC20: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
  STETH_ERC20: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
}

const ebtcAddrs = {
  GENERAL_SAFE:"0x8be7e24263c199ebfcfd6aebca83f8d7ed85a5dd",  // Hardhat dev address
  EBTC_SAFE:"0x20c81d658aae3a8580d990e441a9ef2c9809be74",  //  Hardhat dev address
  DEPLOYER: "0x31c57298578f7508B5982062cfEc5ec8BD346247", // hardhat first account
  ACCOUNT_2: "0x1b1E98f4912aE9014064a70537025EF338e6aD67" // hardhat second account
}

const beneficiaries = {
  TEST_INVESTOR_A: "0xdad05aa3bd5a4904eb2a9482757be5da8d554b3d",
  TEST_INVESTOR_B: "0x625b473f33b37058bf8b9d4c3d3f9ab5b896996a",
  TEST_INVESTOR_C: "0x9ea530178b9660d0fae34a41a02ec949e209142e",
  TEST_INVESTOR_D: "0xffbb4f4b113b05597298b9d8a7d79e6629e726e8",
  TEST_INVESTOR_E: "0x89ff871dbcd0a456fe92db98d190c38bc10d1cc1"
}

const testAccounts = ["0xA967Ba66Fb284EC18bbe59f65bcf42dD11BA8128", "0xc2E345f74B18187E5489822f9601c028ED1915a2"]

const OUTPUT_FILE = './mainnetDeployment/localForkDeploymentOutput.json'

const waitFunction = async () => {
  // Fast forward time 1000s (local mainnet fork only)
  ethers.provider.send("evm_increaseTime", [1000])
  ethers.provider.send("evm_mine") 
}

const GAS_PRICE = 1000
const TX_CONFIRMATIONS = 1 // for local fork test

module.exports = {
  externalAddrs,
  ebtcAddrs,
  beneficiaries,
  OUTPUT_FILE,
  waitFunction,
  GAS_PRICE,
  TX_CONFIRMATIONS,
  testAccounts
};
