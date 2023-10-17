const { TestHelper: th } = require("../utils/testHelpers.js")

const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxy = artifacts.require('DSProxy')

const buildUserProxies = async (users) => {
  const proxies = {}
  const proxyFactory = await DSProxyFactory.new()
  for(let user of users) {
    const proxyTx = await proxyFactory.build({ from: user })
    proxies[user] = await DSProxy.at(proxyTx.logs[0].args.proxy)
  }

  return proxies
}

class Proxy {
  constructor (owner, proxies, scriptAddress, contract) {
    this.owner = owner
    this.proxies = proxies
    this.scriptAddress = scriptAddress
    this.contract = contract
    if (contract) this.address = contract.address
  }

  getFrom(params) {
    if (params.length == 0) return this.owner
    let lastParam = params[params.length - 1]
    if (lastParam.from) {
      return lastParam.from
    }

    return this.owner
  }

  getOptionalParams(params) {
    if (params.length == 0) return {}

    return params[params.length - 1]
  }

  getProxyAddressFromUser(user) {
    return this.proxies[user] ? this.proxies[user].address : user
  }

  getProxyFromUser(user) {
    return this.proxies[user]
  }

  getProxyFromParams(params) {
    const user = this.getFrom(params)
    return this.proxies[user]
  }

  getSlicedParams(params) {
    if (params.length == 0) return params
    let lastParam = params[params.length - 1]
    if (lastParam.from || lastParam.value) {
      return params.slice(0, -1)
    }

    return params
  }

  async forwardFunction(params, signature) {
    const proxy = this.getProxyFromParams(params)
    if (!proxy) {
      return this.proxyFunction(signature.slice(0, signature.indexOf('(')), params)
    }
    const optionalParams = this.getOptionalParams(params)
    const calldata = th.getTransactionData(signature, this.getSlicedParams(params))
    // console.log('proxy: ', proxy.address)
    // console.log(this.scriptAddress, calldata, optionalParams)
    return proxy.methods["execute(address,bytes)"](this.scriptAddress, calldata, optionalParams)
  }

  async proxyFunctionWithUser(functionName, user) {
    return this.contract[functionName](this.getProxyAddressFromUser(user))
  }

  async proxyFunction(functionName, params) {
    // console.log('contract: ', this.contract.address)
    // console.log('functionName: ', functionName)
    // console.log('params: ', params)
    return this.contract[functionName](...params)
  }
}

class BorrowerOperationsProxy extends Proxy {
  constructor(owner, proxies, borrowerOperationsScriptAddress, borrowerOperations) {
    super(owner, proxies, borrowerOperationsScriptAddress, borrowerOperations)
  }

  async openCdp(...params) {
    return this.forwardFunction(params, 'openCdp(uint256,bytes32,bytes32,uint256)')
  }

  async addColl(...params) {
    return this.forwardFunction(params, 'addColl(bytes32,bytes32,uint256)')
  }

  async withdrawColl(...params) {
    return this.forwardFunction(params, 'withdrawColl(uint256,bytes32,bytes32)')
  }

  async withdrawDebt(...params) {
    return this.forwardFunction(params, 'withdrawDebt(uint256,bytes32,bytes32)')
  }

  async repayDebt(...params) {
    return this.forwardFunction(params, 'repayDebt(uint256,bytes32,bytes32)')
  }

  async closeCdp(...params) {
    return this.forwardFunction(params, 'closeCdp()')
  }

  async adjustCdp(...params) {
    return this.forwardFunction(params, 'adjustCdp(uint256,uint256,uint256,bool,bytes32,bytes32)')
  }

  async adjustCdpWithColl(...params) {
    return this.forwardFunction(params, 'adjustCdpWithColl(uint256,uint256,uint256,bool,bytes32,bytes32,uint256)')
  }

  async claimRedeemedCollateral(...params) {
    return this.forwardFunction(params, 'claimRedeemedCollateral(address)')
  }

  async getNewTCRFromCdpChange(...params) {
    return this.proxyFunction('getNewTCRFromCdpChange', params)
  }

  async getNewICRFromCdpChange(...params) {
    return this.proxyFunction('getNewICRFromCdpChange', params)
  }

  async LIQUIDATOR_REWARD(...params) {
    return this.proxyFunction('LIQUIDATOR_REWARD', params)
  }

  async MIN_NET_STETH_BALANCE(...params) {
    return this.proxyFunction('MIN_NET_STETH_BALANCE', params)
  }

  async BORROWING_FEE_FLOOR(...params) {
    return this.proxyFunction('BORROWING_FEE_FLOOR', params)
  }
}

class BorrowerWrappersProxy extends Proxy {
  constructor(owner, proxies, borrowerWrappersScriptAddress) {
    super(owner, proxies, borrowerWrappersScriptAddress, null)
  }

  async claimCollateralAndOpenCdp(...params) {
    return this.forwardFunction(params, 'claimCollateralAndOpenCdp(uint256,bytes32,bytes32,uint256)')
  }

  async claimSPRewardsAndRecycle(...params) {
    return this.forwardFunction(params, 'claimSPRewardsAndRecycle(bytes32,uint256,bytes32,bytes32)')
  }

  async claimStakingGainsAndRecycle(...params) {
    return this.forwardFunction(params, 'claimStakingGainsAndRecycle(bytes32,bytes32,bytes32)')
  }

  async transferETH(...params) {
    return this.forwardFunction(params, 'transferETH(address,uint256)')
  }
}

class CdpManagerProxy extends Proxy {
  constructor(owner, proxies, cdpManagerScriptAddress, cdpManager) {
    super(owner, proxies, cdpManagerScriptAddress, cdpManager)
  }

  async Cdps(user) {
    return this.proxyFunctionWithUser('Cdps', user)
  }

