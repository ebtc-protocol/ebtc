// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ICollSurplusPool.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/ICollateralToken.sol";

contract CollSurplusPool is Ownable, CheckContract, ICollSurplusPool {
    using SafeMath for uint256;

    string public constant NAME = "CollSurplusPool";

    address public borrowerOperationsAddress;
    address public cdpManagerAddress;
    address public activePoolAddress;
    ICollateralToken public collateral;

    // deposited ether tracker
    uint256 internal ETH;
    // Collateral surplus claimable by cdp owners
    mapping(address => uint) internal balances;

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CdpManagerAddressChanged(address _newCdpManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event CollateralAddressChanged(address _collTokenAddress);

    event CollBalanceUpdated(address indexed _account, uint _newBalance);
    event EtherSent(address _to, uint _amount);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _cdpManagerAddress,
        address _activePoolAddress,
        address _collTokenAddress
    ) external override onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_collTokenAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        cdpManagerAddress = _cdpManagerAddress;
        activePoolAddress = _activePoolAddress;
        collateral = ICollateralToken(_collTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CdpManagerAddressChanged(_cdpManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit CollateralAddressChanged(_collTokenAddress);

        _renounceOwnership();
    }

    /* Returns the ETH state variable at ActivePool address.
       Not necessarily equal to the raw ether balance - ether can be forcibly sent to contracts. */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function accountSurplus(address _account, uint _amount) external override {
        _requireCallerIsCdpManager();

        uint newAmount = balances[_account].add(_amount);
        balances[_account] = newAmount;

        emit CollBalanceUpdated(_account, newAmount);
    }

    function claimColl(address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        require(ETH >= claimableColl, "!CollSurplusPoolBal");
        ETH = ETH.sub(claimableColl);
        emit EtherSent(_account, claimableColl);
		
        // NOTE: No need for safe transfer, stETH is standard
        collateral.transfer(_account, claimableColl); //_account.call{value: claimableColl}("");
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

    function receiveColl(uint _value) external override {
        _requireCallerIsActivePool();
        ETH = ETH.add(_value);
    }
}
