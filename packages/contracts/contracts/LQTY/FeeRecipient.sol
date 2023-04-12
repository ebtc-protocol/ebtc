// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Interfaces/IFeeRecipient.sol";
import "../Dependencies/LiquityMath.sol";
import "../Interfaces/IEBTCToken.sol";
import "../Interfaces/ICdpManager.sol";
import "../Dependencies/ICollateralToken.sol";

contract FeeRecipient is IFeeRecipient, Ownable, CheckContract, BaseMath {
    // --- Data ---
    string public constant NAME = "FeeRecipient";

    IEBTCToken public ebtcToken;
    ICollateralToken public collateral;

    address public cdpManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Functions ---

    function setAddresses(
        address _ebtcTokenAddress,
        address _cdpManagerAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) external override onlyOwner {
        checkContract(_ebtcTokenAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);
        checkContract(_collTokenAddress);

        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        cdpManagerAddress = _cdpManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);

        emit EBTCTokenAddressSet(_ebtcTokenAddress);
        emit CdpManagerAddressSet(_cdpManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);
        emit CollateralAddressSet(_collTokenAddress);

        renounceOwnership();
    }

    // --- Reward-per-unit-staked increase functions. Called by Liquity core contracts ---

    /// @dev notify receipt of stETH fee
    function receiveStEthFee(uint _amount) external override {
        _requireCallerIsActivePool();
        emit ReceiveFee(msg.sender, address(collateral), _amount);
    }

    /// @dev notify receipt of eBTC fee
    function receiveEbtcFee(uint _amount) external override {
        _requireCallerIsBOorCdpM();
        emit ReceiveFee(msg.sender, address(ebtcToken), _amount);
    }

    /// @notice Claim stETH fee from CdpManager
    /// @dev Can later include keeper incentives here to automate calling
    function claimStakingSplitFee() public override {
        ICdpManager(cdpManagerAddress).claimStakingSplitFee();
    }

    // --- 'require' functions ---

    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "FeeRecipient: caller is not CdpM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "FeeRecipient: caller is not BorrowerOps");
    }

    function _requireCallerIsBOorCdpM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == cdpManagerAddress,
            "FeeRecipient: Caller is neither BorrowerOperations nor CdpManager"
        );
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "FeeRecipient: caller is not ActivePool");
    }

    // TODO: Add Governable sweep function
}
