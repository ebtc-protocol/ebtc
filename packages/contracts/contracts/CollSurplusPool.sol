// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Interfaces/IActivePool.sol";

contract CollSurplusPool is ICollSurplusPool, ReentrancyGuard, AuthNoOwner {
    using SafeERC20 for IERC20;

    string public constant NAME = "CollSurplusPool";

    address public immutable borrowerOperationsAddress;
    address public immutable cdpManagerAddress;
    address public immutable activePoolAddress;
    address public immutable feeRecipientAddress;
    ICollateralToken public immutable collateral;

    // deposited ether tracker
    uint256 internal totalSurplusCollShares;
    // Collateral surplus claimable by cdp owners
    mapping(address => uint256) internal balances;

    // --- Contract setters ---

    /**
     * @notice Sets the addresses of the contracts and renounces ownership
     * @dev One-time initialization function. Can only be called by the owner as a security measure. Ownership is renounced after the function is called.
     * @param _borrowerOperationsAddress The address of the BorrowerOperations
     * @param _cdpManagerAddress The address of the CDPManager
     * @param _activePoolAddress The address of the ActivePool
     * @param _collTokenAddress The address of the CollateralToken
     */
    constructor(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);
        feeRecipientAddress = IActivePool(activePoolAddress).feeRecipientAddress();

        address _authorityAddress = address(AuthNoOwner(cdpManagerAddress).authority());
        if (_authorityAddress != address(0)) {
            _initializeAuthority(_authorityAddress);
        }

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);
    }

    /**
     * @notice Gets the current collateral state variable of the pool
     * @dev Not necessarily equal to the raw collateral token balance - tokens can be forcibly sent to contracts
     * @return The current collateral balance tracked by the variable
     */
    function getTotalSurplusCollShares() external view override returns (uint256) {
        return totalSurplusCollShares;
    }

    /**
     * @notice Gets the collateral surplus available for the given account
     * @param _account The address of the account
     * @return The collateral balance available to claim
     */
    function getSurplusCollShares(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function increaseSurplusCollShares(address _account, uint256 _amount) external override {
        _requireCallerIsCdpManager();

        uint256 newAmount = balances[_account] + _amount;
        balances[_account] = newAmount;

        emit SurplusCollSharesUpdated(_account, newAmount);
    }

    function claimSurplusCollShares(address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint256 claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit SurplusCollSharesUpdated(_account, 0);

        uint256 cachedTotalSurplusCollShares = totalSurplusCollShares;

        require(cachedTotalSurplusCollShares >= claimableColl, "!CollSurplusPoolBal");
        // Safe per the check above
        unchecked {
            totalSurplusCollShares = cachedTotalSurplusCollShares - claimableColl;
        }
        emit CollSharesTransferred(_account, claimableColl);

        // NOTE: No need for safe transfer if the collateral asset is standard. Make sure this is the case!
        collateral.transferShares(_account, claimableColl);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CollSurplusPool: Caller is not Borrower Operations"
        );
    }

    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "CollSurplusPool: Caller is not CdpManager");
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "CollSurplusPool: Caller is not Active Pool");
    }

    function increaseTotalSurplusCollShares(uint256 _value) external override {
        _requireCallerIsActivePool();
        totalSurplusCollShares = totalSurplusCollShares + _value;
    }

    // === Governed Functions === //

    /// @dev Function to move unintended dust that are not protected
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    function sweepToken(address token, uint256 amount) public nonReentrant requiresAuth {
        require(token != address(collateral), "CollSurplusPool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "CollSurplusPool: Attempt to sweep more than balance");

        IERC20(token).safeTransfer(feeRecipientAddress, amount);

        emit SweepTokenSuccess(token, amount, feeRecipientAddress);
    }
}
