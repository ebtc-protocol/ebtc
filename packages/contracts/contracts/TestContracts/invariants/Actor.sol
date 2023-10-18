pragma solidity 0.8.17;

import {IERC3156FlashBorrower} from "../../Interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "../../Dependencies/IERC20.sol";

contract Actor is IERC3156FlashBorrower {
    address[] internal tokens;
    address[] internal callers;

    constructor(address[] memory _tokens, address[] memory _callers) payable {
        tokens = _tokens;
        callers = _callers;
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(callers[i], type(uint256).max);
        }
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
        address,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        bool isValidCaller = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (token == tokens[i]) {
                isValidCaller = msg.sender == callers[i];
                break;
            }
        }
        require(isValidCaller, "Invalid caller");

        if (data.length != 0) {
            (address[] memory _targets, bytes[] memory _calldatas) = abi.decode(
                data,
                (address[], bytes[])
            );
            for (uint256 i = 0; i < _targets.length; ++i) {
                (bool success, ) = address(_targets[i]).call(_calldatas[i]);
                require(success);
            }
        }

        IERC20(token).approve(msg.sender, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
