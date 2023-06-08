from brownie import Wei

ZERO_ADDRESS = '0x' + '0'.zfill(40)
MAX_BYTES_32 = '0x' + 'F' * 64

def floatToWei(amount):
    return Wei(amount * 1e18)

# Subtracts the borrowing fee
def get_ebtc_amount_from_net_debt(contracts, net_debt):
    borrowing_rate = contracts.cdpManager.getBorrowingRateWithDecay()
    return Wei(net_debt * Wei(1e18) / (Wei(1e18) + borrowing_rate))

def logGlobalState(contracts):
    print('\n ---- Global state ----')
    num_cdps = contracts.sortedCdps.getSize()
    print('Num cdps      ', num_cdps)
    activePoolColl = contracts.activePool.getStEthColl()
    activePoolDebt = contracts.activePool.getEBTCDebt()
    defaultPoolColl = contracts.defaultPool.getStEthColl()
    defaultPoolDebt = contracts.defaultPool.getEBTCDebt()
    total_debt = (activePoolDebt + defaultPoolDebt).to("ether")
    total_coll = (activePoolColl + defaultPoolColl).to("ether")
    print('Total Debt      ', total_debt)
    print('Total Coll      ', total_coll)
    SP_EBTC = contracts.stabilityPool.getTotalEBTCDeposits().to("ether")
    SP_ETH = contracts.stabilityPool.getStEthColl().to("ether")
    print('SP EBTC         ', SP_EBTC)
    print('SP ETH          ', SP_ETH)
    price_ether_current = contracts.priceFeedTestnet.getPrice()
    ETH_price = price_ether_current.to("ether")
    print('ETH price       ', ETH_price)
    TCR = contracts.cdpManager.getTCR(price_ether_current).to("ether")
    print('TCR             ', TCR)
    recovery_mode = contracts.cdpManager.checkRecoveryMode(price_ether_current)
    print('Rec. Mode       ', recovery_mode)
    stakes_snapshot = contracts.cdpManager.totalStakesSnapshot()
    coll_snapshot = contracts.cdpManager.totalCollateralSnapshot()
    print('Stake snapshot  ', stakes_snapshot.to("ether"))
    print('Coll snapshot   ', coll_snapshot.to("ether"))
    if stakes_snapshot > 0:
        print('Snapshot ratio  ', coll_snapshot / stakes_snapshot)
    last_cdp = contracts.sortedCdps.getLast()
    last_ICR = contracts.cdpManager.getCurrentICR(last_cdp, price_ether_current).to("ether")
    #print('Last cdp      ', last_cdp)
    print('Last cdp’s ICR', last_ICR)
    print(' ----------------------\n')

    return [ETH_price, num_cdps, total_coll, total_debt, TCR, recovery_mode, last_ICR, SP_EBTC, SP_ETH]
