const externalAddress  = {
  "collateral": "0xAFAcA5B8C0e5d6e0A48Dc35E46E98648c7fB3274",//goerli
//  "collateral": "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",//mainnet
  "governance": "0xB65cef03b9B89f99517643226d76e286ee999e77",//mainnet badger dev multisig
  "authorityOwner": "0xB65cef03b9B89f99517643226d76e286ee999e77",//mainnet badger dev multisig
  "feeRecipientOwner": "0xB65cef03b9B89f99517643226d76e286ee999e77",//mainnet badger dev multisig
}

const OUTPUT_FILE = './mainnetDeployment/eBTCMainnetDeploymentOutput.json'

const DEPLOY_WAIT = 120000 // milli-seocnds
const GAS_PRICE = 100000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const ETHERSCAN_BASE_URL = 'https://goerli.etherscan.io/address'
//const ETHERSCAN_BASE_URL = 'https://etherscan.io/address'

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
  externalAddress
};
