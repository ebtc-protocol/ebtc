// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Properties} from "../contracts/TestContracts/invariants/Properties.sol";
import {IERC20} from "../contracts/Dependencies/IERC20.sol";
import {IERC3156FlashBorrower} from "../contracts/Interfaces/IERC3156FlashBorrower.sol";
import {TargetFunctions} from "../contracts/TestContracts/invariants/TargetFunctions.sol";
import {TargetContractSetup} from "../contracts/TestContracts/invariants/TargetContractSetup.sol";
import {HalmosAsserts} from "./utils/HalmosAsserts.sol";

contract Halmos is Test, TargetContractSetup, HalmosAsserts, TargetFunctions, IERC3156FlashBorrower {
    modifier setup() override {
        _;
    }

    function setUp() public {
        _setUp();
        _setUpActors();
        actor = actors[USER1];
        vm.startPrank(address(actor));
    }

    function check_BO_01() public {
        openCdp(0, 1);
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
