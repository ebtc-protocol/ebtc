// Define the permissioned function signatures

// CdpManager
const SET_STAKING_REWARD_SPLIT_SIG = (ethers.utils.id('setStakingRewardSplit(uint256)')).substring(0, 10);
// CdpManager
const SET_REDEMPTION_FEE_FLOOR_SIG = ethers.utils.id('setRedemptionFeeFloor(uint256)').substring(0, 10);
// CdpManager
const SET_MINUTE_DECAY_FACTOR_SIG = ethers.utils.id('setMinuteDecayFactor(uint256)').substring(0, 10);
// CdpManager
const SET_BETA_SIG = ethers.utils.id('setBeta(uint256)').substring(0, 10);
// CdpManager
const SET_REDEMPTIONS_PAUSED_SIG = ethers.utils.id('setRedemptionsPaused(bool)').substring(0, 10);
// CdpManagerStorage
const SET_GRACE_PERIOD_SIG = ethers.utils.id('setGracePeriod(uint128)').substring(0, 10);
// EBTCToken
const MINT_SIG = ethers.utils.id('mint(address,uint256)').substring(0, 10);
// EBTCToken
const BURN_SIG = ethers.utils.id('burn(address,uint256)').substring(0, 10);
// EBTCToken
const BURN2_SIG = ethers.utils.id('burn(uint256)').substring(0, 10);
// PriceFeed
const SET_FALLBACK_CALLER_SIG = ethers.utils.id('setFallbackCaller(address)').substring(0, 10);
// PriceFeed
const SET_COLLATERAL_FEED_SOURCE_SIG = ethers.utils.id('setCollateralFeedSource(bool)').substring(0, 10);
// ActivePool & BorrowerOperations
const SET_FEE_BPS_SIG = ethers.utils.id('setFeeBps(uint256)').substring(0, 10);
// ActivePool & BorrowerOperations
const SET_FLASH_LOANS_PAUSED_SIG = ethers.utils.id('setFlashLoansPaused(bool)').substring(0, 10);
// ActivePool & CollSurplusPool & FeeRecipient
const SWEEP_TOKEN_SIG = ethers.utils.id('sweepToken(address,uint256)').substring(0, 10);
// ActivePool
const CLAIM_FEE_RECIPIENT_COLL_SIG = ethers.utils.id('claimFeeRecipientCollShares(uint256)').substring(0, 10);
// Governor
const SET_ROLE_NAME_SIG = ethers.utils.id('setRoleName(uint8,string)').substring(0, 10);
// RolesAuthority
const SET_USER_ROLE_SIG = ethers.utils.id('setUserRole(address,uint8,bool)').substring(0, 10);
// RolesAuthority
const SET_ROLE_CAPABILITY_SIG = ethers.utils.id('setRoleCapability(uint8,address,bytes4,bool)').substring(0, 10);
// RolesAuthority
const SET_PUBLIC_CAPABILITY_SIG = ethers.utils.id('setPublicCapability(address,bytes4,bool)').substring(0, 10);
// RolesAuthority
const BURN_CAPABILITY_SIG = ethers.utils.id('burnCapability(address,bytes4)').substring(0, 10);
// Auth
const TRANSFER_OWNERSHIP_SIG = ethers.utils.id('transferOwnership(address)').substring(0, 10);
// Auth
const SET_AUTHORITY_SIG = ethers.utils.id('setAuthority(address)').substring(0, 10);
// EbtcFeed
const SET_PRIMARY_ORACLE_SIG = ethers.utils.id('setPrimaryOracle(address)').substring(0, 10);
// EbtcFeed
const SET_SECONDARY_ORACLE_SIG = ethers.utils.id('setSecondaryOracle(address)').substring(0, 10);

module.exports = {
  SET_STAKING_REWARD_SPLIT_SIG,
  SET_REDEMPTION_FEE_FLOOR_SIG,
  SET_MINUTE_DECAY_FACTOR_SIG,
  SET_BETA_SIG,
  SET_REDEMPTIONS_PAUSED_SIG,
  SET_GRACE_PERIOD_SIG,
  MINT_SIG,
  BURN_SIG,
  BURN2_SIG,
  SET_FALLBACK_CALLER_SIG,
  SET_COLLATERAL_FEED_SOURCE_SIG,
  SET_FEE_BPS_SIG,
  SET_FLASH_LOANS_PAUSED_SIG,
  SWEEP_TOKEN_SIG,
  CLAIM_FEE_RECIPIENT_COLL_SIG,
  SET_ROLE_NAME_SIG,
  SET_USER_ROLE_SIG,
  SET_ROLE_CAPABILITY_SIG,
  SET_PUBLIC_CAPABILITY_SIG,
  BURN_CAPABILITY_SIG,
  TRANSFER_OWNERSHIP_SIG,
  SET_AUTHORITY_SIG,
  SET_PRIMARY_ORACLE_SIG,
  SET_SECONDARY_ORACLE_SIG
};
