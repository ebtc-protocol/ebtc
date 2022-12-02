// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import './Interfaces/IDefaultPool.sol';
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

contract FeeManager is Ownable, CheckContract {
    using SafeMath for uint256;

    string constant public NAME = "FeeManager";

    address public lusdTokenAddress;
    address public troveManagerAddress;
    address public feeRecipient;

    event TroveManagerAddressChanged(address _troveManagerAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);
    event FeeRecipientChanged(address _feeRecipient);

    function setAddresses(
        address _lusdTokenAddress,
        address _troveManagerAddress, 
        address _feeRecipient
    )
        external
        onlyOwner
    {
        checkContract(_lusdTokenAddress);
        checkContract(_troveManagerAddress);

        lusdTokenAddress = _lusdTokenAddress;
        troveManagerAddress = _troveManagerAddress;
        feeRecipient = _feeRecipient;

        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
        emit FeeRecipientChanged(_feeRecipient);

        _renounceOwnership();
    }

    modifier onlyTroveManager() {
        require(msg.sender == troveManagerAddress);
        _;
    }

    function onOpenTrove(bytes32 _troveId, address _troveOwner, uint _amount, bytes32 _referralId) external onlyTroveManager {
    }

    function onAdjustTrove(bytes32 _troveId) external onlyTroveManager {

    }

    function onMint(bytes32 _troveId, address _troveOwner, uint _amount, bytes32 _referralId) external onlyTroveManager {
    
    }

    function collectFees() external {
        require (msg.sender == feeRecipient);
    }

}
