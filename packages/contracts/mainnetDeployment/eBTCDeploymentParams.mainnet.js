const externalAddress  = {
  "collateral": "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",//mainnet
  "collEthCLFeed": "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",//mainnet
  "ethBtcCLFeed": "0xAc559F25B1619171CbC396a50854A3240b6A4e99",//mainnet
  "authorityOwner": "0xB65cef03b9B89f99517643226d76e286ee999e77",//mainnet badger dev multisig
  "feeRecipientOwner": "0xB65cef03b9B89f99517643226d76e286ee999e77",//mainnet badger dev multisig
}

const OUTPUT_FILE = './mainnetDeployment/eBTCMainnetDeploymentOutput.json'

const DEPLOY_WAIT = 150000 // milli-seconds
const GAS_PRICE = 100000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://etherscan.io/address'

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
  VERIFY_ETHERSCAN,
  externalAddress
};
