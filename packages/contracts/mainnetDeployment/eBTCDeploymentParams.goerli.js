const externalAddrs  = {
  // https://data.chain.link/eth-usd
  CHAINLINK_ETHBTC_PROXY: "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e",
  // https://docs.tellor.io/tellor/the-basics/contracts-reference
  TELLOR_MASTER:"0xD9157453E2668B2fc45b7A803D3FEF3642430cC0", // Same as in mainnet
}

const ebtcAddrs = {
  EBTC_SAFE:"0x419b6ed40D8A7AF57D571d789d77aD2Fd9Ff761E",  //  Test safe address
}

const testAccounts = ["0xA967Ba66Fb284EC18bbe59f65bcf42dD11BA8128", "0xc2E345f74B18187E5489822f9601c028ED1915a2"]

const OUTPUT_FILE = './mainnetDeployment/eBTCGoerliDeploymentOutput.json'

const DEPLOY_WAIT = 120000 // milli-seocnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const ETHERSCAN_BASE_URL = 'https://goerli.etherscan.io/address'

module.exports = {
  externalAddrs,
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
  testAccounts,
  ebtcAddrs
};
