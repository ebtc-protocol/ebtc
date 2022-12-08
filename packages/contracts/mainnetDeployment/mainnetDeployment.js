const { UniswapV2Factory } = require("./ABIs/UniswapV2Factory.js")
const { UniswapV2Pair } = require("./ABIs/UniswapV2Pair.js")
const { UniswapV2Router02 } = require("./ABIs/UniswapV2Router02.js")
const { ChainlinkAggregatorV3Interface } = require("./ABIs/ChainlinkAggregatorV3Interface.js")
const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const { dec } = th
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")
const toBigNum = ethers.BigNumber.from

async function mainnetDeploy(configParams) {
  const date = new Date()
  console.log(date.toUTCString())
  const deployerWallet = (await ethers.getSigners())[0]
  const account2Wallet = (await ethers.getSigners())[1]
  const mdh = new MainnetDeploymentHelper(configParams, deployerWallet)
  const gasPrice = configParams.GAS_PRICE

  let latestBlock = await ethers.provider.getBlockNumber()
  console.log('block number:', latestBlock)

  const deploymentState = mdh.loadPreviousDeployment()

  console.log(`deployer address: ${deployerWallet.address}`)
  console.log(`Account2 address: ${account2Wallet.address}`)
  assert.equal(deployerWallet.address, configParams.liquityAddrs.DEPLOYER)
  assert.equal(account2Wallet.address, configParams.liquityAddrs.ACCOUNT_2)
  let deployerETHBalance = await ethers.provider.getBalance(deployerWallet.address)
  let account2ETHBalance = await ethers.provider.getBalance(deployerWallet.address)
  console.log(`deployerETHBalance before: ${deployerETHBalance}`)
  console.log(`account2ETHBalance before: ${account2ETHBalance}`)

  // Get UniswapV2Factory instance at its deployed address
  const uniswapV2Factory = new ethers.Contract(
    configParams.externalAddrs.UNISWAP_V2_FACTORY,
    UniswapV2Factory.abi,
    deployerWallet
  )

  console.log(`Uniswp addr: ${uniswapV2Factory.address}`)
  const uniAllPairsLength = await uniswapV2Factory.allPairsLength()
  console.log(`Uniswap Factory number of pairs: ${uniAllPairsLength}`)

  deployerETHBalance = await ethers.provider.getBalance(deployerWallet.address)
  console.log(`deployer's ETH balance before deployments: ${deployerETHBalance}`)

  // Deploy core logic contracts
  const liquityCore = await mdh.deployLiquityCoreMainnet(configParams.externalAddrs.TELLOR_MASTER, deploymentState)
  await mdh.logContractObjects(liquityCore)

  // Check Uniswap Pair EBTC-ETH pair before pair creation
  let EBTCWETHPairAddr = await uniswapV2Factory.getPair(liquityCore.ebtcToken.address, configParams.externalAddrs.WETH_ERC20)
  let WETHEBTCPairAddr = await uniswapV2Factory.getPair(configParams.externalAddrs.WETH_ERC20, liquityCore.ebtcToken.address)
  assert.equal(EBTCWETHPairAddr, WETHEBTCPairAddr)


  if (EBTCWETHPairAddr == th.ZERO_ADDRESS) {
    // Deploy Unipool for EBTC-WETH
    await mdh.sendAndWaitForTransaction(uniswapV2Factory.createPair(
      configParams.externalAddrs.WETH_ERC20,
      liquityCore.ebtcToken.address,
      { gasPrice }
    ))

    // Check Uniswap Pair EBTC-WETH pair after pair creation (forwards and backwards should have same address)
    EBTCWETHPairAddr = await uniswapV2Factory.getPair(liquityCore.ebtcToken.address, configParams.externalAddrs.WETH_ERC20)
    assert.notEqual(EBTCWETHPairAddr, th.ZERO_ADDRESS)
    WETHEBTCPairAddr = await uniswapV2Factory.getPair(configParams.externalAddrs.WETH_ERC20, liquityCore.ebtcToken.address)
    console.log(`EBTC-WETH pair contract address after Uniswap pair creation: ${EBTCWETHPairAddr}`)
    assert.equal(WETHEBTCPairAddr, EBTCWETHPairAddr)
  }

  // Deploy Unipool
  const unipool = await mdh.deployUnipoolMainnet(deploymentState)

  // Deploy LQTY Contracts
  const LQTYContracts = await mdh.deployLQTYContractsMainnet(
    configParams.liquityAddrs.GENERAL_SAFE, // bounty address
    unipool.address,  // lp rewards address
    configParams.liquityAddrs.LQTY_SAFE, // multisig LQTY endowment address
    deploymentState,
  )

  // Connect all core contracts up
  await mdh.connectCoreContractsMainnet(liquityCore, LQTYContracts, configParams.externalAddrs.CHAINLINK_ETHUSD_PROXY)
  await mdh.connectLQTYContractsMainnet(LQTYContracts)
  await mdh.connectLQTYContractsToCoreMainnet(LQTYContracts, liquityCore)

  // Deploy a read-only multi-cdp getter
  const multiCdpGetter = await mdh.deployMultiCdpGetterMainnet(liquityCore, deploymentState)

  // Connect Unipool to LQTYToken and the EBTC-WETH pair address, with a 6 week duration
  const LPRewardsDuration = timeVals.SECONDS_IN_SIX_WEEKS
  await mdh.connectUnipoolMainnet(unipool, LQTYContracts, EBTCWETHPairAddr, LPRewardsDuration)

  // Log LQTY and Unipool addresses
  await mdh.logContractObjects(LQTYContracts)
  console.log(`Unipool address: ${unipool.address}`)

  let deploymentStartTime = await LQTYContracts.lqtyToken.getDeploymentStartTime()

  console.log(`deployment start time: ${deploymentStartTime}`)
  const oneYearFromDeployment = (Number(deploymentStartTime) + timeVals.SECONDS_IN_ONE_YEAR).toString()
  console.log(`time oneYearFromDeployment: ${oneYearFromDeployment}`)

  // Deploy LockupContracts - one for each beneficiary
  const lockupContracts = {}

  for (const [investor, investorAddr] of Object.entries(configParams.beneficiaries)) {
    const lockupContractEthersFactory = await ethers.getContractFactory("LockupContract", deployerWallet)
    if (deploymentState[investor] && deploymentState[investor].address) {
      console.log(`Using previously deployed ${investor} lockup contract at address ${deploymentState[investor].address}`)
      lockupContracts[investor] = new ethers.Contract(
        deploymentState[investor].address,
        lockupContractEthersFactory.interface,
        deployerWallet
      )
    } else {
      const txReceipt = await mdh.sendAndWaitForTransaction(LQTYContracts.lockupContractFactory.deployLockupContract(investorAddr, oneYearFromDeployment, { gasPrice }))

      const address = await txReceipt.logs[0].address // The deployment event emitted from the LC itself is is the first of two events, so this is its address 
      lockupContracts[investor] = new ethers.Contract(
        address,
        lockupContractEthersFactory.interface,
        deployerWallet
      )

      deploymentState[investor] = {
        address: address,
        txHash: txReceipt.transactionHash
      }

      mdh.saveDeployment(deploymentState)
    }

    const lqtyTokenAddr = LQTYContracts.lqtyToken.address
    // verify
    if (configParams.ETHERSCAN_BASE_URL) {
      await mdh.verifyContract(investor, deploymentState, [lqtyTokenAddr, investorAddr, oneYearFromDeployment])
    }
  }
  
  // Check chainlink proxy price ---

  const chainlinkProxy = new ethers.Contract(
    configParams.externalAddrs.CHAINLINK_ETHUSD_PROXY,
    ChainlinkAggregatorV3Interface,
    deployerWallet
  )

  // Get latest price
  let chainlinkPrice = await chainlinkProxy.latestAnswer()
  console.log(`current Chainlink price: ${chainlinkPrice}`)

  // Check Tellor price directly (through our TellorCaller)
  let tellorPriceResponse = await liquityCore.tellorCaller.getTellorCurrentValue(1) // id == 1: the ETH-USD request ID
  console.log(`current Tellor price: ${tellorPriceResponse[1]}`)
  console.log(`current Tellor timestamp: ${tellorPriceResponse[2]}`)

  // // --- Lockup Contracts ---
  console.log("LOCKUP CONTRACT CHECKS")
  // Check lockup contracts exist for each beneficiary with correct unlock time
  for (investor of Object.keys(lockupContracts)) {
    const lockupContract = lockupContracts[investor]
    // check LC references correct LQTYToken 
    const storedLQTYTokenAddr = await lockupContract.lqtyToken()
    assert.equal(LQTYContracts.lqtyToken.address, storedLQTYTokenAddr)
    // Check contract has stored correct beneficary
    const onChainBeneficiary = await lockupContract.beneficiary()
    assert.equal(configParams.beneficiaries[investor].toLowerCase(), onChainBeneficiary.toLowerCase())
    // Check correct unlock time (1 yr from deployment)
    const unlockTime = await lockupContract.unlockTime()
    assert.equal(oneYearFromDeployment, unlockTime)

    console.log(
      `lockupContract addr: ${lockupContract.address},
            stored LQTYToken addr: ${storedLQTYTokenAddr}
            beneficiary: ${investor},
            beneficiary addr: ${configParams.beneficiaries[investor]},
            on-chain beneficiary addr: ${onChainBeneficiary},
            unlockTime: ${unlockTime}
            `
    )
  }

  // --- PriceFeed ---
  console.log("PRICEFEED CHECKS")
  // Check Pricefeed's status and last good price
  const lastGoodPrice = await liquityCore.priceFeed.lastGoodPrice()
  const priceFeedInitialStatus = await liquityCore.priceFeed.status()
  th.logBN('PriceFeed first stored price', lastGoodPrice)
  console.log(`PriceFeed initial status: ${priceFeedInitialStatus}`)

  // Check PriceFeed's & TellorCaller's stored addresses
  const priceFeedCLAddress = await liquityCore.priceFeed.priceAggregator()
  const priceFeedTellorCallerAddress = await liquityCore.priceFeed.tellorCaller()
  assert.equal(priceFeedCLAddress, configParams.externalAddrs.CHAINLINK_ETHUSD_PROXY)
  assert.equal(priceFeedTellorCallerAddress, liquityCore.tellorCaller.address)

  // Check Tellor address
  const tellorCallerTellorMasterAddress = await liquityCore.tellorCaller.tellor()
  assert.equal(tellorCallerTellorMasterAddress, configParams.externalAddrs.TELLOR_MASTER)

  // --- Unipool ---

  // Check Unipool's EBTC-ETH Uniswap Pair address
  const unipoolUniswapPairAddr = await unipool.uniToken()
  console.log(`Unipool's stored EBTC-ETH Uniswap Pair address: ${unipoolUniswapPairAddr}`)

  console.log("SYSTEM GLOBAL VARS CHECKS")
  // --- Sorted Cdps ---

  // Check max size
  const sortedCdpsMaxSize = (await liquityCore.sortedCdps.data())[2]
  assert.equal(sortedCdpsMaxSize, '115792089237316195423570985008687907853269984665640564039457584007913129639935')

  // --- CdpManager ---

  const liqReserve = await liquityCore.cdpManager.EBTC_GAS_COMPENSATION()
  const minNetDebt = await liquityCore.cdpManager.MIN_NET_DEBT()

  th.logBN('system liquidation reserve', liqReserve)
  th.logBN('system min net debt      ', minNetDebt)

  // --- Make first EBTC-ETH liquidity provision ---

  // Open cdp if not yet opened
  let cdpCount = await liquityCore.sortedCdps.cdpCountOf(deployerWallet.address)
  if (cdpCount.toString() == '0') {
    let _3kEBTCWithdrawal = th.dec(3000, 18) // 3000 EBTC
    let _3ETHcoll = th.dec(30, 'ether') // 3 ETH
    console.log("Deployer opens a cdp ...")
    await mdh.sendAndWaitForTransaction(
      liquityCore.borrowerOperations.openCdp(
        th._100pct,
        _3kEBTCWithdrawal,
        th.DUMMY_BYTES32,
        th.DUMMY_BYTES32,
        { value: _3ETHcoll, gasPrice }
      )
    )
  } else {
    console.log('Deployer already has an active cdp')
  }

  // Check deployer now has an open cdp
  cdpCount = await liquityCore.sortedCdps.cdpCountOf(deployerWallet.address)
  assert.equal(cdpCount, 1)
  const cdpId = await liquityCore.sortedCdps._ownedCdps(deployerWallet.address, 0)
  console.log(`deployer is in sorted list after making cdp: ${await liquityCore.sortedCdps.contains(cdpId)}`)

  const deployerCdp = await liquityCore.cdpManager.Cdps(cdpId)
  th.logBN('deployer debt', deployerCdp[0])
  th.logBN('deployer coll', deployerCdp[1])
  th.logBN('deployer stake', deployerCdp[2])
  console.log(`deployer's cdp status: ${deployerCdp[3]}`)

  // Check deployer has EBTC
  let deployerEBTCBal = await liquityCore.ebtcToken.balanceOf(deployerWallet.address)
  th.logBN("deployer's EBTC balance", deployerEBTCBal)



  // Check Uniswap pool has EBTC and WETH tokens
  const EBTCETHPair = await new ethers.Contract(
    EBTCWETHPairAddr,
    UniswapV2Pair.abi,
    deployerWallet
  )

  const token0Addr = await EBTCETHPair.token0()
  const token1Addr = await EBTCETHPair.token1()
  console.log(`EBTC-ETH Pair token 0: ${th.squeezeAddr(token0Addr)},
        EBTCToken contract addr: ${th.squeezeAddr(liquityCore.ebtcToken.address)}`)
  console.log(`EBTC-ETH Pair token 1: ${th.squeezeAddr(token1Addr)},
        WETH ERC20 contract addr: ${th.squeezeAddr(configParams.externalAddrs.WETH_ERC20)}`)

  // Check initial EBTC-ETH pair reserves before provision
  let reserves = await EBTCETHPair.getReserves()
  th.logBN("EBTC-ETH Pair's EBTC reserves before provision", reserves[0])
  th.logBN("EBTC-ETH Pair's ETH reserves before provision", reserves[1])

  // Get the UniswapV2Router contract
  const uniswapV2Router02 = new ethers.Contract(
    configParams.externalAddrs.UNISWAP_V2_ROUTER02,
    UniswapV2Router02.abi,
    deployerWallet
  )

  // --- Provide liquidity to EBTC-ETH pair if not yet done so ---
  let deployerLPTokenBal = await EBTCETHPair.balanceOf(deployerWallet.address)
  if (deployerLPTokenBal.toString() == '0') {
    console.log('Providing liquidity to Uniswap...')
    // Give router an allowance for EBTC
    await liquityCore.ebtcToken.increaseAllowance(uniswapV2Router02.address, dec(10000, 18))

    // Check Router's spending allowance
    const routerEBTCAllowanceFromDeployer = await liquityCore.ebtcToken.allowance(deployerWallet.address, uniswapV2Router02.address)
    th.logBN("router's spending allowance for deployer's EBTC", routerEBTCAllowanceFromDeployer)

    // Get amounts for liquidity provision
    const LP_ETH = dec(1, 'ether')

    // Convert 8-digit CL price to 18 and multiply by ETH amount
    const EBTCAmount = toBigNum(chainlinkPrice)
      .mul(toBigNum(dec(1, 10)))
      .mul(toBigNum(LP_ETH))
      .div(toBigNum(dec(1, 18)))

    const minEBTCAmount = EBTCAmount.sub(toBigNum(dec(100, 18)))

    latestBlock = await ethers.provider.getBlockNumber()
    now = (await ethers.provider.getBlock(latestBlock)).timestamp
    let tenMinsFromNow = now + (60 * 60 * 10)

    // Provide liquidity to EBTC-ETH pair
    await mdh.sendAndWaitForTransaction(
      uniswapV2Router02.addLiquidityETH(
        liquityCore.ebtcToken.address, // address of EBTC token
        EBTCAmount, // EBTC provision
        minEBTCAmount, // minimum EBTC provision
        LP_ETH, // minimum ETH provision
        deployerWallet.address, // address to send LP tokens to
        tenMinsFromNow, // deadline for this tx
        {
          value: dec(1, 'ether'),
          gasPrice,
          gasLimit: 5000000 // For some reason, ethers can't estimate gas for this tx
        }
      )
    )
  } else {
    console.log('Liquidity already provided to Uniswap')
  }
  // Check EBTC-ETH reserves after liquidity provision:
  reserves = await EBTCETHPair.getReserves()
  th.logBN("EBTC-ETH Pair's EBTC reserves after provision", reserves[0])
  th.logBN("EBTC-ETH Pair's ETH reserves after provision", reserves[1])



  // --- 2nd Account opens cdp ---
  cdpCount = await liquityCore.sortedCdps.cdpCountOf(account2Wallet.address)
  if (cdpCount.toString() == '0') {
    console.log("Acct 2 opens a cdp ...")
    let _1500EBTCWithdrawal = th.dec(3000, 18) // 3000 EBTC
    let _15_ETHcoll = th.dec(30, 18) // 30 ETH
    const borrowerOpsEthersFactory = await ethers.getContractFactory("BorrowerOperations", account2Wallet)
    const borrowerOpsAcct2 = await new ethers.Contract(liquityCore.borrowerOperations.address, borrowerOpsEthersFactory.interface, account2Wallet)

    await mdh.sendAndWaitForTransaction(borrowerOpsAcct2.openCdp(th._100pct, _1500EBTCWithdrawal, th.DUMMY_BYTES32, th.DUMMY_BYTES32, { value: _15_ETHcoll, gasPrice, gasLimit: 1000000 }))
  } else {
    console.log('Acct 2 already has an active cdp')
  }

  // Check deployer now has an open cdp
  cdpCount = await liquityCore.sortedCdps.cdpCountOf(account2Wallet.address)
  assert.equal(cdpCount, 1)
  const cdpId2 = await liquityCore.sortedCdps._ownedCdps(account2Wallet.address, 0)
  console.log(`Acct 2 is in sorted list after making cdp: ${await liquityCore.sortedCdps.contains(cdpId2)}`)

  const acct2Cdp = await liquityCore.cdpManager.Cdps(cdpId2)
  th.logBN('acct2 debt', acct2Cdp[0])
  th.logBN('acct2 coll', acct2Cdp[1])
  th.logBN('acct2 stake', acct2Cdp[2])
  console.log(`acct2 cdp status: ${acct2Cdp[3]}`)

  // Check deployer has EBTC
  let account2EBTCBal = await liquityCore.ebtcToken.balanceOf(account2Wallet.address)
  th.logBN("Account2's EBTC balance", account2EBTCBal)


  // // --- System stats  ---

  // Uniswap EBTC-ETH pool size
  reserves = await EBTCETHPair.getReserves()
  th.logBN("EBTC-ETH Pair's current EBTC reserves", reserves[0])
  th.logBN("EBTC-ETH Pair's current ETH reserves", reserves[1])

  // Number of cdps
  const numCdps = await liquityCore.cdpManager.getCdpIdsCount()
  console.log(`number of cdps: ${numCdps} `)

  // Sorted list size
  const listSize = await liquityCore.sortedCdps.getSize()
  console.log(`Cdp list size: ${listSize} `)

  // Total system debt and coll
  const entireSystemDebt = await liquityCore.cdpManager.getEntireSystemDebt()
  const entireSystemColl = await liquityCore.cdpManager.getEntireSystemColl()
  th.logBN("Entire system debt", entireSystemDebt)
  th.logBN("Entire system coll", entireSystemColl)
  
  // TCR
  const TCR = await liquityCore.cdpManager.getTCR(chainlinkPrice)
  console.log(`TCR: ${TCR}`)

  // current borrowing rate
  const baseRate = await liquityCore.cdpManager.baseRate()
  const currentBorrowingRate = await liquityCore.cdpManager.getBorrowingRateWithDecay()
  th.logBN("Base rate", baseRate)
  th.logBN("Current borrowing rate", currentBorrowingRate)

  // --- State variables ---

  // CdpManager 
  console.log("CdpManager state variables:")
  const totalStakes = await liquityCore.cdpManager.totalStakes()
  const totalStakesSnapshot = await liquityCore.cdpManager.totalStakesSnapshot()
  const totalCollateralSnapshot = await liquityCore.cdpManager.totalCollateralSnapshot()
  th.logBN("Total cdp stakes", totalStakes)
  th.logBN("Snapshot of total cdp stakes before last liq. ", totalStakesSnapshot)
  th.logBN("Snapshot of total cdp collateral before last liq. ", totalCollateralSnapshot)

  const L_ETH = await liquityCore.cdpManager.L_ETH()
  const L_EBTCDebt = await liquityCore.cdpManager.L_EBTCDebt()
  th.logBN("L_ETH", L_ETH)
  th.logBN("L_EBTCDebt", L_EBTCDebt)


  // TODO: Uniswap *LQTY-ETH* pool size (check it's deployed?)

  // ************************
  // --- NOT FOR APRIL 5: Deploy a LQTYToken2 with General Safe as beneficiary to test minting LQTY showing up in Gnosis App  ---

  // // General Safe LQTY bal before:
  // const realGeneralSafeAddr = "0xF06016D822943C42e3Cb7FC3a6A3B1889C1045f8"

  //   const LQTYToken2EthersFactory = await ethers.getContractFactory("LQTYToken2", deployerWallet)
  //   const lqtyToken2 = await LQTYToken2EthersFactory.deploy( 
  //     "0xF41E0DD45d411102ed74c047BdA544396cB71E27",  // CI param: LC1 
  //     "0x9694a04263593AC6b895Fc01Df5929E1FC7495fA", // LQTY Staking param: LC2
  //     "0x98f95E112da23c7b753D8AE39515A585be6Fb5Ef", // LCF param: LC3
  //     realGeneralSafeAddr,  // bounty/hackathon param: REAL general safe addr
  //     "0x98f95E112da23c7b753D8AE39515A585be6Fb5Ef", // LP rewards param: LC3
  //     deployerWallet.address, // multisig param: deployer wallet
  //     {gasPrice, gasLimit: 10000000}
  //   )

  //   console.log(`lqty2 address: ${lqtyToken2.address}`)

  //   let generalSafeLQTYBal = await lqtyToken2.balanceOf(realGeneralSafeAddr)
  //   console.log(`generalSafeLQTYBal: ${generalSafeLQTYBal}`)



  // ************************
  // --- NOT FOR APRIL 5: Test short-term lockup contract LQTY withdrawal on mainnet ---

  // now = (await ethers.provider.getBlock(latestBlock)).timestamp

  // const LCShortTermEthersFactory = await ethers.getContractFactory("LockupContractShortTerm", deployerWallet)

  // new deployment
  // const LCshortTerm = await LCShortTermEthersFactory.deploy(
  //   LQTYContracts.lqtyToken.address,
  //   deployerWallet.address,
  //   now, 
  //   {gasPrice, gasLimit: 1000000}
  // )

  // LCshortTerm.deployTransaction.wait()

  // existing deployment
  // const deployedShortTermLC = await new ethers.Contract(
  //   "0xbA8c3C09e9f55dA98c5cF0C28d15Acb927792dC7", 
  //   LCShortTermEthersFactory.interface,
  //   deployerWallet
  // )

  // new deployment
  // console.log(`Short term LC Address:  ${LCshortTerm.address}`)
  // console.log(`recorded beneficiary in short term LC:  ${await LCshortTerm.beneficiary()}`)
  // console.log(`recorded short term LC name:  ${await LCshortTerm.NAME()}`)

  // existing deployment
  //   console.log(`Short term LC Address:  ${deployedShortTermLC.address}`)
  //   console.log(`recorded beneficiary in short term LC:  ${await deployedShortTermLC.beneficiary()}`)
  //   console.log(`recorded short term LC name:  ${await deployedShortTermLC.NAME()}`)
  //   console.log(`recorded short term LC name:  ${await deployedShortTermLC.unlockTime()}`)
  //   now = (await ethers.provider.getBlock(latestBlock)).timestamp
  //   console.log(`time now: ${now}`)

  //   // check deployer LQTY bal
  //   let deployerLQTYBal = await LQTYContracts.lqtyToken.balanceOf(deployerWallet.address)
  //   console.log(`deployerLQTYBal before he withdraws: ${deployerLQTYBal}`)

  //   // check LC LQTY bal
  //   let LC_LQTYBal = await LQTYContracts.lqtyToken.balanceOf(deployedShortTermLC.address)
  //   console.log(`LC LQTY bal before withdrawal: ${LC_LQTYBal}`)

  // // withdraw from LC
  // const withdrawFromShortTermTx = await deployedShortTermLC.withdrawLQTY( {gasPrice, gasLimit: 1000000})
  // withdrawFromShortTermTx.wait()

  // // check deployer bal after LC withdrawal
  // deployerLQTYBal = await LQTYContracts.lqtyToken.balanceOf(deployerWallet.address)
  // console.log(`deployerLQTYBal after he withdraws: ${deployerLQTYBal}`)

  //   // check LC LQTY bal
  //   LC_LQTYBal = await LQTYContracts.lqtyToken.balanceOf(deployedShortTermLC.address)
  //   console.log(`LC LQTY bal after withdrawal: ${LC_LQTYBal}`)
}

module.exports = {
  mainnetDeploy
}
