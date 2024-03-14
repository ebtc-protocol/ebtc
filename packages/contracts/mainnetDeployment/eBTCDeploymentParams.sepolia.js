const externalAddress  = {
  "collEthCLFeed": "0x007C2f192D648cBe79Ef3CC5A3DaB43D7D8c893e",
  "btcUsdCLFeed": "0x95ed2698f28c1038846b133a409Ae2Aaf0571EEa",
  "ethUsdCLFeed": "0x2Cf513b4ba3725F88bf599029Ae1A7930c84d485",
  "chainlinkAdapter": "0x7a2ed89C0E2E5acF20ccf3284A012ABbfac36D62",
  "authorityOwner": "", // Leave empty for deployer, required for atomic governance wireup.
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

const ADDITIONAL_HIGHSEC_ADMIN = "0xC8A7768D2a9EE15437c981a7130268622083c2BD" // security msig
const ADDITIONAL_LOWSEC_ADMIN = "0xC8A7768D2a9EE15437c981a7130268622083c2BD" // security msig

// Toggle if reusing Timelocks already configured or if configuration is handled manually
const SKIP_TIMELOCK_CONFIG = true

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
  ADDITIONAL_LOWSEC_ADMIN,
  SKIP_TIMELOCK_CONFIG
};
