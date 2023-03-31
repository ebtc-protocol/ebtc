const externalAddrs  = {
  // https://data.chain.link/eth-usd
  CHAINLINK_ETHBTC_PROXY: "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e",
  // https://docs.tellor.io/tellor/the-basics/contracts-reference
  TELLOR_MASTER:"0xD9157453E2668B2fc45b7A803D3FEF3642430cC0", // Same as in mainnet
  // https://uniswap.org/docs/v2/smart-contracts/factory/
  UNISWAP_V2_FACTORY: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  UNISWAP_V2_ROUTER02: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  WETH_ERC20: "0xcd48a86666D2a79e027D82cA6Adf853357c70d02",
}

const OUTPUT_FILE = './mainnetDeployment/goerliDeploymentOutput.json'

const delay = ms => new Promise(res => setTimeout(res, ms));
const waitFunction = async () => {
  return delay(90000) // wait 90s
}

const GAS_PRICE = 1000000000 // 1 Gwei
const TX_CONFIRMATIONS = 1

const ETHERSCAN_BASE_URL = 'https://goerli.etherscan.io/address'

module.exports = {
  externalAddrs,
  OUTPUT_FILE,
  waitFunction,
  GAS_PRICE,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
};
