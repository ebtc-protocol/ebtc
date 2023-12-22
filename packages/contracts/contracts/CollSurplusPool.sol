// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/ICollateralToken.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/ReentrancyGuard.sol";
import "./Dependencies/AuthNoOwner.sol";
import "./Interfaces/IActivePool.sol";

/// @notice CollSurplusPool holds stETH collateral for Cdp owner when redemption or liquidation happens
/// @notice only if there is a remaining portion of the closed Cdp for the owner to claim
/// @dev While an owner could have multiple different sized Cdps, the remaining surplus colateral from all of its closed Cdp
/// @dev is consolidated into one balance here
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
    }

    /// @return The current total collateral surplus available in this pool
    function getTotalSurplusCollShares() external view override returns (uint256) {
        return totalSurplusCollShares;
    }

    /// @return The collateral surplus available for the specified owner _account
    /// @param _account The address of the owner whose surplus balance to be queried
    function getSurplusCollShares(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    // --- Pool functionality ---

    /// @notice Increases the claimable surplus collateral shares for the specified account.
    /// @notice Internal permissioned system function, can track amounts added from collateral shares and liquidator reward shares separately for accounting purposes.
    /// @dev Only the CdpManager contract can call this function.
    /// @param _cdpId CdpId surplus collateral shares come from, for accounting purposes.
    /// @param _account The account to increase collateral surplus balance for.
    /// @param _collateralShares The number of collateral shares to be added to the owner's surplus balance, from Cdp collateral shares.
    /// @param _liquidatorRewardShares The number of collateral shares to be added to the owner's surplus balance, from liquidator reward shares.
    function increaseSurplusCollShares(
        bytes32 _cdpId,
        address _account,
        uint256 _collateralShares,
        uint256 _liquidatorRewardShares
    ) external override {
        _requireCallerIsCdpManager();

        uint256 _totalClaimableSurplusCollShares = balances[_account] +
            _collateralShares +
            _liquidatorRewardShares;
        balances[_account] = _totalClaimableSurplusCollShares;

        emit SurplusCollSharesAdded(
            _cdpId,
            _account,
            _totalClaimableSurplusCollShares,
            _collateralShares,
            _liquidatorRewardShares
        );
    }

    /// @notice Allow owner to claim all its surplus recorded in this pool
    /// @dev stETH token will be sent to _account address if any surplus exist
    /// @param _account The owner address whose surplus balance is to be claimed
    function claimSurplusCollShares(address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint256 claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;

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

    /// @notice Increase total collateral surplus balance by _value
    /// @param _value The surplus increase value
    /// @dev only ActivePool is allowed to call this function
    function increaseTotalSurplusCollShares(uint256 _value) external override {
        _requireCallerIsActivePool();
        totalSurplusCollShares = totalSurplusCollShares + _value;
    }

    // === Governed Functions === //

    /// @dev Function to move unintended dust that are not protected to fee recipient
    /// @notice moves given amount of given token (collateral is NOT allowed)
    /// @notice because recipient are fixed, this function is safe to be called by anyone
    /// @param token The token to be swept
    /// @param amount The token value to be swept
    function sweepToken(address token, uint256 amount) public nonReentrant requiresAuth {
        require(token != address(collateral), "CollSurplusPool: Cannot Sweep Collateral");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "CollSurplusPool: Attempt to sweep more than balance");

        IERC20(token).safeTransfer(feeRecipientAddress, amount);

        emit SweepTokenSuccess(token, amount, feeRecipientAddress);
    }
}
