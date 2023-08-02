pragma solidity 0.8.17;

import {IERC3156FlashBorrower} from "../../Interfaces/IERC3156FlashBorrower.sol";
import {EBTCTokenTester} from "../EBTCTokenTester.sol";
import {BorrowerOperations} from "../../BorrowerOperations.sol";
import {ActivePool} from "../../ActivePool.sol";
import {IERC20} from "../../Dependencies/IERC20.sol";

contract Actor is IERC3156FlashBorrower {
    EBTCTokenTester immutable ebtcToken;
    BorrowerOperations immutable borrowerOperations;
    ActivePool immutable activePool;

    constructor(
        EBTCTokenTester _ebtcToken,
        BorrowerOperations _borrowerOperations,
        ActivePool _activePool
    ) payable {
        ebtcToken = _ebtcToken;
        borrowerOperations = _borrowerOperations;
        activePool = _activePool;
    }

    function proxy(
        address _target,
        bytes memory _calldata
    ) public returns (bool success, bytes memory returnData) {
        (success, returnData) = address(_target).call(_calldata);
    }

    function proxy(
        address _target,
        bytes memory _calldata,
        uint256 value
    ) public returns (bool success, bytes memory returnData) {
        (success, returnData) = address(_target).call{value: value}(_calldata);
    }

    receive() external payable {}

    // callback for flashloan
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        if (token == address(ebtcToken)) {
            require(msg.sender == address(borrowerOperations), "!borrowerOperationsFLSender");
        } else {
            require(msg.sender == address(activePool), "!activePoolFLSender");
        }

        IERC20(token).approve(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
