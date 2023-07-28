// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

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
import {IERC3156FlashLender} from "../contracts/Interfaces/IERC3156FlashLender.sol";

import {Utilities} from "../foundry_test/utils/Utilities.sol";
import {BytecodeReader} from "../foundry_test/utils/BytecodeReader.sol";

contract MyScript is Script {

    EBTCDeployer ebtcDeployer = EBTCDeployer(0x42c4adf565981dCD2FC24BEA0e46098836Ea0F26);



    function setUp(address gov) internal {
        EBTCDeployer.EbtcAddresses memory addr = ebtcDeployer.getFutureEbtcAddresses();
        
        console2.log("authorityAddress", addr.authorityAddress);
        console2.log("liquidationLibraryAddress", addr.liquidationLibraryAddress);
        console2.log("cdpManagerAddress", addr.cdpManagerAddress);
        console2.log("borrowerOperationsAddress", addr.borrowerOperationsAddress);
        console2.log("priceFeedAddress", addr.priceFeedAddress);
        console2.log("sortedCdpsAddress", addr.sortedCdpsAddress);
        console2.log("activePoolAddress", addr.activePoolAddress);
        console2.log("collSurplusPoolAddress", addr.collSurplusPoolAddress);
        console2.log("hintHelpersAddress", addr.hintHelpersAddress);
        console2.log("ebtcTokenAddress", addr.ebtcTokenAddress);
        console2.log("feeRecipientAddress", addr.feeRecipientAddress);
        console2.log("multiCdpGetterAddress", addr.multiCdpGetterAddress);

        // SIZES
        console2.log("authorityAddress", addr.authorityAddress.code.length);
        console2.log("liquidationLibraryAddress", addr.liquidationLibraryAddress.code.length);
        console2.log("cdpManagerAddress", addr.cdpManagerAddress.code.length);
        console2.log("borrowerOperationsAddress", addr.borrowerOperationsAddress.code.length);
        console2.log("priceFeedAddress", addr.priceFeedAddress.code.length);
        console2.log("sortedCdpsAddress", addr.sortedCdpsAddress.code.length);
        console2.log("activePoolAddress", addr.activePoolAddress.code.length);
        console2.log("collSurplusPoolAddress", addr.collSurplusPoolAddress.code.length);
        console2.log("hintHelpersAddress", addr.hintHelpersAddress.code.length);
        console2.log("ebtcTokenAddress", addr.ebtcTokenAddress.code.length);
        console2.log("feeRecipientAddress", addr.feeRecipientAddress.code.length);
        console2.log("multiCdpGetterAddress", addr.multiCdpGetterAddress.code.length);
    }

    function run() external {
      // TODO: Proper: 0xA3e81EBdf5ebdc0787B2c594A735a0Bfb69Bbf72
      // TODO: Proper: a37df416a6c9686092a5e1d087d7e994f71e7d2a1eb183831260cc4d11ad4f3f
        uint256 deployerPrivateKey = 0xa37df416a6c9686092a5e1d087d7e994f71e7d2a1eb183831260cc4d11ad4f3f;
        vm.startBroadcast(deployerPrivateKey);

        setUp(0xA3e81EBdf5ebdc0787B2c594A735a0Bfb69Bbf72);

        vm.stopBroadcast();
    }
}
