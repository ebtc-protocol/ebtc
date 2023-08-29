// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {IERC3156FlashBorrower} from "../contracts/Interfaces/IERC3156FlashBorrower.sol";

/*
 * Test suite that converts from echidna "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract EchidnaToFoundry is eBTCBaseFixture, Properties, IERC3156FlashBorrower {
    address user;
    address actor;
    uint internal constant INITIAL_COLL_BALANCE = 1e21;
    uint256 private constant MAX_FLASHLOAN_ACTIONS = 4;

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
        user = address(this);
        actor = user;
        vm.startPrank(address(this));
        vm.deal(user, INITIAL_COLL_BALANCE);
        collateral.deposit{value: INITIAL_COLL_BALANCE}();

        IERC20(collateral).approve(address(activePool), type(uint256).max);
        IERC20(eBTCToken).approve(address(borrowerOperations), type(uint256).max);
    }

    function testGetGasRefund() public {
        // TODO convert to foundry test
        setEthPerShare(166472971329298343907410417081817146937181310074112353288);
        openCdp(0, 1);
        addColl(120719409312262194023192469707599498, 169959741405433799125898596825763);
        openCdp(0, 1);
        closeCdp(0);
    }

    function testGetEquity() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        openCdp(0, 6017477493556148);
        openCdp(
            116241465726706579940676160693764388857475194631576631540259024322658,
            1817137256320022
        );
        redeemCollateral(
            26614308365956830740674967552436143289186716835450083370339261669379702,
            1384110347060895451294098103757437540301390035862529508464766486079565,
            4111505908023053120587254978547282594806873281945684814578972428283812304
        );
    }

    function testGetFlashFee() public {
        openCdp(0, 2);
        setEthPerShare(0);

        flashLoanColl(216);
    }

    function testBO05() public {
        openCdp(0, 1);
        setEthPerShare(0);
        addColl(89746347972992101541, 29594050145240);
        openCdp(0, 1);
        uint256 balanceBefore = collateral.balanceOf(address(this));
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(this), 0);
        uint256 cdpCollBefore = cdpManager.getCdpColl(_cdpId);
        uint256 liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        console2.log("before %s", balanceBefore);
        closeCdp(0);
        uint256 balanceAfter = collateral.balanceOf(address(this));
        console2.log("after %s %s %s %s", balanceAfter, cdpCollBefore, liquidatorRewardSharesBefore);
        console2.log(
            "isApproximateEq? %s",
            isApproximateEq(
                balanceBefore +
                    collateral.getPooledEthByShares(cdpCollBefore + liquidatorRewardSharesBefore),
                balanceAfter,
                0.0e18
            )
        );
    }

    function testBrokenCdpm4() public {
        openCdp(72141099106195067837191398095614470036586507560146867, 3841);
        openCdp(138711028362710431195438633179531745921712852901503794761514, 22613);
        setEthPerShare(24422684974255655458766413850138378431721);
        vm.warp(block.timestamp + 348292 + 390247 + 396978 + 14374);

        cdpManager.applyPendingGlobalState(); // Accrue change in stETH Value

        uint256 valueBefore = _getValue();
        console.log("valueBefore", valueBefore);
        redeemCollateral(
            5693805027259487391817279795949662737234119713540967169331,
            5442622424533550139791733199345932418401974502572419280832,
            32829286642066383138421349005089843612094010323700170406627
        );
        uint256 valueAfter = _getValue();
        console.log("valueAfter", valueAfter);
        assertLe(valueBefore, valueAfter, "value cahnge");
    }

    //
    function _getValue() internal returns (uint256) {
        uint256 currentPrice = priceFeedMock.getPrice();

        uint256 totalColl = cdpManager.getEntireSystemColl();
        uint256 totalDebt = cdpManager.getEntireSystemDebt();
        uint256 totalCollFeeRecipient = activePool.getFeeRecipientClaimableColl();

        uint256 surplusColl = collSurplusPool.getStEthColl();

        uint256 totalValue = ((totalCollFeeRecipient * currentPrice) / 1e18) +
            ((totalColl * currentPrice) / 1e18) +
            ((surplusColl * currentPrice) / 1e18) -
            totalDebt;
        return totalValue;
    }

    function testDebugLiquidateZero() public {
        openCdp(0, 1);
        openCdp(
            89987264111579281160927512855035343800112805104904539378532907880159583883,
            1106532110377617551
        );
        setEthPerShare(0);
        setEthPerShare(0);
        setEthPerShare(0);
        uint256 _price = priceFeedMock.getPrice();
        uint256 tcrBefore = cdpManager.getTCR(_price);
        uint256 feeRecipientBalanceBefore = collateral.balanceOf(activePool.feeRecipientAddress()) +
            activePool.getFeeRecipientClaimableColl();
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), 0);
        // cdpManager.applyPendingGlobalState();

        liquidateCdps(0);
        uint256 tcrAfter = cdpManager.getTCR(_price);
        uint256 feeRecipientBalanceAfter = collateral.balanceOf(activePool.feeRecipientAddress()) +
            activePool.getFeeRecipientClaimableColl();
        console.log("\ttcr %s %s %s", tcrBefore, tcrAfter, cdpManager.getCurrentICR(_cdpId, _price));
        console.log("\tfee %s %s", feeRecipientBalanceBefore, feeRecipientBalanceAfter);
        console.log("\tLICR", cdpManager.LICR(), collateral.getSharesByPooledEth(cdpManager.LICR()));
        // assertGt(tcrAfter, tcrBefore, L_12);
    }

    function testCloseCdpGasCompensationBrokenDueToFeeSplit() public {
        bytes32 _cdpId = openCdp(0, 1);
        addColl(
            1136306260966836966416254910600741013785759825099592986674110980406214,
            547292987167112192731837925341417026323903943248170797463056655103524
        );
        setEthPerShare(254118524);
        addColl(
            12597227859793617205474425017915022562745818181943317312554948512,
            9719570706362477321866756827913315445905565055267406059909916475
        );
        setEthPerShare(427559125359927817315385493025244950085348258422237142673507024064172809185);
        openCdp(3571529399317342246939748969305228181926514889773271968455159558869, 9858);
        setEthPerShare(3643538871032775039067393294322983338235379072440222187277243527);
        vars.actorCollBefore = collateral.balanceOf(actor);
        vars.cdpCollBefore = cdpManager.getCdpColl(_cdpId);
        vars.liquidatorRewardSharesBefore = cdpManager.getCdpLiquidatorRewardShares(_cdpId);
        closeCdp(0);
        vars.actorCollAfter = collateral.balanceOf(actor);
        console.log(
            "\tcloseCdpGasCompensation",
            vars.actorCollBefore,
            vars.actorCollAfter,
            vars.actorCollAfter - vars.actorCollBefore
        );
        console.log(
            "\tcloseCdpGasCompensation",
            vars.cdpCollBefore,
            vars.liquidatorRewardSharesBefore,
            vars.cdpCollBefore + vars.liquidatorRewardSharesBefore
        );

        // assertTrue(
        //     isApproximateEq(
        //         vars.actorCollBefore +
        //             // ActivePool transfer SHARES not ETH directly
        //             collateral.getPooledEthByShares(
        //                 vars.cdpCollBefore + vars.liquidatorRewardSharesBefore
        //             ),
        //         vars.actorCollAfter,
        //         0.01e18
        //     ),
        //     BO_05
        // );
    }

    function testFlashLoanEBTC() public {
        openCdp(31907386653083806466320315455248167275022035374271615, 2);
        flashLoanEBTC(20542751032848327136066959552045638727049657135270774054943898826);
    }

    function testTcrMustIncreaseAfterRepayment() public {
        openCdp(13981380896748761892053706028661380888937876551972584966356379645, 23);
        setEthPerShare(55516200804822679866310029419499170992281118179349982013988952907);
        repayEBTC(1, 509846657665200610349434642309205663062);
    }

    function testTCRShouldNotDecreaseAfterRedemptions() public {
        vm.warp(block.timestamp + cdpManager.BOOTSTRAP_PERIOD());
        openCdp(0, 1);
        setPrice(1322581084004256081677);
        openCdp(1157, 129247021399144974);
        setPrice(0);
        redeemCollateral(
            55272814824723720282644178,
            451485902797602866794737611631,
            2499559204056333929
        );
    }

    function clampBetween(uint256 value, uint256 low, uint256 high) internal returns (uint256) {
        if (value < low || value > high) {
            uint ans = low + (value % (high - low + 1));
            return ans;
        }
        return value;
    }

    function setEthPerShare(uint256 _newEthPerShare) internal {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / 1.1e18,
            (currentEthPerShare * 1.1e18) / 1e18
        );

        console2.log("setEthPerShare", _newEthPerShare);
        collateral.setEthPerShare(_newEthPerShare);
    }

    function setPrice(uint256 _newPrice) internal {
        uint256 currentPrice = priceFeedMock.getPrice();
        _newPrice = clampBetween(
            _newPrice,
            (currentPrice * 1e18) / 1.1e18,
            (currentPrice * 1.1e18) / 1e18
        );

        console2.log("setPrice", _newPrice);
        priceFeedMock.setPrice(_newPrice);
    }

    function openCdp(uint256 _col, uint256 _EBTCAmount) internal returns (bytes32) {
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_EBTCAmount * CCR) / (price);
        uint256 minCollAmount = max(
            borrowerOperations.MIN_NET_COLL() + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, 1e20);
        _col = clampBetween(requiredCollAmount, minCollAmount, maxCollAmount);
        collateral.approve(address(borrowerOperations), _col);

        console2.log("openCdp", _col, _EBTCAmount);
        return borrowerOperations.openCdp(_EBTCAmount, bytes32(0), bytes32(0), _col);
    }

    function closeCdp(uint _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(user));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), _i);

        console2.log("closeCdp", _i);
        borrowerOperations.closeCdp(_cdpId);
    }

    function addColl(uint _coll, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _coll = clampBetween(_coll, 0, 1e20);
        collateral.approve(address(borrowerOperations), _coll);

        console2.log("addColl", _coll, _i);
        borrowerOperations.addColl(_cdpId, _cdpId, _cdpId, _coll);
    }

    function withdrawEBTC(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _amount = clampBetween(_amount, 0, type(uint128).max);

        console2.log("withdrawEBTC", _amount, _i);
        borrowerOperations.withdrawEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function withdrawColl(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        _amount = clampBetween(
            _amount,
            0,
            collateral.getPooledEthByShares(cdpManager.getCdpColl(_cdpId))
        );

        console2.log("withdrawColl", _amount, _i);
        borrowerOperations.withdrawColl(_cdpId, _amount, _cdpId, _cdpId);
    }

    function repayEBTC(uint _amount, uint256 _i) internal {
        uint256 numberOfCdps = sortedCdps.cdpCountOf(user);

        _i = clampBetween(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(user, _i);

        (uint256 entireDebt, , ) = cdpManager.getEntireDebtAndColl(_cdpId);
        _amount = clampBetween(_amount, 0, entireDebt);

        console2.log("repayEBTC", _amount, _i);
        borrowerOperations.repayEBTC(_cdpId, _amount, _cdpId, _cdpId);
    }

    function redeemCollateral(
        uint _EBTCAmount,
        uint _partialRedemptionHintNICR,
        uint _maxFeePercentage
    ) internal {
        require(
            block.timestamp > cdpManager.getDeploymentStartTime() + cdpManager.BOOTSTRAP_PERIOD(),
            "CdpManager: Redemptions are not allowed during bootstrap phase"
        );

        _EBTCAmount = clampBetween(_EBTCAmount, 0, eBTCToken.balanceOf(address(user)));

        _maxFeePercentage = clampBetween(
            _maxFeePercentage,
            cdpManager.redemptionFeeFloor(),
            cdpManager.DECIMAL_PRECISION()
        );

        console2.log("redeemCollateral", _EBTCAmount, _partialRedemptionHintNICR, _maxFeePercentage);
        cdpManager.redeemCollateral(
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            _partialRedemptionHintNICR,
            1,
            _maxFeePercentage
        );
    }

    function liquidateCdps(uint _n) internal {
        _n = clampBetween(_n, 1, cdpManager.getCdpIdsCount());

        console2.log("liquidateCdps", _n);
        cdpManager.liquidateCdps(_n);
    }

    function flashLoanColl(uint _amount) internal {
        _amount = clampBetween(_amount, 0, activePool.maxFlashLoan(address(collateral)));

        console2.log("flashLoanColl", _amount);

        uint _balBefore = collateral.balanceOf(activePool.feeRecipientAddress());
        uint _fee = activePool.flashFee(address(collateral), _amount);
        activePool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(collateral),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint _balAfter = collateral.balanceOf(activePool.feeRecipientAddress());
        console.log("\tbalances", _balBefore, _balAfter);
        console.log("\tfee", _fee);
    }

    function flashLoanEBTC(uint _amount) internal {
        _amount = clampBetween(_amount, 0, borrowerOperations.maxFlashLoan(address(eBTCToken)));

        console2.log("flashLoanEBTC", _amount);

        uint _balBefore = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        uint _fee = borrowerOperations.flashFee(address(eBTCToken), _amount);
        borrowerOperations.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(eBTCToken),
            _amount,
            _getFlashLoanActions(_amount)
        );
        uint _balAfter = eBTCToken.balanceOf(borrowerOperations.feeRecipientAddress());
        console.log("\tbalances", _balBefore, _balAfter);
        console.log("\tfee", _fee);
    }

    function _getFlashLoanActions(uint256 value) internal returns (bytes memory) {
        uint256 _actions = clampBetween(value, 1, MAX_FLASHLOAN_ACTIONS);
        uint256 _EBTCAmount = clampBetween(value, 1, eBTCToken.totalSupply() / 2);
        uint256 _col = clampBetween(value, 1, cdpManager.getEntireSystemColl() / 2);
        uint256 _n = clampBetween(value, 1, cdpManager.getCdpIdsCount());

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(user));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");
        uint256 _i = clampBetween(value, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(user), _i);
        assert(_cdpId != bytes32(0));

        address[] memory _targets = new address[](_actions);
        bytes[] memory _calldatas = new bytes[](_actions);

        address[] memory _allTargets = new address[](7);
        bytes[] memory _allCalldatas = new bytes[](7);

        _allTargets[0] = address(borrowerOperations);
        _allCalldatas[0] = abi.encodeWithSelector(
            borrowerOperations.openCdp.selector,
            _EBTCAmount,
            bytes32(0),
            bytes32(0),
            _col
        );

        _allTargets[1] = address(borrowerOperations);
        _allCalldatas[1] = abi.encodeWithSelector(borrowerOperations.closeCdp.selector, _cdpId);

        _allTargets[2] = address(borrowerOperations);
        _allCalldatas[2] = abi.encodeWithSelector(
            borrowerOperations.addColl.selector,
            _cdpId,
            _cdpId,
            _cdpId,
            _col
        );

        _allTargets[3] = address(borrowerOperations);
        _allCalldatas[3] = abi.encodeWithSelector(
            borrowerOperations.withdrawColl.selector,
            _cdpId,
            _col,
            _cdpId,
            _cdpId
        );

        _allTargets[4] = address(borrowerOperations);
        _allCalldatas[4] = abi.encodeWithSelector(
            borrowerOperations.withdrawEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[5] = address(borrowerOperations);
        _allCalldatas[5] = abi.encodeWithSelector(
            borrowerOperations.repayEBTC.selector,
            _cdpId,
            _EBTCAmount,
            _cdpId,
            _cdpId
        );

        _allTargets[6] = address(cdpManager);
        _allCalldatas[6] = abi.encodeWithSelector(cdpManager.liquidateCdps.selector, _n);

        for (uint256 _j = 0; _j < _actions; ++_j) {
            _i = uint256(keccak256(abi.encodePacked(value, _j, _i))) % _allTargets.length;
            console2.log("\taction", _i);

            _targets[_j] = _allTargets[_i];
            _calldatas[_j] = _allCalldatas[_i];
        }

        return abi.encode(_targets, _calldatas);
    }

    // callback for flashloan
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        if (data.length != 0) {
            (address[] memory _targets, bytes[] memory _calldatas) = abi.decode(
                data,
                (address[], bytes[])
            );
            for (uint256 i = 0; i < _targets.length; ++i) {
                (bool success, bytes memory returnData) = address(_targets[i]).call(_calldatas[i]);
                require(success, _getRevertMsg(returnData));
            }
        }

        IERC20(token).approve(msg.sender, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
