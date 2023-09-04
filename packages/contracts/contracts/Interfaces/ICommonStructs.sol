// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ICommonStructs {
    /**
     * @dev All required state when adjusting a CDP.
     * @param price Current price
     * @param collChange Absolute value of collateral change for this adjustment. Can be zero.
     * @param isCollIncrease Sign of adjustment. True if collateral is increasing, false if decreasing.
     * @param netDebtChange Absolute value of debt change for this adjustment. Can be zero.
     * @param isDebtIncrease Sign of adjustment. True if debt is increasing, false if decreasing.
     * @param debt Debt units before adjustment operation.
     * @param coll Collateral shares before adjustment operation.
     * @param newDebt Debt units after adjustment operation.
     * @param newColl Collateral shares after adjustment operation.
     * @param oldICR ICR before adjustment operation, using current price.
     * @param newICR  ICR after adjustment operation, using current price.
     * @param newNICR  NICR after adjustment operation. Used to determine new position of CDP in Linked List.
     * @param newTCR  System TCR after adjustment operation, using current price.
     */
    struct AdjustCdpState {
        uint256 price;
        uint256 collChange;
        bool isCollIncrease;
        uint256 netDebtChange;
        bool isDebtIncrease;
        uint256 debt;
        uint256 coll;
        uint256 newDebt;
        uint256 newColl;
        uint256 oldICR;
        uint256 newICR;
        uint256 newNICR;
        uint256 newTCR;
    }
}
