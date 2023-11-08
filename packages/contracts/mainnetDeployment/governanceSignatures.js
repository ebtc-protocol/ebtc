// Define the permissioned function signatures
const SET_STAKING_REWARD_SPLIT_SIG = ethers.utils.id('setStakingRewardSplit(uint256)');
const SET_REDEMPTION_FEE_FLOOR_SIG = ethers.utils.id('setRedemptionFeeFloor(uint256)');
const SET_MINUTE_DECAY_FACTOR_SIG = ethers.utils.id('setMinuteDecayFactor(uint256)');
const SET_BETA_SIG = ethers.utils.id('setBeta(uint256)');
const SET_REDEMPTIONS_PAUSED_SIG = ethers.utils.id('setRedemptionsPaused(bool)');
const SET_GRACE_PERIOD_SIG = ethers.utils.id('setGracePeriod(uint128)');
const MINT_SIG = ethers.utils.id('mint(address,uint256)');
const BURN_SIG = ethers.utils.id('burn(address,uint256)');
const BURN2_SIG = ethers.utils.id('burn(uint256)');
const SET_FALLBACK_CALLER_SIG = ethers.utils.id('setFallbackCaller(address)');
const SET_FEE_BPS_SIG = ethers.utils.id('setFeeBps(uint256)');
const SET_FLASH_LOANS_PAUSED_SIG = ethers.utils.id('setFlashLoansPaused(bool)');
const SET_MAX_FEE_BPS_SIG = ethers.utils.id('setMaxFeeBps(uint256)');
const SWEEP_TOKEN_SIG = ethers.utils.id('sweepToken(address,uint256)');
const CLAIM_FEE_RECIPIENT_COLL_SIG = ethers.utils.id('claimFeeRecipientCollShares(uint256)');
const SET_FEE_RECIPIENT_ADDRESS_SIG = ethers.utils.id('setFeeRecipientAddress(address)');
const SET_ROLE_NAME_SIG = ethers.utils.id('setRoleName(uint8,string)');
const SET_USER_ROLE_SIG = ethers.utils.id('setUserRole(address,uint8,bool)');
const SET_ROLE_CAPABILITY_SIG = ethers.utils.id('setRoleCapability(uint8,address,bytes4,bool)');
const SET_PUBLIC_CAPABILITY_SIG = ethers.utils.id('setPublicCapability(address,bytes4,bool)');
const BURN_CAPABILITY_SIG = ethers.utils.id('burnCapability(address,bytes4)');
const TRANSFER_OWNERSHIP_SIG = ethers.utils.id('transferOwnership(address)');
const SET_AUTHORITY_SIG = ethers.utils.id('setAuthority(address)');

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
  SET_FEE_BPS_SIG,
  SET_FLASH_LOANS_PAUSED_SIG,
  SET_MAX_FEE_BPS_SIG,
  SWEEP_TOKEN_SIG,
  CLAIM_FEE_RECIPIENT_COLL_SIG,
  SET_FEE_RECIPIENT_ADDRESS_SIG,
  SET_ROLE_NAME_SIG,
  SET_USER_ROLE_SIG,
  SET_ROLE_CAPABILITY_SIG,
  SET_PUBLIC_CAPABILITY_SIG,
  BURN_CAPABILITY_SIG,
  TRANSFER_OWNERSHIP_SIG,
  SET_AUTHORITY_SIG
};
