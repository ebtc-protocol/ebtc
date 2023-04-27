// SPDX-License-Identifier: MIT

import "./Interfaces/IGasPool.sol";
import "./Dependencies/ICollateralToken.sol";

pragma solidity 0.8.17;

/**
 * The purpose of this contract is to hold EBTC tokens for gas compensation:
 * https://github.com/liquity/dev#gas-compensation
 * When a borrower opens a cdp, an additional 50 EBTC debt is issued,
 * and 50 EBTC is minted and sent to this contract.
 * When a borrower closes their active cdp, this gas compensation is refunded:
 * 50 EBTC is burned from the this contract's balance, and the corresponding
 * 50 EBTC debt on the cdp is cancelled.
 * See this issue for more context: https://github.com/liquity/dev/issues/186
 */
contract GasPool is IGasPool {
    string public constant NAME = "GasPool";

    address public immutable borrowerOperationsAddress;
    address public immutable cdpManagerAddress;

    ICollateralToken public collateral;

    uint256 internal StEthColl; // deposited collateral tracker

    mapping(address => uint256) public override liquidatorRewardSharesFor;

    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _collTokenAddress
    ) {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        collateral = ICollateralToken(_collTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit CollateralAddressChanged(_collTokenAddress);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the StEthColl state variable.
     *
     *Not necessarily equal to the the contract's raw StEthColl balance - ether can be forcibly sent to contracts.
     */
    function getStEthColl() external view override returns (uint) {
        return StEthColl;
    }

    function getEBTCDebt() external view override returns (uint) {
        return 0;
    }

    function sendStEthColl(address _account, uint _amount) external override {
        _requireCallerIsBOorCdpM();
        require(StEthColl >= _amount, "GasPool: Insufficient stEth balance");

        StEthColl = StEthColl - _amount;
        emit GasPoolStEthBalanceUpdated(StEthColl);
        emit CollateralSent(_account, _amount);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, _amount);
    }

    function receiveColl(uint _value) external override {
        _requireCallerIsBOorCdpM();
        StEthColl = StEthColl + _value;
        emit GasPoolStEthBalanceUpdated(StEthColl);
    }

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "GasPool: Caller is neither BorrowerOperations nor CdpManager"
        );
    }
}
