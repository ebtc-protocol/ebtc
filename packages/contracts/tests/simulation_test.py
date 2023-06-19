import csv
import os
from dataclasses import dataclass
from typing import Optional

from eth_abi import encode_abi ## web3.py doesn't have abi.encode for some reason
import pytest
from brownie import *  # noqa

from accounts import *
from helpers import *  # noqa
from simulation_helpers import *


@dataclass
class Contracts:
    priceFeedTestnet: Optional[Contract] = None
    sortedCdps: Optional[Contract] = None
    cdpManager: Optional[Contract] = None
    activePool: Optional[Contract] = None
    stabilityPool: Optional[Contract] = None
    gasPool: Optional[Contract] = None
    defaultPool: Optional[Contract] = None
    collSurplusPool: Optional[Contract] = None
    borrowerOperations: Optional[Contract] = None
    hintHelpers: Optional[Contract] = None
    ebtcToken: Optional[Contract] = None
    feeRecipient: Optional[Contract] = None
    ebtcDeployer: Optional[Contract] = None
    authority: Optional[Contract] = None
    collateral: Optional[Contract] = None


@pytest.fixture
def add_accounts():
    if network.show_active() != 'development':
        print("Importing accounts...")
        import_accounts(accounts)


@pytest.fixture
def contracts():
    contracts = Contracts()


    """
        Re uses the fixture so we deploy all via solidity
        Then fetch the addresses and be done
        No point in re-writing the same code
    """

    """
        /** @dev The order is as follows:
            0: authority
            1: liquidationLibrary
            2: cdpManager
            3: borrowerOperations
            4: priceFeed
            5; sortedCdps
            6: activePool
            7: collSurplusPool
            8: hintHelpers
            9: eBTCToken
            10: feeRecipient
            11: multiCdpGetter

            TODO TODO TODO TODO TODO TODO
            Need to add params (check: `static async deployViaCreate3(ebtcDeployer, _argTypes, _argValues, _code, _salt) {`
        */
    """

    ## -1 Deployer (NOTE: Raised gas limit)
    contracts.ebtcDeployer = EBTCDeployerTester.deploy({"from": a[0]})
    contracts.collateral = CollateralTokenTester.deploy({"from": a[0]})

    _addresses = contracts.ebtcDeployer.getFutureEbtcAddresses()

    ## TODO: START FROM
    ## // deploy Governor as Authority 
    ## TODO: For each contract, get Contract.NAME.encode_input because otherwise we can't encode it
    ## NOTE: Source for deployment: 
    ## https://github.com/Badger-Finance/ebtc/blob/ff38ed88712662785310657b6e96b8f8f3d241b7/packages/contracts/mainnetDeployment/eBTCDeployScript.js#L184

    ## 0: authority
    tx = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.AUTHORITY(),
        contracts.ebtcDeployer.authority_creationCode(),
        encode_abi(["address"], [a[0].address]),
        {"from": a[0]}
    )
    contracts.authority = AuthNoOwner.at(tx.return_value)
    assert contracts.authority.address == _addresses[0]

    ## 1: liquidationLibrary
    """
    [_addresses[3], _addresses[7], _addresses[9], _addresses[5], _addresses[6], _addresses[4], contracts.collateral.address]
    """
    contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.LIQUIDATION_LIBRARY(),
        contracts.ebtcDeployer.liquidationLibrary_creationCode(),
        encode_abi([
            'address', 
            'address', 
            'address', 
            'address', 
            'address', 
            'address', 
            'address'
            ], 
            [
                _addresses[3], _addresses[7], _addresses[9], _addresses[5], _addresses[6], _addresses[4], contracts.collateral.address
            ]),
        {"from": a[0]}
    )
    # contracts.liquidationLibrary = LiquidationLibrary.at(tx.return_value)
    # print("contracts.liquidationLibrary", contracts.liquidationLibrary)
    # assert contracts.liquidationLibrary.address == _addresses[1]
    
    # ## 2: cdpManager
    """
    _constructorArgs = [_addresses[1], _addresses[0], _addresses[3], _addresses[7], _addresses[9], _addresses[5], _addresses[6], _addresses[4], contracts.collateral.address];
    """
    contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.CDP_MANAGER(),
        contracts.ebtcDeployer.cdpManager_creationCode(),
        encode_abi(['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'],
                [_addresses[1], _addresses[0], _addresses[3], _addresses[7], _addresses[9], _addresses[5], _addresses[6], _addresses[4], contracts.collateral.address]
        ),
        {"from": a[0]}
    )

    ## 3: borrowerOperations
    """
    _constructorArgs = [_addresses[2], _addresses[6], _addresses[7], _addresses[4], _addresses[5], _addresses[9], _addresses[10], contracts.collateral.address];
    """
    contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.BORROWER_OPERATIONS(),
        contracts.ebtcDeployer.borrowerOperationsTester_creationCode(), ## NOTE: Tester
        encode_abi(
            ['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address'],
            [_addresses[2], _addresses[6], _addresses[7], _addresses[4], _addresses[5], _addresses[9], _addresses[10], contracts.collateral.address]
        ),
        {"from": a[0]}
    )

    ## NOTE: eBTC Token is deploy in script here, we deploy later

    ## 4: priceFeed
    """
    _argValues = [_addresses[0]];
    """
    contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.PRICE_FEED(),
        contracts.ebtcDeployer.priceFeedTestnet_creationCode(), ## NOTE: This is TESTNET 
        encode_abi(
            ['address'],
            [_addresses[0]]
        ),
        {"from": a[0]}
    )


    ## 5; sortedCdps
    """
    _constructorArgs = [0, _addresses[2], _addresses[3]];
    """
    contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.SORTED_CDPS(),
        contracts.ebtcDeployer.sortedCdps_creationCode(),
        encode_abi(
            ['uint256', 'address', 'address'],
            [0, _addresses[2], _addresses[3]]
        ),
        {"from": a[0]}
    )

    ## 6: activePool
    """
    _constructorArgs = [_addresses[3], _addresses[2], contracts.collateral.address, _addresses[7], _addresses[10]];
    """
    contracts.activePool = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.ACTIVE_POOL(),
        contracts.ebtcDeployer.activePool_creationCode(),
        encode_abi(
            ['address', 'address', 'address', 'address', 'address'],
            [_addresses[3], _addresses[2], contracts.collateral.address, _addresses[7], _addresses[10]]
        ),
        {"from": a[0]}
    )

    ## 7: collSurplusPool
    """
    _constructorArgs = [_addresses[3], _addresses[2], _addresses[6], contracts.collateral.address];
    """
    contracts.collSurplusPool = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.COLL_SURPLUS_POOL(),
        contracts.ebtcDeployer.collSurplusPool_creationCode(),
        encode_abi(
            ['address', 'address', 'address', 'address'],
            [_addresses[3], _addresses[2], _addresses[6], contracts.collateral.address]
        ),
        {"from": a[0]}
    )

    ## 8: hintHelpers
    """
    _constructorArgs = [_addresses[5], _addresses[2], contracts.collateral.address, _addresses[6], _addresses[4]];
    """
    contracts.hintHelpers = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.HINT_HELPERS(),
        contracts.ebtcDeployer.hintHelpers_creationCode(),
        encode_abi(
            ['address', 'address', 'address', 'address', 'address'],
            [_addresses[5], _addresses[2], contracts.collateral.address, _addresses[6], _addresses[4]]
        ),
        {"from": a[0]}
    )

    ## 9: eBTCToken
    """
    _constructorArgs = [_addresses[2], _addresses[3], _addresses[0]];
    """
    contracts.eBTCToken = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.EBTC_TOKEN(),
        contracts.ebtcDeployer.ebtcToken_creationCode(),
        encode_abi(
            ['address', 'address', 'address'],
            [_addresses[2], _addresses[3], _addresses[0]]
        ),
        {"from": a[0]}
    )

    ## 10: feeRecipient
    """
    _constructorArgs = [this.feeRecipientOwner, _addresses[1]];
    """
    contracts.feeRecipient = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.FEE_RECIPIENT(),
        contracts.ebtcDeployer.feeRecipient_creationCode(),
        encode_abi(
            ['address', 'address'],
            [a[0].address, _addresses[1]] ## TODO: Is valid?s
        ),
        {"from": a[0]}
    )

    ## 11: multiCdpGetter
    """
    _constructorArgs = [_addresses[2], _addresses[5]];
    """
    contracts.multiCdpGetter = contracts.ebtcDeployer.deployWithCreationCodeAndConstructorArgs(
        contracts.ebtcDeployer.MULTI_CDP_GETTER(),
        contracts.ebtcDeployer.multiCdpGetter_creationCode(),
        encode_abi(
            ['address', 'address'],
            [_addresses[2], _addresses[5]]
        ),
        {"from": a[0]}
    )


    """
            function getFutureEbtcAddresses() public view returns (EbtcAddresses memory) {
        EbtcAddresses memory addresses = EbtcAddresses(
            Create3.addressOf(keccak256(abi.encodePacked(AUTHORITY))), 0 
            Create3.addressOf(keccak256(abi.encodePacked(LIQUIDATION_LIBRARY))), 1
            Create3.addressOf(keccak256(abi.encodePacked(CDP_MANAGER))), 2
            Create3.addressOf(keccak256(abi.encodePacked(BORROWER_OPERATIONS))), 3
            Create3.addressOf(keccak256(abi.encodePacked(PRICE_FEED))), 4 
            Create3.addressOf(keccak256(abi.encodePacked(SORTED_CDPS))), 5
            Create3.addressOf(keccak256(abi.encodePacked(ACTIVE_POOL))), 6
            Create3.addressOf(keccak256(abi.encodePacked(COLL_SURPLUS_POOL))), 7
            Create3.addressOf(keccak256(abi.encodePacked(HINT_HELPERS))), 8 
            Create3.addressOf(keccak256(abi.encodePacked(EBTC_TOKEN))),9
            Create3.addressOf(keccak256(abi.encodePacked(FEE_RECIPIENT))), 10 
            Create3.addressOf(keccak256(abi.encodePacked(MULTI_CDP_GETTER)))11
        );

    """

    contracts.priceFeedTestnet = PriceFeedTestnet.at(_addresses[4])
    contracts.sortedCdps = SortedCdps.at(_addresses[5])
    contracts.cdpManager = CdpManager.at(_addresses[2])
    contracts.activePool = ActivePool.at(_addresses[6])
    contracts.collSurplusPool = CollSurplusPool.at(_addresses[7])
    contracts.borrowerOperations = BorrowerOperations.at(_addresses[3])
    contracts.hintHelpers = HintHelpers.at(_addresses[8])
    contracts.ebtcToken = EBTCToken.at(_addresses[9])
    contracts.feeRecipient = FeeRecipient.at(_addresses[10])
    ## TODO: Add the addresses from the factory
    ## TODO: Add some sort of test to prove they are correct

    return contracts


