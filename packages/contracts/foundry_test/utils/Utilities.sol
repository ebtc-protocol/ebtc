// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.11;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../contracts/Dependencies/SafeMath.sol";

//common utilities for forge tests
contract Utilities is Test {
    using SafeMath for uint256;
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() public returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    //create users with 100 ether balance
    function createUsers(uint256 userNum)
        public
        returns (address payable[] memory)
    {
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

    /* Calculate some relevant borrowed amount based on collateral, it's price and CR
    BorrowedAmount is calculated as: (Collateral * eBTC Price) / CR
    */
    function calculateBorrowAmount(uint256 coll, uint256 price, uint256 collateralRatio)
        public pure returns (uint256) {
        return coll.mul(price).div(collateralRatio);
    }
    

    /// @dev Given Borrow Amount, Price and Collateral Ratio tells you how much to deposit
    function calculateCollateralAmount(
        uint256 borrowAmount, uint256 price, uint256 collateralRatio
    ) public pure returns (uint256) {
        return collateralRatio.mul(borrowAmount).div(price);
    }

    /* This is the function that generates the random number.
    * It takes the minimum and maximum values of the range as arguments
    * and returns the random number. Use `seed` attr to randomize more
    */
    function generateRandomNumber(uint min, uint max, address seed) public view returns (uint256) {
        // Generate a random number using the keccak256 hash function
        uint randomNumber = uint(keccak256(abi.encodePacked(block.difficulty, now, seed)));

        // Use the modulo operator to constrain the random number to the desired range
        uint result = randomNumber % (max - min + 1) + min;
        return result;
    }
}
