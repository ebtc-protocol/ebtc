// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";
import {WETH9} from "../contracts/TestContracts/WETH9.sol";
import {BorrowerOperations} from "../contracts/BorrowerOperations.sol";
import {PriceFeedTestnet} from "../contracts/TestContracts/testnet/PriceFeedTestnet.sol";
import {SortedCdps} from "../contracts/SortedCdps.sol";
import {CdpManager} from "../contracts/CdpManager.sol";
import {LiquidationLibrary} from "../contracts/LiquidationLibrary.sol";
import {ActivePool} from "../contracts/ActivePool.sol";
import {HintHelpers} from "../contracts/HintHelpers.sol";
import {FeeRecipient} from "../contracts/FeeRecipient.sol";
import {EBTCToken} from "../contracts/EBTCToken.sol";
import {CollSurplusPool} from "../contracts/CollSurplusPool.sol";
import {FunctionCaller} from "../contracts/TestContracts/FunctionCaller.sol";
import {CollateralTokenTester} from "../contracts/TestContracts/CollateralTokenTester.sol";
import {Governor} from "../contracts/Governor.sol";
import {EBTCDeployer} from "../contracts/EBTCDeployer.sol";
import {Utilities} from "./utils/Utilities.sol";
import {BytecodeReader} from "./utils/BytecodeReader.sol";

contract EBTCDeployerTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint256 public mintAmount = 1e18;

    string public constant TEST_SALT_STRING = "salty";
    string public constant TEST_SALT_STRING_2 = "salty2";

    function setUp() public override {
        eBTCBaseFixture.setUp();
        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    function atest_NonDeployerCannotDeploy() public {
        address user = _utils.getNextUserAddress();

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        ebtcDeployer.deploy(TEST_SALT_STRING, type(Governor).creationCode);
    }

    function atest_DeployIndividualContract() public {
        vm.startPrank(defaultGovernance);
        address expected = ebtcDeployer.addressOf(TEST_SALT_STRING);
        address deployed = ebtcDeployer.deploy(TEST_SALT_STRING, type(Governor).creationCode);

        // We should have deployed to the expected address
        assertEq(deployed, expected);
        vm.stopPrank();
    }

    function test_DeployMultipleContracts() public {
        vm.startPrank(defaultGovernance);

        address deployed;

        // -- Governor --
        address expectedDeployed = ebtcDeployer.addressOf(TEST_SALT_STRING);
        deployed = ebtcDeployer.deploy(
            TEST_SALT_STRING,
            abi.encodePacked(type(Governor).creationCode, abi.encode(defaultGovernance))
        );

        // Ensure at expected addresses
        assertEq(deployed, expectedDeployed);
        assertGt(deployed.code.length, 0);

        // Assert constructor fields initialized as expected
        Governor testAuthority = Governor(deployed);
        assertEq(testAuthority.owner(), defaultGovernance);
        assertEq(address(testAuthority.authority()), deployed);

        // -- LiquidationLibrary --
        expectedDeployed = ebtcDeployer.addressOf(TEST_SALT_STRING_2);
        deployed = ebtcDeployer.deploy(
            TEST_SALT_STRING_2,
            abi.encodePacked(
                type(LiquidationLibrary).creationCode,
                abi.encode(
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0),
                    address(0)
                )
            )
        );

        assertEq(deployed, expectedDeployed);
        assertGt(deployed.code.length, 0);

        LiquidationLibrary testLiquidationLibrary = LiquidationLibrary(deployed);
        assertEq(testLiquidationLibrary.liquidationLibrary(), address(0));

        vm.stopPrank();
    }

    function _printAddresses(address[] memory addresses) internal view {
        for (uint256 i = 0; i < addresses.length; i++) {
            console.log("address %s: %s", i, addresses[i]);
        }
    }
}
