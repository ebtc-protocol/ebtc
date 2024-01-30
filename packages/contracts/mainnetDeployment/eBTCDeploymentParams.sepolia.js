const externalAddress  = {
  "collateral": "0x97BA9AA7B7DC74f7a74864A62c4fF93b2b22f015", //sepolia
  "securityMultisig": "0xC8A7768D2a9EE15437c981a7130268622083c2BD", //sepolia
  "cdpTechOpsMultisig": "0x664F43229dDa9fdEE00e723753f88f3Ba81967F6", //sepolia
  "feeRecipientMultisig": "0x5C1246E0b464060919301273781a266Ac119A0Bb", //sepolia
  "treasuryVaultMultisig": "0x005E0Ad70b40B23cef409978350CA77a179de350", //sepolia
}

const OUTPUT_FILE = './mainnetDeployment/eBTCSepoliaDeploymentOutput.json'

const DEPLOY_WAIT = 30000 // milli-secnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://sepolia.etherscan.io/address'

// Timelock configuration parameters
const HIGHSEC_MIN_DELAY = 600 // 10 mins
const LOWSEC_MIN_DELAY = 300 // 5 mins

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
