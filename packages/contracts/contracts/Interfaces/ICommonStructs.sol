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
        uint price;
        uint collChange;
        bool isCollIncrease;
        uint netDebtChange;
        bool isDebtIncrease;
        uint debt;
        uint coll;
        uint newDebt;
        uint newColl;
        uint oldICR;
        uint newICR;
        uint newNICR;
        uint newTCR;
    }
}
