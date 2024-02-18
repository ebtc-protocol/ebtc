const externalAddress  = {
  "collateral": "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",//mainnet
  "collEthCLFeed": "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",//mainnet
  "btcUsdCLFeed": "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
  "ethUsdCLFeed": "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
  "authorityOwner": "",// security multisig
  "securityMultisig": "", //mainnet
  "cdpTechOpsMultisig": "", //mainnet
  "feeRecipientMultisig": "", //mainnet
  "treasuryVaultMultisig": "", //mainnet
}

const OUTPUT_FILE = './mainnetDeployment/eBTCMainnetDeploymentOutput.json'

const DEPLOY_WAIT = 150000 // milli-seconds
const GAS_PRICE = 100000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://etherscan.io/address'

// Timelock configuration parameters
const HIGHSEC_MIN_DELAY = 604800 // 7 days
const LOWSEC_MIN_DELAY = 172800 // 2 days

const ADDITIONAL_HIGHSEC_ADMIN = ""
const ADDITIONAL_LOWSEC_ADMIN = ""

module.exports = {
  OUTPUT_FILE,
  DEPLOY_WAIT,
  GAS_PRICE,
  MAX_FEE_PER_GAS,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
  VERIFY_ETHERSCAN,
  externalAddress,
  HIGHSEC_MIN_DELAY,
  LOWSEC_MIN_DELAY,
  ADDITIONAL_HIGHSEC_ADMIN,
  ADDITIONAL_LOWSEC_ADMIN
};
