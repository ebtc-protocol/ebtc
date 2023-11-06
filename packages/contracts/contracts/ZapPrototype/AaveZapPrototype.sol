// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ZapPrototype } from "./ZapPrototype.sol";
import { IAaveFlashLender, IAaveFlashLoanReceiver } from "./IAaveFlashLender.sol";
import { Deployments } from "./Deployments.sol";

contract AaveZapPrototype is ZapPrototype, IAaveFlashLoanReceiver {

    constructor(DeploymentParams memory params) 
        ZapPrototype(params) {
    }

    function flashLoan(ZapInParams calldata params) internal override {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        assets[0] = Deployments.wstETH;

        // TODO: determine the amount to flash borrow
        // maybe collAmount - margin?
        amounts[0] = params.cdp.collAmount;

        IAaveFlashLender(FLASH_LENDER).flashLoan(
            address(this),
            assets,
            amounts,
            new uint256[](1), // modes
            address(this),
            abi.encode(params),
            0
        );            
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // TODO: unwrap wstETH to ETH

        super.handleFlashLoan(params);
        return true;
    }
}
