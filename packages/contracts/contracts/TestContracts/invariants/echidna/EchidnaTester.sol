// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesConstants.sol";

import "../../../Interfaces/ICdpManagerData.sol";
import "../../../Dependencies/SafeMath.sol";
import "../../../CdpManager.sol";
import "../../../LiquidationLibrary.sol";
import "../../../BorrowerOperations.sol";
import "../../../ActivePool.sol";
import "../../../CollSurplusPool.sol";
import "../../../SortedCdps.sol";
import "../../../HintHelpers.sol";
import "../../../FeeRecipient.sol";
import "../../testnet/PriceFeedTestnet.sol";
import "../../CollateralTokenTester.sol";
import "../../EBTCTokenTester.sol";
import "../../../Governor.sol";
import "../../../EBTCDeployer.sol";

import "../IHevm.sol";
import "../Properties.sol";
import "../Actor.sol";
import "./EchidnaBaseTester.sol";
import "./EchidnaProperties.sol";
import "./EchidnaBeforeAfter.sol";
import "./EchidnaAssertionHelper.sol";

// Run with:
// cd <your-path-to-ebtc-repo-root>/packages/contracts
// rm -f ./fuzzTests/corpus/* # (optional)
// <your-path-to->/echidna-test contracts/TestContracts/invariants/echidna/EchidnaTester.sol --test-mode property --contract EchidnaTester --config fuzzTests/echidna_config.yaml --crytic-args "--solc <your-path-to-solc0817>" --solc-args "--base-path <your-path-to-ebtc-repo-root>/packages/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Dependencies -include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Interfaces"
contract EchidnaTester is
    EchidnaBaseTester,
    EchidnaBeforeAfter,
    EchidnaProperties,
    EchidnaAssertionHelper,
    PropertiesConstants
{
    constructor() payable {
        _setUp();
        _setUpActors();
    }

    function _setUp() internal {
        defaultGovernance = msg.sender;
        ebtcDeployer = new EBTCDeployer();

        // Default governance is deployer
        // vm.prank(defaultGovernance);
        collateral = new CollateralTokenTester();

        EBTCDeployer.EbtcAddresses memory addr = ebtcDeployer.getFutureEbtcAddresses();

        {
            bytes memory creationCode;
            bytes memory args;

            // Use EBTCDeployer to deploy all contracts at determistic addresses

            // Authority
            creationCode = type(Governor).creationCode;
            args = abi.encode(address(this));

            authority = Governor(
                ebtcDeployer.deploy(ebtcDeployer.AUTHORITY(), abi.encodePacked(creationCode, args))
            );

            // Liquidation Library
            creationCode = type(LiquidationLibrary).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.collSurplusPoolAddress,
                addr.ebtcTokenAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.priceFeedAddress,
                address(collateral)
            );

            liqudationLibrary = LiquidationLibrary(
                ebtcDeployer.deploy(
                    ebtcDeployer.LIQUIDATION_LIBRARY(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // CDP Manager
            creationCode = type(CdpManager).creationCode;
            args = abi.encode(
                addr.liquidationLibraryAddress,
                addr.authorityAddress,
                addr.borrowerOperationsAddress,
                addr.collSurplusPoolAddress,
                addr.ebtcTokenAddress,
                addr.sortedCdpsAddress,
                addr.activePoolAddress,
                addr.priceFeedAddress,
                address(collateral)
            );

            cdpManager = CdpManager(
                ebtcDeployer.deploy(ebtcDeployer.CDP_MANAGER(), abi.encodePacked(creationCode, args))
            );

            // Borrower Operations
            creationCode = type(BorrowerOperations).creationCode;
            args = abi.encode(
                addr.cdpManagerAddress,
                addr.activePoolAddress,
                addr.collSurplusPoolAddress,
                addr.priceFeedAddress,
                addr.sortedCdpsAddress,
                addr.ebtcTokenAddress,
                addr.feeRecipientAddress,
                address(collateral)
            );

            borrowerOperations = BorrowerOperations(
                ebtcDeployer.deploy(
                    ebtcDeployer.BORROWER_OPERATIONS(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Price Feed Mock
            creationCode = type(PriceFeedTestnet).creationCode;
            args = abi.encode(addr.authorityAddress);

            priceFeedTestnet = PriceFeedTestnet(
                ebtcDeployer.deploy(ebtcDeployer.PRICE_FEED(), abi.encodePacked(creationCode, args))
            );

            // Sorted CDPS
            creationCode = type(SortedCdps).creationCode;
            args = abi.encode(
                type(uint256).max,
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress
            );

            sortedCdps = SortedCdps(
                ebtcDeployer.deploy(ebtcDeployer.SORTED_CDPS(), abi.encodePacked(creationCode, args))
            );

            // Active Pool
            creationCode = type(ActivePool).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.cdpManagerAddress,
                address(collateral),
                addr.collSurplusPoolAddress,
                addr.feeRecipientAddress
            );

            activePool = ActivePool(
                ebtcDeployer.deploy(ebtcDeployer.ACTIVE_POOL(), abi.encodePacked(creationCode, args))
            );

            // Coll Surplus Pool
            creationCode = type(CollSurplusPool).creationCode;
            args = abi.encode(
                addr.borrowerOperationsAddress,
                addr.cdpManagerAddress,
                addr.activePoolAddress,
                address(collateral)
            );

            collSurplusPool = CollSurplusPool(
                ebtcDeployer.deploy(
                    ebtcDeployer.COLL_SURPLUS_POOL(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Hint Helpers
            creationCode = type(HintHelpers).creationCode;
            args = abi.encode(
                addr.sortedCdpsAddress,
                addr.cdpManagerAddress,
                address(collateral),
                addr.activePoolAddress,
                addr.priceFeedAddress
            );

            hintHelpers = HintHelpers(
                ebtcDeployer.deploy(
                    ebtcDeployer.HINT_HELPERS(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // eBTC Token
            creationCode = type(EBTCTokenTester).creationCode;
            args = abi.encode(
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress,
                addr.authorityAddress
            );

            eBTCToken = EBTCTokenTester(
                ebtcDeployer.deploy(ebtcDeployer.EBTC_TOKEN(), abi.encodePacked(creationCode, args))
            );

            // Fee Recipieint
            creationCode = type(FeeRecipient).creationCode;
            args = abi.encode(
                addr.ebtcTokenAddress,
                addr.cdpManagerAddress,
                addr.borrowerOperationsAddress,
                addr.activePoolAddress,
                address(collateral)
            );

            feeRecipient = FeeRecipient(
                ebtcDeployer.deploy(
                    ebtcDeployer.FEE_RECIPIENT(),
                    abi.encodePacked(creationCode, args)
                )
            );

            // Configure authority
            authority.setRoleName(0, "Admin");
            authority.setRoleName(1, "eBTCToken: mint");
            authority.setRoleName(2, "eBTCToken: burn");
            authority.setRoleName(3, "CDPManager: all");
            authority.setRoleName(4, "PriceFeed: setTellorCaller");
            authority.setRoleName(5, "BorrowerOperations: setFlashFee & setMaxFlashFee");

            authority.setRoleCapability(1, address(eBTCToken), MINT_SIG, true);

            authority.setRoleCapability(2, address(eBTCToken), BURN_SIG, true);

            authority.setRoleCapability(3, address(cdpManager), SET_STAKING_REWARD_SPLIT_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_REDEMPTION_FEE_FLOOR_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_MINUTE_DECAY_FACTOR_SIG, true);
            authority.setRoleCapability(3, address(cdpManager), SET_BASE_SIG, true);

            authority.setRoleCapability(4, address(priceFeedTestnet), SET_TELLOR_CALLER_SIG, true);

            authority.setRoleCapability(5, address(borrowerOperations), SET_FLASH_FEE_SIG, true);
            authority.setRoleCapability(5, address(borrowerOperations), SET_MAX_FLASH_FEE_SIG, true);

            authority.setRoleCapability(5, address(activePool), SET_FLASH_FEE_SIG, true);
            authority.setRoleCapability(5, address(activePool), SET_MAX_FLASH_FEE_SIG, true);

            authority.setUserRole(defaultGovernance, 0, true);
            authority.setUserRole(defaultGovernance, 1, true);
            authority.setUserRole(defaultGovernance, 2, true);
            authority.setUserRole(defaultGovernance, 3, true);
            authority.setUserRole(defaultGovernance, 4, true);
            authority.setUserRole(defaultGovernance, 5, true);

            authority.transferOwnership(defaultGovernance);
        }

        MCR = cdpManager.MCR();
        CCR = cdpManager.CCR();
        LICR = cdpManager.LICR();
        MIN_NET_COLL = cdpManager.MIN_NET_COLL();
        assert(MCR > 0);
        assert(CCR > 0);
        assert(LICR > 0);
        assert(MIN_NET_COLL > 0);
    }

    function _setUpActors() internal {
        bool success;
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            actors[addresses[i]] = new Actor(eBTCToken, borrowerOperations, activePool);
            (success, ) = address(actors[addresses[i]]).call{value: INITIAL_ETH_BALANCE}("");
            assert(success);
            (success, ) = actors[addresses[i]].proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                INITIAL_COLL_BALANCE
            );
            assert(success);
        }
    }

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

    // function _ensureMCR(bytes32 _cdpId, CDPChange memory _change) internal view {
    //     uint price = priceFeedTestnet.getPrice();
    //     (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
    //     uint _debt = entireDebt + _change.debtAddition - _change.debtReduction;
    //     uint _coll = entireColl + _change.collAddition - _change.collReduction;
    //     require((_debt * MCR) / price < _coll, "!CDP_MCR");
    // }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    // function liquidate(uint _i) external {
    //     actor = actors[msg.sender];

    //     bool success;
    //     bytes memory returnData;

    //     uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
    //     require(numberOfCdps > 0, "Actor must have at least one CDP open");

    //     _i = clampBetween(_i, 0, numberOfCdps - 1);
    //     bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
    //     assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

    //     uint256 _price = priceFeedTestnet.getPrice();

    //     uint _icr = cdpManager.getCurrentICR(_cdpId, _price);
    //     bool _recovery = cdpManager.checkRecoveryMode(_price);

    //     (success, returnData) =    actor.proxy(
    //             address(cdpManager),
    //             abi.encodeWithSelector(CdpManager.liquidate.selector, _cdpId)
    //         );
    // }

    // function partialLiquidate(uint _i, uint _partialAmount) internal {
    //     actor = actors[msg.sender];
    //     bytes32 _cdpId = _getRandomCdp(_i);

    //     (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
    //     priceFeedTestnet.setPrice(_newPrice);

    //     uint _icr = cdpManager.getCurrentICR(_cdpId, _newPrice);
    //     bool _recovery = cdpManager.checkRecoveryMode(_newPrice);

    //     if (_icr < cdpManager.MCR() || (_recovery && _icr < cdpManager.getTCR(_newPrice))) {
    //         (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
    //         require(_partialAmount < entireDebt, "!_partialAmount");
    //         actor.proxy(
    //             address(cdpManager),
    //             abi.encodeWithSelector(
    //                 CdpManager.partiallyLiquidate.selector,
    //                 _cdpId,
    //                 _partialAmount,
    //                 _cdpId,
    //                 _cdpId
    //             )
    //         );
    //         (uint256 _newEntireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
    //         require(_newEntireDebt < entireDebt, "!reducedByPartialLiquidation");
    //     }

    //     priceFeedTestnet.setPrice(_oldPrice);
    // }

    function liquidateCdps(uint _n) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _n = clampBetween(_n, 1, cdpManager.getCdpIdsCount());

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidateCdps.selector, _n)
        );

        if (success) {
            assertRevertReasonEqual(returnData, "TODO1");
        } else {
            assertRevertReasonEqual(returnData, "TODO2");
        }
    }

    function redeemCollateral(uint _EBTCAmount, uint _partialRedemptionHintNICR) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(
                CdpManager.redeemCollateral.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0),
                bytes32(0),
                _partialRedemptionHintNICR,
                0,
                0
            )
        );

        if (success) {
            assertRevertReasonEqual(returnData, "TODO1");
        } else {
            assertRevertReasonEqual(returnData, "TODO2");
        }
    }

    // function claimStakingSplitFee() internal {
    //     // TODO do before/after active pool fees
    //     cdpManager.claimStakingSplitFee();
    // }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function flashloanColl(uint _amount) internal {
        actor = actors[msg.sender];

        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));

        // sugardaddy fee
        uint _fee = activePool.flashFee(address(collateral), _amount);
        require(_fee < address(actor).balance, "!tooMuchFeeCollFL");

        actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, "", _fee)
        );

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());

        actor.proxy(
            address(activePool),
            abi.encodeWithSelector(
                ActivePool.flashLoan.selector,
                IERC3156FlashBorrower(address(actor)),
                address(collateral),
                _amount,
                abi.encodePacked(uint256(0))
            )
        );

        uint _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        assert(_balAfter - _balBefore == _fee);
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    // function flashloanEBTC(uint _amount) internal {
    //     actor = actors[msg.sender];

    //     _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

    //     // sugardaddy fee
    //     uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);
    //     actor.proxy(
    //         address(eBTCToken),
    //         abi.encodeWithSelector(EBTCTokenTester.unprotectedMint.selector, _fee)
    //     );

    //     // take the flashloan which should always cost the fee paid by caller
    //     uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
    //     (bool success, ) = actor.proxy(
    //         address(borrowerOperations),
    //         abi.encodeWithSelector(
    //             BorrowerOperations.flashLoan.selector,
    //             IERC3156FlashBorrower(address(this)),
    //             address(eBTCToken),
    //             _amount,
    //             abi.encodePacked(uint256(0))
    //         )
    //     );
    //     uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
    //     if (success) {
    //         assert(_balAfter - _balBefore == _fee);

    //         // TODO remove?
    //         actor.proxy(
    //             address(eBTCToken),
    //             abi.encodeWithSelector(
    //                 EBTCTokenTester.unprotectedBurn.selector,
    //                 borrowerOperations.feeRecipientAddress(),
    //                 _fee
    //             )
    //         );
    //     }
    // }

    function openCdp(uint256 _col, uint256 _EBTCAmount) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedTestnet.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * CCR) / (price);
        uint256 minCollAmount = max(
            MIN_NET_COLL + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
        _col = clampBetween(requiredCollAmount, minCollAmount, maxCollAmount);

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _col
            )
        );
        assertWithMsg(success, "Approve never fails");
        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.openCdp.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0),
                _col
            )
        );
        if (success) {
            bytes32 _cdpId = abi.decode(returnData, (bytes32));

            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
            uint _collWorth = collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId));
            assertGte(_collWorth, MIN_NET_COLL, "CDP collateral must be above minimum");
            assertWithMsg(cdpManager.getCdpIdsCount() > 0, "CDPs count must have increased");
        } else {
            if (_EBTCAmount == 0) {
                assertRevertReasonEqual(returnData, "BorrowerOps: Debt must be non-zero");
            } else if (collateral.balanceOf(address(actor)) < _col) {
                assertRevertReasonEqual(
                    returnData,
                    "ERC20: transfer amount exceeds balance"
                    // Actor must have collateral to open CDP
                );
            } else {
                assertRevertReasonEqual(
                    returnData,
                    "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
                    // Actor must have collateral to open CDP
                );
            }
        }
    }

    function addColl(uint _coll, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _coll = clampBetween(_coll, 0, INITIAL_COLL_BALANCE / 10);

        if (collateral.balanceOf(address(actor)) < _coll) {
            (success, ) = actor.proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                collateral.getPooledEthByShares(_coll - collateral.balanceOf(address(actor)))
            );
            assertWithMsg(success, "deposit never fails as EchidnaTester has high enough balance");
        }

        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(borrowerOperations),
                _coll
            )
        );
        assertWithMsg(success, "Approve never fails");

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.addColl.selector,
                _cdpId,
                _cdpId,
                _cdpId,
                _coll
            )
        );

        _after(_cdpId);

        if (success) {
            // TODO add more invariants here
            assertWithMsg(
                vars.nicrAfter > vars.nicrBefore ||
                    diffPercent(vars.nicrAfter, vars.nicrBefore) < 0.01e18,
                "P-49 Adding collateral improves Nominal ICR"
            );
            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
        } else {
            assertEq(_coll, 0, "Cannot addColl 0");
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: There must be either a collateral change or a debt change"
                // "Cannot addColl 0"
            );
        }
    }

    function withdrawColl(uint _amount, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        CDPChange memory _change = CDPChange(0, _amount, 0, 0);

        // Can only withdraw up to CDP collateral amount, otherwise will revert with assert
        _amount = clampBetween(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );
        // _ensureMCR(_cdpId, _change);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawColl.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            // TODO add more invariants here
            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
            assertLt(
                vars.nicrAfter,
                vars.nicrBefore,
                "P-50 Removing collateral decreases the Nominal ICR"
            );
        } else {
            if (_amount == 0) {
                assertRevertReasonEqual(
                    returnData,
                    "BorrowerOps: There must be either a collateral change or a debt change"
                );
            } else {
                assertRevertReasonEqual(
                    returnData,
                    "BorrowerOps: Cdp's net coll must be greater than minimum",
                    "BorrowerOps: An operation that would result in ICR < MCR is not permitted",
                    "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
                );
            }
        }
    }

    function withdrawEBTC(uint _amount, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        // TODO verify the assumption below, maybe there's a more sensible (or Governance-defined/hardcoded) limit for the maximum amount of minted eBTC at a single operation
        // Can only withdraw up to type(uint128).max eBTC, so that `BorrwerOperations._getNewCdpAmounts` does not overflows
        _amount = clampBetween(_amount, 0, type(uint128).max);

        CDPChange memory _change = CDPChange(0, 0, _amount, 0);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            // TODO add more invariants
            assertEq(vars.debtAfter, vars.debtBefore + _amount, "withdrawEBTC increases debt");
            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
            assertGt(vars.nicrBefore, vars.nicrAfter, "withdrawEBTC decreases Nominal ICR");
        } else if (_amount == 0) {
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: Debt increase requires non-zero debtChange"
            );
        } else if (vars.cdpStatusBefore != 1) {
            assertRevertReasonEqual(returnData, "BorrowerOps: Cdp does not exist or is closed");
        } else if (
            collateral.getPooledEthByShares(vars.cdpCollBefore) < borrowerOperations.MIN_NET_COLL()
        ) {
            // This may happen after a rebase, if before the CDP has coll greater than min now it may not be anymore
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: Cdp's net coll must be greater than minimum"
            );
        } else {
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: An operation that would result in ICR < MCR is not permitted",
                "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
            );
        }
    }

    function repayEBTC(uint _amount, uint256 _i) external {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.repayEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            assertWithMsg(
                vars.tcrAfter > vars.tcrBefore ||
                    diffPercent(vars.tcrAfter, vars.tcrBefore) < 0.01e18,
                "TCR must increase after a repayment"
            );

            assertEq(
                vars.ebtcTotalSupplyAfter,
                vars.ebtcTotalSupplyBefore - _amount,
                "P-05: eBTC tokens are burned upon repayment of a CDP's debt"
            );

            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
        } else if (_amount == 0) {
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: There must be either a collateral change or a debt change"
                // "Cannot repayBTC 0"
            );
        } else if (vars.debtBefore - _amount == 0) {
            assertRevertReasonEqual(returnData, "BorrowerOps: Debt must be non-zero");
        } else {
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: Cdp's net coll must be greater than minimum"
            );
        }
    }

    function closeCdp(uint _i) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            // TODO add more invariants
            assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
            assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
            assertEq(
                vars.sortedCdpsSizeBefore - 1,
                vars.sortedCdpsSizeAfter,
                "closeCdp reduces list size by 1"
            );
            assertGt(
                vars.actorCollAfter,
                vars.actorCollBefore,
                "closeCdp increases the collateral balance of the user"
            );
            assertEq(
                vars.actorCollBefore + vars.cdpCollBefore + vars.liquidatorRewardSharesBefore,
                vars.actorCollAfter,
                "closeCdp gives collateral and liquidator rewards back to user"
            );
        } else if (vars.sortedCdpsSizeBefore == 1) {
            // TODO check also for overflow reverts
            assertRevertReasonEqual(returnData, "CdpManager: Only one cdp in the system");
        } else {
            assertRevertReasonEqual(
                returnData,
                "BorrowerOps: Cdp does not exist or is closed",
                "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
            );
        }
    }

    // function adjustCdp(uint _collWithdrawal, uint _debtChange, bool _isDebtIncrease) internal {
    //     actor = actors[msg.sender];
    //     bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
    //     require(_cdpId != bytes32(0), "!cdpId");

    //     (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
    //     require(_collWithdrawal < entireColl, "!adjustCdpExt_collWithdrawal");

    //     uint price = priceFeedTestnet.getPrice();

    //     uint debtChange = _debtChange;
    //     CDPChange memory _change;
    //     if (_isDebtIncrease) {
    //         _change = CDPChange(0, _collWithdrawal, _debtChange, 0);
    //     } else {
    //         // TODO can I change entire debt? remove -1
    //         _debtChange = clampBetween(_debtChange, 0, entireDebt - 1);
    //         _change = CDPChange(0, _collWithdrawal, 0, _debtChange);
    //     }
    //     // _ensureMCR(_cdpId, _change);
    //     actor.proxy(
    //         address(borrowerOperations),
    //         abi.encodeWithSelector(
    //             BorrowerOperations.adjustCdp.selector,
    //             _cdpId,
    //             _cdpId,
    //             _collWithdrawal,
    //             debtChange,
    //             _isDebtIncrease,
    //             _cdpId,
    //             _cdpId
    //         )
    //     );
    //     if (_collWithdrawal > 0 || _isDebtIncrease) {
    //         assertWithMsg(invariant_P_03(cdpManager, priceFeedTestnet), "P-03");
    //         assertWithMsg(invariant_P_50(cdpManager, priceFeedTestnet, _cdpId), "P-50");
    //     }
    // }

    ///////////////////////////////////////////////////////
    // EBTC Token
    ///////////////////////////////////////////////////////

    // TODO evaluate if recipient should be any or should be one of actors
    // function approveAndTransfer(address recipient, uint256 amount) internal returns (bool) {
    //     actor = actors[msg.sender];

    //     actor.proxy(
    //         address(eBTCToken),
    //         abi.encodeWithSelector(EBTCToken.approve.selector, recipient, amount)
    //     );
    //     actor.proxy(
    //         address(eBTCToken),
    //         abi.encodeWithSelector(EBTCToken.transfer.selector, recipient, amount)
    //     );
    // }

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function setEthPerShare(uint256 _newEthPerShare) external {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1 ether) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1 ether
        );
        collateral.setEthPerShare(_newEthPerShare);
    }

    ///////////////////////////////////////////////////////
    // PriceFeed
    ///////////////////////////////////////////////////////

    function setPrice(uint256 _newPrice) external {
        uint256 currentPrice = priceFeedTestnet.getPrice();
        _newPrice = clampBetween(
            _newPrice,
            (currentPrice * 1 ether) / MAX_PRICE_CHANGE_PERCENT,
            (currentPrice * MAX_PRICE_CHANGE_PERCENT) / 1 ether
        );
        priceFeedTestnet.setPrice(_newPrice);
    }
}
