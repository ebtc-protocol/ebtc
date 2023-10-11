// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../contracts/Interfaces/ICdpManager.sol";

//common utilities for forge tests
contract Utilities is Test {
    uint256 internal constant DECIMAL_PRECISION = 1e18;
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));
    bytes32 internal nextSpecial = keccak256(abi.encodePacked("special address"));
    uint256 public constant LIQUIDATOR_REWARD = 2e17;

    function getNextSpecialAddress() public returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextSpecial))));
        nextSpecial = keccak256(abi.encodePacked(nextSpecial));
        return user;
    }

    function getNextUserAddress() public returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    //create users with 10000000 ether balance
    function createUsers(uint256 userNum) public returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = getNextUserAddress();
            vm.deal(user, 10000000 ether);
            users[i] = user;
        }
        return users;
    }

    //move block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks) public {
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
    }

    /* 
        Calculate collateral amount to post based on required debt, collateral price and CR
        Collateral amount is calculated as: (Debt * CR) / Price
        // TODO: Formula inaccurate
        // TODO: In fixing formula all tests mess up
    */
    function calculateCollAmount(
        uint256 debt,
        uint256 price,
        uint256 collateralRatio
    ) public pure returns (uint256) {
        return ((debt * 1e18 * collateralRatio) / price / 1e18) + LIQUIDATOR_REWARD; // add liquidator reward to
    }

    /* Calculate some relevant borrowed amount based on collateral, it's price and CR
    BorrowedAmount is calculated as: (Collateral * eBTC Price) / CR
    */
    function calculateBorrowAmount(
        uint256 coll,
        uint256 price,
        uint256 collateralRatio
    ) public pure returns (uint256) {
        return ((coll * price) / collateralRatio);
    }

    /// @dev Given Borrow Amount, Price and Collateral Ratio tells you how much to deposit
    function calculateCollateralAmount(
        uint256 borrowAmount,
        uint256 price,
        uint256 collateralRatio
    ) public pure returns (uint256) {
        return ((collateralRatio * borrowAmount) / price);
    }

    /* This is the function that generates the random number.
     * It takes the minimum and maximum values of the range as arguments
     * and returns the random number. Use `seed` attr to randomize more
     */
    function generateRandomNumber(
        uint256 min,
        uint256 max,
        address seed
    ) public view returns (uint256) {
        // Generate a random number using the keccak256 hash function
        uint256 randomNumber = uint256(
            keccak256(abi.encodePacked(block.number, block.timestamp, seed))
        );

        // Use the modulo operator to constrain the random number to the desired range
        uint256 result = (randomNumber % (max - min + 1)) + min;
        //        // Randomly shrink random number
        //        if (result % 4 == 0) {
        //            result /= 100;
        //        }
        return result;
    }

    // Source: https://github.com/transmissions11/solmate/blob/3a752b8c83427ed1ea1df23f092ea7a810205b6c/src/utils/FixedPointMathLib.sol#L53-L69
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(gt(mod(mul(x, y), denominator), 0), div(mul(x, y), denominator))
        }
    }

    function calculateBorrowAmountFromDebt(
        uint256 amount,
        uint256 gasCompensation,
        uint256 borrowingRate
    ) public pure returns (uint256) {
        // Borrow amount = (Debt - Gas compensation) / (1 + Borrow Rate)
        return
            mulDivUp(
                amount - gasCompensation,
                DECIMAL_PRECISION,
                (DECIMAL_PRECISION + borrowingRate)
            );
    }

    function assertApproximateEq(
        uint256 _num1,
        uint256 _num2,
        uint256 _tolerance
    ) public pure returns (bool) {
        if (_num1 > _num2) {
            return _tolerance >= (_num1 - _num2);
        } else {
            return _tolerance >= (_num2 - _num1);
        }
    }
}
