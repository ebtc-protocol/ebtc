// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IDefaultPool.sol";
import "./Interfaces/IActivePool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";

/*
 * The Default Pool holds the stETH collateral and EBTC debt (but not EBTC tokens) from liquidations that have been redistributed
 * to active cdps but not yet "applied", i.e. not yet recorded on a recipient active cdp's struct.
 *
 * When a cdp makes an operation that applies its pending stETH collateral and EBTC debt, its pending stETH collateral and EBTC debt is moved
 * from the Default Pool to the Active Pool.
 */

/**
 * @title Default Pool Contract
 * @dev The Default Pool holds the stETH collateral and EBTC debt (but not EBTC tokens) from liquidations that have been redistributed to active cdps but not yet "applied", i.e. not yet recorded on a recipient active cdp's struct.
 * When a cdp makes an operation that applies its pending stETH collateral and EBTC debt, its pending stETH collateral and EBTC debt is moved from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool, ReentrancyGuard, AuthNoOwner {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public constant NAME = "DefaultPool";

    address public cdpManagerAddress;
    address public activePoolAddress;
    address public feeRecipientAddress;
    uint256 internal StEthColl; // deposited stETH collateral tracker
    uint256 internal EBTCDebt; // debt
    ICollateralToken public collateral;

    // -- Permissioned Function Signatures --
    bytes4 private constant SWEEP_TOKEN_SIG =
        bytes4(keccak256(bytes("sweepToken(address,uint256)")));

    // --- Dependency setters ---

    /**
     * @notice Sets the addresses for the contract's dependencies.
     * @param _cdpManagerAddress The address of the cdp manager contract
     * @param _activePoolAddress The address of the active pool contract
     * @param _collTokenAddress The address of the collateral token contract
     */
    function setAddresses(
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) external onlyOwner {
        checkContract(_cdpManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_collTokenAddress);

        cdpManagerAddress = _cdpManagerAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);
        feeRecipientAddress = IActivePool(activePoolAddress).feeRecipientAddress();

        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the StEthColl state variable.
     *
     * Not necessarily equal to the the contract's raw stETH collateral balance - ether can be forcibly sent to contracts.
     */

    /**
     * @notice Returns the value of the StEthColl state variable
     * @return The value of the StEthColl state variable
     */
    function getStEthColl() external view override returns (uint) {
        return StEthColl;
    }

    /**
     * @notice Returns the value of the EBTCDebt state variable
     * @return The value of the EBTCDebt state variable
     */
    function getEBTCDebt() external view override returns (uint) {
        return EBTCDebt;
    }

    // --- Pool functionality ---

    /**
     * @notice Sends ETH to the active pool contract
     * @param _amount The amount of ETH to send
     */
    function sendETHToActivePool(uint _amount) external override {
        _requireCallerIsCdpManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        require(StEthColl >= _amount, "!DefaultPoolBal");
        StEthColl = StEthColl - _amount;
        emit DefaultPoolETHBalanceUpdated(StEthColl);
        emit CollateralSent(activePool, _amount);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(activePool, _amount);
        IActivePool(activePool).receiveColl(_amount);
    }

    /**
     * @notice Increases the value of the EBTCDebt state variable
     * @param _amount The amount to increase by
     */
    function increaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt + _amount;
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    /**
     * @notice Decreases the value of the EBTCDebt state variable
     * @param _amount The amount to decrease by
     */
    function decreaseEBTCDebt(uint _amount) external override {
        _requireCallerIsCdpManager();
        EBTCDebt = EBTCDebt - _amount;
        emit DefaultPoolEBTCDebtUpdated(EBTCDebt);
    }

    // --- 'require' functions ---

    /**
     * @notice Checks if the caller is the ActivePool contract
     */
    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    /**
     * @notice Checks if the caller is the CdpManager contract
     */
    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "DefaultPool: Caller is not the CdpManager");
    }

    /**
     * @notice Receives collateral from the active pool contract
     * @param _value The amount of collateral to receive
     */
    function receiveColl(uint _value) external override {
        _requireCallerIsActivePool();
        StEthColl = StEthColl + _value;
        emit DefaultPoolETHBalanceUpdated(StEthColl);
    }

    // === Governed Functions === //

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    function sweepToken(address token, uint amount) public nonReentrant {
        require(
            isAuthorized(msg.sender, SWEEP_TOKEN_SIG),
            "DefaultPool: sender not authorized for sweepToken(address,uint256)"
        );
        require(token != address(collateral), "DefaultPool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "DefaultPool: Attempt to sweep more than balance");

        IERC20(token).safeTransfer(feeRecipientAddress, amount);
    }
}