@pytest.fixture
def print_expectations():
    # ether_price_one_year = price_ether_initial * (1 + drift_ether)**8760
    # print("Expected ether price at the end of the year: $", ether_price_one_year)
    print("Expected LQTY price at the end of first month: $",
          price_LQTY_initial * (1 + drift_LQTY) ** 720)

    print("\n Open cdps")
    print("E(Q_t^e)    = ", collateral_gamma_k * collateral_gamma_theta)
    print("SD(Q_t^e)   = ", collateral_gamma_k ** 0.5 * collateral_gamma_theta)
    print("E(CR^*(i))  = ", (target_cr_a + target_cr_b * target_cr_chi_square_df) * 100, "%")
    print("SD(CR^*(i)) = ", target_cr_b * (2 * target_cr_chi_square_df) ** (1 / 2) * 100, "%")
    print("E(tau)      = ", rational_inattention_gamma_k * rational_inattention_gamma_theta * 100,
          "%")
    print("SD(tau)     = ",
          rational_inattention_gamma_k ** 0.5 * rational_inattention_gamma_theta * 100, "%")
    print("\n")


"""# Simulation Program
**Sequence of events**

> In each period, the following events occur sequentially


* exogenous ether price input
* cdp liquidation
* return of the previous period's stability pool determined (liquidation gain & airdropped LQTY gain
* cdp closure
* cdp adjustment
* open cdps
* issuance fee
* cdp pool formed
* EBTC supply determined
* EBTC stability pool demand determined
* EBTC liquidity pool demand determined
* EBTC price determined
* redemption & redemption fee
* LQTY pool return determined
"""


