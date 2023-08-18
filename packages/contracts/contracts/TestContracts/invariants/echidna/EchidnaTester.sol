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
// rm -f fuzzTests/corpus/* # (optional)
// echidna contracts/TestContracts/invariants/echidna/EchidnaTester.sol --test-mode property --contract EchidnaTester --config fuzzTests/echidna_config.yaml
contract EchidnaTester is
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
    }

    function _setUpActors() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        address[] memory callers = new address[](2);
        callers[0] = address(borrowerOperations);
        callers[1] = address(activePool);
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            actors[addresses[i]] = new Actor(tokens, callers);
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

    function _totalCdpsBelowMcr() internal returns (uint256) {
        uint256 ans;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedTestnet.getPrice();

        while (currentCdp != bytes32(0)) {
            if (cdpManager.getCurrentICR(currentCdp, _price) < cdpManager.MCR()) {
                ++ans;
            }

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        return ans;
    }

    function _getCdpIdsAndICRs() internal returns (Cdp[] memory ans) {
        ans = new Cdp[](sortedCdps.getSize());
        uint256 i = 0;
        bytes32 currentCdp = sortedCdps.getFirst();

        uint256 _price = priceFeedTestnet.getPrice();

        while (currentCdp != bytes32(0)) {
            ans[i++] = Cdp({id: currentCdp, icr: cdpManager.getCurrentICR(currentCdp, _price)});

            currentCdp = sortedCdps.getNext(currentCdp);
        }
    }

    function _cdpIdsAndICRsDiff(
        Cdp[] memory superset,
        Cdp[] memory subset
    ) internal returns (Cdp[] memory ans) {
        ans = new Cdp[](superset.length - subset.length);
        uint256 index = 0;
        for (uint256 i = 0; i < superset.length; i++) {
            bool duplicate;
            for (uint256 j = 0; j < subset.length; j++) {
                if (superset[i].id == subset[j].id) {
                    duplicate = true;
                }
            }
            if (!duplicate) {
                ans[index++] = superset[i];
            }
        }
    }

    function _getRandomCdp(uint _i) internal view returns (bytes32) {
        uint _cdpIdx = _i % cdpManager.getCdpIdsCount();
        return cdpManager.CdpIds(_cdpIdx);
    }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    function liquidate(uint _i) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        uint256 _price = priceFeedTestnet.getPrice();

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidate.selector, _cdpId)
        );

        _after(_cdpId);

        if (success) {
            if (vars.icrBefore < cdpManager.LICR()) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertWithMsg(vars.tcrAfter > vars.tcrBefore, L_12);
            }
            assertWithMsg(
                vars.icrBefore < cdpManager.MCR() ||
                    (vars.icrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
                L_01
            );
        } else if (vars.sortedCdpsSizeBefore > _i) {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function partialLiquidate(uint _i, uint _partialAmount) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        bytes32 _cdpId = _getRandomCdp(_i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(entireDebt > 0, "CDP must have debt");

        _partialAmount = clampBetween(_partialAmount, 0, entireDebt - 1);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(
                CdpManager.partiallyLiquidate.selector,
                _cdpId,
                _partialAmount,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            (uint256 _newEntireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            assertLt(_newEntireDebt, entireDebt, "Partial liquidation must reduce CDP debt");

            if (vars.icrBefore < cdpManager.LICR()) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertWithMsg(vars.tcrAfter > vars.tcrBefore, L_12);
            }
            assertWithMsg(
                vars.icrBefore < cdpManager.MCR() ||
                    (vars.icrBefore < cdpManager.CCR() && vars.isRecoveryModeBefore),
                L_01
            );

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function liquidateCdps(uint _n) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot liquidate last CDP");

        _n = clampBetween(_n, 1, cdpManager.getCdpIdsCount());

        uint256 totalCdpsBelowMcr = _totalCdpsBelowMcr();
        uint256 _price = priceFeedTestnet.getPrice();
        Cdp[] memory cdpsBefore = _getCdpIdsAndICRs();

        _before(bytes32(0));

        (success, returnData) = actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidateCdps.selector, _n)
        );

        _after(bytes32(0));

        if (success) {
            Cdp[] memory cdpsAfter = _getCdpIdsAndICRs();

            Cdp[] memory cdpsLiquidated = _cdpIdsAndICRsDiff(cdpsBefore, cdpsAfter);
            assertGte(
                cdpsLiquidated.length,
                1,
                "liquidateCdps must liquidate at least 1 CDP when successful"
            );
            assertLte(
                cdpsLiquidated.length,
                _n,
                "liquidateCdps must not liquidate more than n CDPs"
            );
            uint256 minIcrBefore = type(uint256).max;
            for (uint256 i = 0; i < cdpsLiquidated.length; ++i) {
                assertWithMsg(
                    cdpsLiquidated[i].icr < cdpManager.MCR() ||
                        (cdpsLiquidated[i].icr < cdpManager.CCR() && vars.isRecoveryModeBefore),
                    L_01
                );
                if (cdpsLiquidated[i].icr < minIcrBefore) {
                    minIcrBefore = cdpsLiquidated[i].icr;
                }
            }

            if (minIcrBefore < cdpManager.LICR()) {
                // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/5
                assertWithMsg(vars.tcrAfter > vars.tcrBefore, L_12);
            }
        } else if (vars.sortedCdpsSizeBefore > _n) {
            bool atLeastOneCdpIsLiquidatable = false;
            for (uint256 i = 0; i < cdpsBefore.length; ++i) {
                if (
                    cdpsBefore[i].icr < cdpManager.MCR() ||
                    (cdpsBefore[i].icr < cdpManager.CCR() && vars.isRecoveryModeBefore)
                ) {
                    atLeastOneCdpIsLiquidatable = true;
                    break;
                }
            }
            if (atLeastOneCdpIsLiquidatable) {
                assertRevertReasonNotEqual(returnData, "Panic(17)");
            }
        }
    }

    function redeemCollateral(
        uint _EBTCAmount,
        uint _partialRedemptionHintNICR,
        uint _maxFeePercentage
    ) external log {
        require(
            block.timestamp > cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD(),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );

        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _EBTCAmount = clampBetween(_EBTCAmount, 0, eBTCToken.balanceOf(address(actor)));

        _maxFeePercentage = clampBetween(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        _before(bytes32(0));

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
                _maxFeePercentage
            )
        );

        _after(bytes32(0));

        if (success) {
            assertWithMsg(!vars.isRecoveryModeBefore, EBTC_02);
            assertWithMsg(invariant_CDPM_04(vars), CDPM_04);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function flashLoanColl(uint _amount) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));
        uint _fee = activePool.flashFee(address(collateral), _amount);

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        (success, returnData) = actor.proxy(
            address(activePool),
            abi.encodeWithSelector(
                ActivePool.flashLoan.selector,
                IERC3156FlashBorrower(address(actor)),
                address(collateral),
                _amount,
                // NOTE: this is a dummy flash loan, it is not doing anything inside the `onFlashLoan` callback. It can be improved to pass an arbitrary calldata to be sent back to the system
                abi.encodePacked("")
            )
        );

        if (success) {
            uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
            assertEq(_balAfter - _balBefore, _fee, "Flashloan should send fee to recipient");
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    ///////////////////////////////////////////////////////
    // BorrowerOperations
    ///////////////////////////////////////////////////////

    function flashLoanEBTC(uint _amount) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.flashLoan.selector,
                IERC3156FlashBorrower(address(actor)),
                address(eBTCToken),
                _amount,
                // NOTE: this is a dummy flash loan, it is not doing anything inside the `onFlashLoan` callback. It can be improved to pass an arbitrary calldata to be sent back to the system
                abi.encodePacked("")
            )
        );

        if (success) {
            uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
            assertEq(_balAfter - _balBefore, _fee, "Flashloan should send fee to recipient");
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedTestnet.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_COLL() + borrowerOperations.LIQUIDATOR_REWARD(),
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

        _before(bytes32(0));

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

        _after(bytes32(0));

        assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
        if (success) {
            bytes32 _cdpId = abi.decode(returnData, (bytes32));

            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
            assertEq(
                vars.sortedCdpsSizeBefore + 1,
                vars.sortedCdpsSizeAfter,
                "CDPs count must have increased"
            );
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function addColl(uint _coll, uint256 _i) external log {
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
                (_coll - collateral.balanceOf(address(actor)))
            );
            assertGte(
                collateral.balanceOf(address(actor)),
                _coll,
                "Actor has high enough balance to add"
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
            assertWithMsg(
                vars.nicrAfter > vars.nicrBefore || collateral.getEthPerShare() != 1e18,
                BO_03
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);

            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
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

        // Can only withdraw up to CDP collateral amount, otherwise will revert with assert
        _amount = clampBetween(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );

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
            assertLt(vars.nicrAfter, vars.nicrBefore, BO_04);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);
            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
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
        // Can only withdraw up to type(uint128).max eBTC, so that `BorrwerOperations._getNewCdpAmounts` does not overflow
        _amount = clampBetween(_amount, 0, type(uint128).max);

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
            assertGte(vars.debtAfter, vars.debtBefore, "withdrawEBTC must not decrease debt");
            assertEq(
                vars.actorEbtcAfter,
                vars.actorEbtcBefore + _amount,
                "withdrawEBTC must increase debt by requested amount"
            );
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function repayEBTC(uint _amount, uint256 _i) external log {
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
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(
            //     vars.tcrAfter > vars.tcrBefore ||
            //         diffPercent(vars.tcrAfter, vars.tcrBefore) < 0.01e18,
            //     BO_08
            // );

            assertEq(vars.ebtcTotalSupplyBefore - _amount, vars.ebtcTotalSupplyAfter, BO_07);
            assertEq(vars.actorEbtcBefore - _amount, vars.actorEbtcAfter, BO_07);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);
            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function closeCdp(uint _i) external log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        require(cdpManager.getCdpIdsCount() > 1, "Cannot close last CDP");

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
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);
            emit L4(
                vars.actorCollBefore,
                vars.cdpCollBefore,
                vars.liquidatorRewardSharesBefore,
                vars.actorCollAfter
            );
            assertWithMsg(
                // not exact due to rounding errors
                isApproximateEq(
                    vars.actorCollBefore + vars.cdpCollBefore + vars.liquidatorRewardSharesBefore,
                    vars.actorCollAfter,
                    0.01e18
                ),
                BO_05
            );
            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease
    ) internal log {
        actor = actors[msg.sender];

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        assertWithMsg(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _collWithdrawal = clampBetween(_collWithdrawal, 0, entireColl);
        _EBTCChange = clampBetween(_EBTCChange, 0, entireDebt);

        _before(_cdpId);

        (success, returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.adjustCdp.selector,
                _cdpId,
                _collWithdrawal,
                _EBTCChange,
                _isDebtIncrease,
                _cdpId,
                _cdpId
            )
        );

        _after(_cdpId);

        if (success) {
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/3
            // assertWithMsg(invariant_GENERAL_09(cdpManager, priceFeedTestnet, _cdpId), GENERAL_09);

            assertWithMsg(invariant_GENERAL_01(vars), GENERAL_01);
            // https://github.com/Badger-Finance/ebtc-fuzz-review/issues/4
            // assertGte(cdpManager.getCdpColl(_cdpId), borrowerOperations.MIN_NET_COLL(), GENERAL_10);
        } else {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
        }
    }

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function setEthPerShare(uint256 _newEthPerShare) internal {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1e18
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
            (currentPrice * 1e18) / MAX_PRICE_CHANGE_PERCENT,
            (currentPrice * MAX_PRICE_CHANGE_PERCENT) / 1e18
        );
        priceFeedTestnet.setPrice(_newPrice);
    }
}
