// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/PropertiesHelper.sol";

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

// Run with:
// cd <your-path-to-ebtc-repo-root>/packages/contracts
// rm -f ./fuzzTests/corpus/* # (optional)
// <your-path-to->/echidna-test contracts/TestContracts/invariants/echidna/EchidnaTester.sol --test-mode property --contract EchidnaTester --config fuzzTests/echidna_config.yaml --crytic-args "--solc <your-path-to-solc0817>" --solc-args "--base-path <your-path-to-ebtc-repo-root>/packages/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts --include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Dependencies -include-path <your-path-to-ebtc-repo-root>/packages/contracts/contracts/Interfaces"
contract EchidnaTester is EchidnaBaseTester, EchidnaProperties, PropertiesAsserts {
    constructor() payable {
        _setUp();
        _setUpActors();
        _connectCoreContracts();
        _connectLQTYContractsToCore();
    }

    /* basic function to call when setting up new echidna test
    Use in pair with connectCoreContracts to wire up infrastructure
    */
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
        // TODO why 100 actors instead of echidna's default of 3?
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            actors[i] = new Actor(eBTCToken, borrowerOperations, activePool);
            (bool success, ) = address(actors[i]).call{value: INITIAL_BALANCE}("");
            assert(success);
            actors[i].proxy(
                address(collateral),
                abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
                INITIAL_COLL_BALANCE
            );
        }
    }

    /* connectCoreContracts() - wiring up deployed contracts and setting up infrastructure
     */
    function _connectCoreContracts() internal {
        // TODO why is this necessary?
        IHevm(hevm).warp(block.timestamp + 86400);
    }

    /* connectLQTYContractsToCore() - connect LQTY contracts to core contracts
     */
    function _connectLQTYContractsToCore() internal {
        // TODO can this be removed?
    }

    ///////////////////////////////////////////////////////
    // Helper functions
    ///////////////////////////////////////////////////////

    function _ensureMCR(bytes32 _cdpId, CDPChange memory _change) internal view {
        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
        uint _debt = entireDebt + _change.debtAddition - _change.debtReduction;
        uint _coll = entireColl + _change.collAddition - _change.collReduction;
        require((_debt * MCR) / price < _coll, "!CDP_MCR");
    }

    function _getRandomActor(uint _i) internal pure returns (uint) {
        return _i % NUMBER_OF_ACTORS;
    }

    function _getRandomCdp(uint _i) internal view returns (bytes32) {
        uint _cdpIdx = _i % cdpManager.getCdpIdsCount();
        return cdpManager.CdpIds(_cdpIdx);
    }

    function _getNewPriceForLiquidation(
        uint _i
    ) internal view returns (uint _oldPrice, uint _newPrice) {
        uint _priceDiv = _i % 10;
        _oldPrice = priceFeedTestnet.getPrice();
        _newPrice = _oldPrice / (_priceDiv + 1);
    }

    // helper functions
    function _ensureNoLiquidationTriggered(bytes32 _cdpId) internal view {
        uint _price = priceFeedTestnet.getPrice();
        if (_price > 0) {
            bool _recovery = cdpManager.checkRecoveryMode(_price);
            uint _icr = cdpManager.getCurrentICR(_cdpId, _price);
            if (_recovery) {
                require(_icr > cdpManager.getTCR(_price), "liquidationTriggeredInRecoveryMode");
            } else {
                require(_icr > cdpManager.MCR(), "liquidationTriggeredInNormalMode");
            }
        }
    }

    function _ensureNoRecoveryModeTriggered() internal view {
        uint _price = priceFeedTestnet.getPrice();
        if (_price > 0) {
            require(!cdpManager.checkRecoveryMode(_price), "!recoveryModeTriggered");
        }
    }

    function _ensureMinCollInCdp(bytes32 _cdpId) internal view {
        uint _collWorth = collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId));
        require(_collWorth < cdpManager.MIN_NET_COLL(), "!minimum CDP collateral");
    }

    ///////////////////////////////////////////////////////
    // CdpManager
    ///////////////////////////////////////////////////////

    function liquidateExt(uint _i) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = _getRandomCdp(_i);

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        uint _icr = cdpManager.getCurrentICR(_cdpId, _newPrice);
        bool _recovery = cdpManager.checkRecoveryMode(_newPrice);

        if (_icr < cdpManager.MCR() || (_recovery && _icr < cdpManager.getTCR(_newPrice))) {
            (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            actor.proxy(
                address(cdpManager),
                abi.encodeWithSelector(CdpManager.liquidate.selector, _cdpId)
            );
            require(!sortedCdps.contains(_cdpId), "!ClosedByLiquidation");
        }

        priceFeedTestnet.setPrice(_oldPrice);
    }

    function partialLiquidateExt(uint _i, uint _partialAmount) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = _getRandomCdp(_i);

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        uint _icr = cdpManager.getCurrentICR(_cdpId, _newPrice);
        bool _recovery = cdpManager.checkRecoveryMode(_newPrice);

        if (_icr < cdpManager.MCR() || (_recovery && _icr < cdpManager.getTCR(_newPrice))) {
            (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            require(_partialAmount < entireDebt, "!_partialAmount");
            actor.proxy(
                address(cdpManager),
                abi.encodeWithSelector(
                    CdpManager.partiallyLiquidate.selector,
                    _cdpId,
                    _partialAmount,
                    _cdpId,
                    _cdpId
                )
            );
            (uint256 _newEntireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
            require(_newEntireDebt < entireDebt, "!reducedByPartialLiquidation");
        }

        priceFeedTestnet.setPrice(_oldPrice);
    }

    function liquidateCdpsExt(uint _i, uint _n) external {
        Actor actor = actors[_getRandomActor(_i)];

        (uint _oldPrice, uint _newPrice) = _getNewPriceForLiquidation(_i);
        priceFeedTestnet.setPrice(_newPrice);

        if (_n > cdpManager.getCdpIdsCount()) {
            _n = cdpManager.getCdpIdsCount();
        }

        actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(CdpManager.liquidateCdps.selector, _n)
        );

        priceFeedTestnet.setPrice(_oldPrice);
    }

    function redeemCollateralExt(
        // TODO optimize the input space
        uint _i,
        uint _EBTCAmount,
        bytes32 _firstRedemptionHint,
        bytes32 _upperPartialRedemptionHint,
        bytes32 _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    ) external {
        Actor actor = actors[_getRandomActor(_i)];
        actor.proxy(
            address(cdpManager),
            abi.encodeWithSelector(
                CdpManager.redeemCollateral.selector,
                _EBTCAmount,
                _firstRedemptionHint,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR,
                0,
                0
            )
        );
    }

    function claimSplitFee() external {
        cdpManager.claimStakingSplitFee();
    }

    ///////////////////////////////////////////////////////
    // ActivePool
    ///////////////////////////////////////////////////////

    function flashloanCollExt(uint _i, uint _amount) public {
        Actor actor = actors[_getRandomActor(_i)];
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

    function flashloanEBTCExt(uint _i, uint _amount) public {
        Actor actor = actors[_getRandomActor(_i)];
        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        // sugardaddy fee
        uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);
        actor.proxy(
            address(eBTCToken),
            abi.encodeWithSelector(EBTCTokenTester.unprotectedMint.selector, _fee)
        );

        // take the flashloan which should always cost the fee paid by caller
        uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        (bool success, ) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.flashLoan.selector,
                IERC3156FlashBorrower(address(this)),
                address(eBTCToken),
                _amount,
                abi.encodePacked(uint256(0))
            )
        );
        uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        if (success) {
            assert(_balAfter - _balBefore == _fee);

            // TODO remove?
            actor.proxy(
                address(eBTCToken),
                abi.encodeWithSelector(
                    EBTCTokenTester.unprotectedBurn.selector,
                    borrowerOperations.feeRecipientAddress(),
                    _fee
                )
            );
        }
    }

    function openCdpWithCollExt(uint _i, uint _coll, uint _EBTCAmount) public {
        Actor actor = actors[_getRandomActor(_i)];

        // we pass in CCR instead of MCR in case it’s the first one
        uint price = priceFeedTestnet.getPrice();
        require(price > 0);
        require((_EBTCAmount * MCR) / price < _coll);

        uint requiredCollAmount = (_EBTCAmount * CCR) / (price);
        requiredCollAmount = clampBetween(_coll, requiredCollAmount, 2 * requiredCollAmount);

        uint actorBalance = collateral.balanceOf(address(actor));
        if (actorBalance < requiredCollAmount) {
            actor.proxy(
                address(collateral),
                abi.encodeWithSelector(
                    CollateralTokenTester.deposit.selector,
                    "",
                    requiredCollAmount - actorBalance
                )
            );
        }
        (bool success, bytes memory returnData) = actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.openCdp.selector,
                _EBTCAmount,
                bytes32(0),
                bytes32(0)
            )
        );
        if(success) {
            bytes32 _cdpId = abi.decode(returnData, (bytes32));
            _ensureNoLiquidationTriggered(_cdpId);
            _ensureNoRecoveryModeTriggered();
            _ensureMinCollInCdp(_cdpId);

            numberOfCdps = cdpManager.getCdpIdsCount();
            assert(numberOfCdps > 0);
        }
    }

    function addCollExt(uint _i, uint _coll) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        uint actorBalance = collateral.balanceOf(address(actor));

        if (actorBalance < _coll) {
            actor.proxy(
                address(collateral),
                abi.encodeWithSelector(
                    CollateralTokenTester.deposit.selector,
                    "",
                    _coll - actorBalance
                )
            );
        }

        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.addColl.selector,
                _cdpId,
                _coll,
                _cdpId,
                _cdpId
            )
        );
    }

    function withdrawCollExt(uint _i, uint _amount) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, _amount, 0, 0);
        _ensureMCR(_cdpId, _change);

        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawColl.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );
        _ensureNoLiquidationTriggered(_cdpId);
        _ensureNoRecoveryModeTriggered();
    }

    function withdrawEBTCExt(uint _i, uint _amount) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        CDPChange memory _change = CDPChange(0, 0, _amount, 0);
        _ensureMCR(_cdpId, _change);

        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.withdrawEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );
        _ensureNoLiquidationTriggered(_cdpId);
        _ensureNoRecoveryModeTriggered();
    }

    function repayEBTCExt(uint _i, uint _amount) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _amount = clampBetween(_amount, 1, entireDebt);
        uint _price = priceFeedTestnet.fetchPrice();
        uint _tcrBefore = cdpManager.getTCR(_price);
        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.repayEBTC.selector,
                _cdpId,
                _amount,
                _cdpId,
                _cdpId
            )
        );
        uint _tcrAfter = cdpManager.getTCR(_price);
        assert(_tcrAfter > _tcrBefore);
    }

    function closeCdpExt(uint _i) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");
        require(1 == cdpManager.getCdpStatus(_cdpId), "!closeCdpExtActive");
        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, _cdpId)
        );
    }

    function adjustCdpExt(
        uint _i,
        uint _collWithdrawal,
        uint _debtChange,
        bool _isDebtIncrease
    ) external {
        Actor actor = actors[_getRandomActor(_i)];
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), 0);
        require(_cdpId != bytes32(0), "!cdpId");

        (uint256 entireDebt, uint256 entireColl, ) = cdpManager.getEntireDebtAndColl(_cdpId);
        require(_collWithdrawal < entireColl, "!adjustCdpExt_collWithdrawal");

        uint price = priceFeedTestnet.getPrice();
        require(price > 0);

        uint debtChange = _debtChange;
        CDPChange memory _change;
        if (_isDebtIncrease) {
            _change = CDPChange(0, _collWithdrawal, _debtChange, 0);
        } else {
            // TODO can I change entire debt? remove -1
            _debtChange = clampBetween(_debtChange, 0, entireDebt - 1);
            _change = CDPChange(0, _collWithdrawal, 0, _debtChange);
        }
        _ensureMCR(_cdpId, _change);
        actor.proxy(
            address(borrowerOperations),
            abi.encodeWithSelector(
                BorrowerOperations.adjustCdp.selector,
                _cdpId,
                _cdpId,
                _collWithdrawal,
                debtChange,
                _isDebtIncrease,
                _cdpId,
                _cdpId
            )
        );
        if (_collWithdrawal > 0 || _isDebtIncrease) {
            _ensureNoLiquidationTriggered(_cdpId);
            _ensureNoRecoveryModeTriggered();
        }
    }

    ///////////////////////////////////////////////////////
    // EBTC Token
    ///////////////////////////////////////////////////////

    // TODO evaluate if recipient should be any or should be one of actors
    function approveAndTransfer(uint _i, address recipient, uint256 amount) external returns (bool) {
        Actor actor = actors[_getRandomActor(_i)];
        actor.proxy(
            address(eBTCToken),
            abi.encodeWithSelector(EBTCToken.approve.selector, recipient, amount)
        );
        actor.proxy(
            address(eBTCToken),
            abi.encodeWithSelector(EBTCToken.transfer.selector, recipient, amount)
        );
    }

    ///////////////////////////////////////////////////////
    // Collateral Token (Test)
    ///////////////////////////////////////////////////////

    function increaseCollateralRate(uint _newBiggerIndex) external {
        _newBiggerIndex = clampBetween(
            _newBiggerIndex,
            collateral.getPooledEthByShares(1e18),
            min(10_000 * 1e18, collateral.getPooledEthByShares(1e18) * 10_000)
        );
        collateral.setEthPerShare(_newBiggerIndex);
    }

    // Example for real world slashing: https://twitter.com/LidoFinance/status/1646505631678107649
    // > There are 11 slashing ongoing with the RockLogic GmbH node operator in Lido.
    // > the total projected impact is around 20 ETH,
    // > or about 3% of average daily protocol rewards/0.0004% of TVL.
    function decreaseCollateralRate(uint _newSmallerIndex) external {
        _newSmallerIndex = clampBetween(
            _newSmallerIndex,
            max(collateral.getPooledEthByShares(1e18) / 10000, 1),
            collateral.getPooledEthByShares(1e18)
        );
        collateral.setEthPerShare(_newSmallerIndex);
    }
}