def test_run_simulation(add_accounts, contracts, print_expectations):
    contracts.priceFeedTestnet.setPrice(floatToWei(price_ether[0]), {'from': a[0]})
    # whale
    whale_coll = 30000.0
    contracts.collateral.deposit({'from': a[0], 'value': floatToWei(whale_coll)})
    balance_of_coll = contracts.collateral.balanceOf(a[0])
    contracts.collateral.approve(contracts.borrowerOperations.address, balance_of_coll, {"from": a[0]})
    ## Deposit All
    ## Borrow 10e18
    contracts.borrowerOperations.openCdp(Wei(10e18), ZERO_ADDRESS, ZERO_ADDRESS, balance_of_coll,
                                           {'from': a[0]})

    active_accounts = []
    inactive_accounts = [*range(1, len(accounts))]

    price_ebtc = 1
    price_lqty_current = price_LQTY_initial

    data = {"airdrop_gain": [0] * n_sim, "liquidation_gain": [0] * n_sim,
            "issuance_fee": [0] * n_sim, "redemption_fee": [0] * n_sim}
    total_ebtc_redempted = 0
    total_coll_added = whale_coll
    total_coll_liquidated = 0

    print(f"Accounts: {len(accounts)}")
    print(f"Network: {network.show_active()}")

    logGlobalState(contracts)
    with open(
            os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                "simulation.csv",
            ), "w+",
    ) as csvfile:
        datawriter = csv.writer(csvfile, delimiter=',')
        datawriter.writerow(
            ['iteration', 'ETH_price', 'price_EBTC', 'price_LQTY', 'num_cdps', 'total_coll',
             'total_debt', 'TCR', 'recovery_mode', 'last_ICR', 'SP_EBTC', 'SP_ETH',
             'total_coll_added', 'total_coll_liquidated', 'total_ebtc_redempted'])

        # Simulation Process
        for index in range(1, n_sim):
            print('\n  --> Iteration', index)
            print('  -------------------\n')
            # exogenous ether price input
            price_ether_current = price_ether[index]
            contracts.priceFeedTestnet.setPrice(floatToWei(price_ether_current),
                                                {'from': a[0]})

            # cdp liquidation & return of stability pool
            result_liquidation = liquidate_cdps(accounts, contracts, active_accounts,
                                                  inactive_accounts, price_ether_current,
                                                  price_ebtc, price_lqty_current, data, index)
            total_coll_liquidated = total_coll_liquidated + result_liquidation[0]
            return_stability = result_liquidation[1]

            # close cdps
            result_close = close_cdps(accounts, contracts, active_accounts, inactive_accounts,
                                        price_ether_current, price_ebtc, index)

            # adjust cdps
            [coll_added_adjust, issuance_ebtc_adjust] = adjust_cdps(accounts, contracts,
                                                                      active_accounts,
                                                                      inactive_accounts,
                                                                      price_ether_current, index)

            # open cdps
            [coll_added_open, issuance_ebtc_open] = open_cdps(accounts, contracts,
                                                                active_accounts, inactive_accounts,
                                                                price_ether_current, price_ebtc,
                                                                index)
            total_coll_added = total_coll_added + coll_added_adjust + coll_added_open
            # active_accounts.sort(key=lambda a : a.get('CR_initial'))

            # Stability Pool
            stability_update(accounts, contracts, active_accounts, return_stability, index)

            # Calculating Price, Liquidity Pool, and Redemption
            [price_ebtc, redemption_pool, redemption_fee,
             issuance_ebtc_stabilizer] = price_stabilizer(accounts, contracts, active_accounts,
                                                          inactive_accounts, price_ether_current,
                                                          price_ebtc, index)
            total_ebtc_redempted = total_ebtc_redempted + redemption_pool
            print('EBTC price', price_ebtc)
            print('LQTY price', price_lqty_current)

            issuance_fee = price_ebtc * (
                    issuance_ebtc_adjust + issuance_ebtc_open + issuance_ebtc_stabilizer)
            data['issuance_fee'][index] = issuance_fee
            data['redemption_fee'][index] = redemption_fee

            # LQTY Market
            result_lqty = lqty_market(index, data)
            price_lqty_current = result_lqty[0]
            # annualized_earning = result_LQTY[1]
            # MC_LQTY_current = result_LQTY[2]

            [eth_price, num_cdps, total_coll, total_debt, tcr, recovery_mode, last_icr, sp_ebtc,
             sp_eth] = logGlobalState(contracts)
            print('Total redempted ', total_ebtc_redempted)
            print('Total ETH added ', total_coll_added)
            print('Total ETH liquid', total_coll_liquidated)
            print(f'Ratio ETH liquid {100 * total_coll_liquidated / total_coll_added}%')
            print(' ----------------------\n')

            datawriter.writerow(
                [index, eth_price, price_ebtc, price_lqty_current, num_cdps, total_coll,
                 total_debt, tcr, recovery_mode, last_icr, sp_ebtc, sp_eth, total_coll_added,
                 total_coll_liquidated, total_ebtc_redempted])

            assert price_ebtc > 0
