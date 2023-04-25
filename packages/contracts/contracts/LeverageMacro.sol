pragma solidity 0.8.17;

import "./Interfaces/IBorrowerOperations.sol";

contract LeverageMacro {
    IBorrowerOperations public immutable borrowerOperations;

    constructor(address _borrowerOperationsAddress) {
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
    }

    function openCdpLeveraged(
        uint _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint _collAmount
    ) external returns (bytes32 cdpId) {
        // Flashloan final eBTC Balance (add buffer for fee)

        // Use eBTC Balance to Buy stETH

        // Deposit stETH (+ your stETH)

        // Mint eBTC

        // Repay FlashLoan + fee

        // Send eBTC to caller + Trove (NEED TO ALLOW TRANSFERING ON CREATION)
        return borrowerOperations.openCdpFor(_EBTCAmount, _upperHint, _lowerHint, _collAmount, msg.sender);
    }
}
