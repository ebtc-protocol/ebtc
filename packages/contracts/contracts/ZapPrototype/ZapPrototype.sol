// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IPositionManagers } from "../Interfaces/IPositionManagers.sol";
import { IBorrowerOperations } from "../Interfaces/IBorrowerOperations.sol";
import { IERC20 } from "../Dependencies/IERC20.sol";
import { Deployments } from "./Deployments.sol";

abstract contract ZapPrototype {
    address immutable internal FLASH_LENDER;
    IBorrowerOperations immutable internal BORROWER_OPERATIONS;

    struct DeploymentParams {
        address flashLender;
        address borrowerOperations;
    }

    constructor(DeploymentParams memory params) {
        // Make sure we are using the correct Deployments lib
        uint256 chainId;
        assembly { chainId := chainid() }
        require(Deployments.CHAIN_ID == chainId);

        FLASH_LENDER = params.flashLender;
        BORROWER_OPERATIONS = IBorrowerOperations(params.borrowerOperations);
    }

    struct PmPermit {
        address borrower;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;       
    }

    struct CdpParams {
        uint256 borrowAmount;
        uint256 collAmount;
        bytes32 upperHint;
        bytes32 lowerHint;
    }

    struct ZapInParams {
        CdpParams cdp;
        PmPermit permit;
    }

    function zapInEth() external payable {
        // TODO: submit ETH to Lido and receive stETH
    }

    function zapIn(ZapInParams calldata params) external {
        flashLoan(params);
    }

    function flashLoan(ZapInParams calldata params) internal virtual;

    function handleFlashLoan(bytes calldata params) internal {
        require(msg.sender == FLASH_LENDER);

        ZapInParams memory zapInParams = abi.decode(params, (ZapInParams));

        IPositionManagers(address(BORROWER_OPERATIONS)).permitPositionManagerApproval(
            zapInParams.permit.borrower,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            zapInParams.permit.deadline,
            zapInParams.permit.v,
            zapInParams.permit.r,
            zapInParams.permit.s
        );

        BORROWER_OPERATIONS.openCdpFor(
            zapInParams.cdp.borrowAmount, 
            zapInParams.cdp.upperHint, 
            zapInParams.cdp.lowerHint, 
            zapInParams.cdp.collAmount, 
            zapInParams.permit.borrower
        );
    }
}