  async getCdpStatus(user) {
    return this.proxyFunctionWithUser('getCdpStatus', user)
  }

  async getCdpDebt(user) {
    return this.proxyFunctionWithUser('getCdpDebt', user)
  }

  async getCdpCollShares(user) {
    return this.proxyFunctionWithUser('getCdpCollShares', user)
  }

  async totalStakes() {
    return this.proxyFunction('totalStakes', [])
  }

  async getPendingETHReward(...params) {
    return this.proxyFunction('getPendingETHReward', params)
  }

  async getPendingRedistributedDebt(...params) {
    return this.proxyFunction('getPendingRedistributedDebt', params)
  }

  async liquidate(user) {
    return this.proxyFunctionWithUser('liquidate', user)
  }

  async getCachedTCR(...params) {
    return this.proxyFunction('getTCR', params)
  }

  async getCachedICR(user, price) {
    return this.contract.getCachedICR(this.getProxyAddressFromUser(user), price)
  }

  async checkRecoveryMode(...params) {
    return this.proxyFunction('checkRecoveryMode', params)
  }

  async getCdpOwnersCount() {
    return this.proxyFunction('getCdpOwnersCount', [])
  }

  async baseRate() {
    return this.proxyFunction('baseRate', [])
  }

  async L_STETHColl() {
    return this.proxyFunction('L_STETHColl', [])
  }

  async systemDebtRedistributionIndex() {
    return this.proxyFunction('systemDebtRedistributionIndex', [])
  }

  async cdpDebtRedistributionIndex(user) {
    return this.proxyFunctionWithUser('cdpDebtRedistributionIndex', user)
  }

  async lastRedemptionTimestamp() {
    return this.proxyFunction('lastRedemptionTimestamp', [])
  }

  async redeemCollateral(...params) {
    return this.forwardFunction(params, 'redeemCollateral(uint256,bytes32,bytes32,bytes32,uint256,uint256,uint256)')
  }

  async getActualDebtFromComposite(...params) {
    return this.proxyFunction('getActualDebtFromComposite', params)
  }

  async getRedemptionFeeWithDecay(...params) {
    return this.proxyFunction('getRedemptionFeeWithDecay', params)
  }

  async getSyncedDebtAndCollShares(...params) {
    return this.proxyFunction('getSyncedDebtAndCollShares', params)
  }
}

class SortedCdpsProxy extends Proxy {
  constructor(owner, proxies, sortedCdps) {
    super(owner, proxies, null, sortedCdps)
  }

  async contains(user) {
    return this.proxyFunctionWithUser('contains', user)
  }

  async isEmpty(user) {
    return this.proxyFunctionWithUser('isEmpty', user)
  }

  async findInsertPosition(...params) {
    return this.proxyFunction('findInsertPosition', params)
  }

  async cdpOfOwnerByIndex(...params) {
    return this.forwardFunction(params, 'cdpOfOwnerByIndex(address,uint)')
  }

  async existCdpOwners(...params) {
    return this.forwardFunction(params, 'existCdpOwners(bytes32)')
  }
}

class TokenProxy extends Proxy {
  constructor(owner, proxies, tokenScriptAddress, token) {
    super(owner, proxies, tokenScriptAddress, token)
  }

  async transfer(...params) {
    // switch destination to proxy if any
    params[0] = this.getProxyAddressFromUser(params[0])
    return this.forwardFunction(params, 'transfer(address,uint256)')
  }

  async transferFrom(...params) {
    // switch to proxies if any
    params[0] = this.getProxyAddressFromUser(params[0])
    params[1] = this.getProxyAddressFromUser(params[1])
    return this.forwardFunction(params, 'transferFrom(address,address,uint256)')
  }

  async approve(...params) {
    // switch destination to proxy if any
    params[0] = this.getProxyAddressFromUser(params[0])
    return this.forwardFunction(params, 'approve(address,uint256)')
  }

  async increaseAllowance(...params) {
    // switch destination to proxy if any
    params[0] = this.getProxyAddressFromUser(params[0])
    return this.forwardFunction(params, 'increaseAllowance(address,uint256)')
  }

  async decreaseAllowance(...params) {
    // switch destination to proxy if any
    params[0] = this.getProxyAddressFromUser(params[0])
    return this.forwardFunction(params, 'decreaseAllowance(address,uint256)')
  }

  async totalSupply(...params) {
    return this.proxyFunction('totalSupply', params)
  }

  async balanceOf(user) {
    return this.proxyFunctionWithUser('balanceOf', user)
  }

  async allowance(...params) {
    // switch to proxies if any
    const owner = this.getProxyAddressFromUser(params[0])
    const spender = this.getProxyAddressFromUser(params[1])

    return this.proxyFunction('allowance', [owner, spender])
  }

  async name(...params) {
    return this.proxyFunction('name', params)
  }

  async symbol(...params) {
    return this.proxyFunction('symbol', params)
  }

  async decimals(...params) {
    return this.proxyFunction('decimals', params)
  }
}

class LQTYStakingProxy extends Proxy {
  constructor(owner, proxies, tokenScriptAddress, token) {
    super(owner, proxies, tokenScriptAddress, token)
  }

  async stake(...params) {
    return this.forwardFunction(params, 'stake(uint256)')
  }

  async stakes(user) {
    return this.proxyFunctionWithUser('stakes', user)
  }

  async unstake(...params) {
    return this.forwardFunction(params, 'unstake(uint256)')
  }

  async F_EBTC(user) {
    return this.proxyFunctionWithUser('F_EBTC', user)
  }
}

module.exports = {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  CdpManagerProxy,
  SortedCdpsProxy,
  TokenProxy,
  LQTYStakingProxy
}
