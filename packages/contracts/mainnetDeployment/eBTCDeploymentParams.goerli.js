const externalAddress  = {
  "collEthCLFeed": "0xb4c4a493AB6356497713A78FFA6c60FB53517c63",//goerli
  "ethBtcCLFeed": "0x779877A7B0D9E8603169DdbD7836e478b4624789",//goerli
  "securityMultisig": "0x0A8fE898020f5E02C8D7ac29CCb907198f77ed92", //goerli
  "cdpTechOpsMultisig": "0xb1939449B5612F632F2651cBe56b8FDc7f04dE26", //goerli
  "feeRecipientMultisig": "0x821Ef96C19db290d2E4856460C730E59F4688539", //goerli
}

const OUTPUT_FILE = './mainnetDeployment/eBTCGoerliDeploymentOutput.json'

const DEPLOY_WAIT = 120000 // milli-secnds
const GAS_PRICE = 80000000000 // x Gwei
const MAX_FEE_PER_GAS = 100833966421
const TX_CONFIRMATIONS = 1

const VERIFY_ETHERSCAN = true
const ETHERSCAN_BASE_URL = 'https://goerli.etherscan.io/address'

// Timelock configuration parameters
const HIGHSEC_MIN_DELAY = "600" // 10 mins
const LOWSEC_MIN_DELAY = "300" // 5 mins

const ADDITIONAL_HIGHSEC_ADMIN = ""
const ADDITIONAL_LOWSEC_ADMIN = ""

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
