// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/BaseMath.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ILQTYStaking.sol";
import "../Dependencies/LiquityMath.sol";
import "../Interfaces/IEBTCToken.sol";

contract LQTYStaking is ILQTYStaking, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---
    string public constant NAME = "LQTYStaking";

    mapping(address => uint) public stakes;
    uint public totalLQTYStaked;

    uint public F_ETH; // Running sum of ETH fees per-LQTY-staked
    uint public F_EBTC; // Running sum of LQTY fees per-LQTY-staked

    // User snapshots of F_ETH and F_EBTC, taken at the point at which their latest deposit was made
    mapping(address => Snapshot) public snapshots;

    struct Snapshot {
        uint F_ETH_Snapshot;
        uint F_EBTC_Snapshot;
    }

    ILQTYToken public lqtyToken;
    IEBTCToken public ebtcToken;

    address public cdpManagerAddress;
    address public borrowerOperationsAddress;
    address public activePoolAddress;

    // --- Events ---

    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event EBTCTokenAddressSet(address _ebtcTokenAddress);
    event CdpManagerAddressSet(address _cdpManager);
    event BorrowerOperationsAddressSet(address _borrowerOperationsAddress);
    event ActivePoolAddressSet(address _activePoolAddress);

    event StakeChanged(address indexed staker, uint newStake);
    event StakingGainsWithdrawn(address indexed staker, uint EBTCGain, uint ETHGain);
    event F_ETHUpdated(uint _F_ETH);
    event F_EBTCUpdated(uint _F_EBTC);
    event TotalLQTYStakedUpdated(uint _totalLQTYStaked);
    event EtherSent(address _account, uint _amount);
    event StakerSnapshotsUpdated(address _staker, uint _F_ETH, uint _F_EBTC);

    // --- Functions ---

    function setAddresses(
        address _lqtyTokenAddress,
        address _ebtcTokenAddress,
        address _cdpManagerAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress
    ) external override onlyOwner {
        checkContract(_lqtyTokenAddress);
        checkContract(_ebtcTokenAddress);
        checkContract(_cdpManagerAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);

        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        ebtcToken = IEBTCToken(_ebtcTokenAddress);
        cdpManagerAddress = _cdpManagerAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePoolAddress = _activePoolAddress;

        emit LQTYTokenAddressSet(_lqtyTokenAddress);
        emit LQTYTokenAddressSet(_ebtcTokenAddress);
        emit CdpManagerAddressSet(_cdpManagerAddress);
        emit BorrowerOperationsAddressSet(_borrowerOperationsAddress);
        emit ActivePoolAddressSet(_activePoolAddress);

        _renounceOwnership();
    }

    // If caller has a pre-existing stake, send any accumulated ETH and EBTC gains to them.
    function stake(uint _LQTYamount) external override {
        _requireNonZeroAmount(_LQTYamount);

        uint currentStake = stakes[msg.sender];

        uint ETHGain;
        uint EBTCGain;
        // Grab any accumulated ETH and EBTC gains from the current stake
        if (currentStake != 0) {
            ETHGain = _getPendingETHGain(msg.sender);
            EBTCGain = _getPendingEBTCGain(msg.sender);
        }

        _updateUserSnapshots(msg.sender);

        uint newStake = currentStake.add(_LQTYamount);

        // Increase user’s stake and total LQTY staked
        stakes[msg.sender] = newStake;
        totalLQTYStaked = totalLQTYStaked.add(_LQTYamount);
        emit TotalLQTYStakedUpdated(totalLQTYStaked);

        // Transfer LQTY from caller to this contract
        lqtyToken.sendToLQTYStaking(msg.sender, _LQTYamount);

        emit StakeChanged(msg.sender, newStake);
        emit StakingGainsWithdrawn(msg.sender, EBTCGain, ETHGain);

        // Send accumulated EBTC and ETH gains to the caller
        if (currentStake != 0) {
            ebtcToken.transfer(msg.sender, EBTCGain);
            _sendETHGainToUser(ETHGain);
        }
    }

    // Unstake the LQTY and send the it back to the caller, along with their accumulated EBTC & ETH gains.
    // If requested amount > stake, send their entire stake.
    function unstake(uint _LQTYamount) external override {
        uint currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab any accumulated ETH and EBTC gains from the current stake
        uint ETHGain = _getPendingETHGain(msg.sender);
        uint EBTCGain = _getPendingEBTCGain(msg.sender);

        _updateUserSnapshots(msg.sender);

        if (_LQTYamount > 0) {
            uint LQTYToWithdraw = LiquityMath._min(_LQTYamount, currentStake);

            uint newStake = currentStake.sub(LQTYToWithdraw);

            // Decrease user's stake and total LQTY staked
            stakes[msg.sender] = newStake;
            totalLQTYStaked = totalLQTYStaked.sub(LQTYToWithdraw);
            emit TotalLQTYStakedUpdated(totalLQTYStaked);

            // Transfer unstaked LQTY to user
            lqtyToken.transfer(msg.sender, LQTYToWithdraw);

            emit StakeChanged(msg.sender, newStake);
        }

        emit StakingGainsWithdrawn(msg.sender, EBTCGain, ETHGain);

        // Send accumulated EBTC and ETH gains to the caller
        ebtcToken.transfer(msg.sender, EBTCGain);
        _sendETHGainToUser(ETHGain);
    }

    // --- Reward-per-unit-staked increase functions. Called by Liquity core contracts ---

    function increaseF_ETH(uint _ETHFee) external override {
        _requireCallerIsCdpManager();
        uint ETHFeePerLQTYStaked;

        if (totalLQTYStaked > 0) {
            ETHFeePerLQTYStaked = _ETHFee.mul(DECIMAL_PRECISION).div(totalLQTYStaked);
        }

        F_ETH = F_ETH.add(ETHFeePerLQTYStaked);
        emit F_ETHUpdated(F_ETH);
    }

    function increaseF_EBTC(uint _EBTCFee) external override {
        _requireCallerIsBorrowerOperations();
        uint EBTCFeePerLQTYStaked;

        if (totalLQTYStaked > 0) {
            EBTCFeePerLQTYStaked = _EBTCFee.mul(DECIMAL_PRECISION).div(totalLQTYStaked);
        }

        F_EBTC = F_EBTC.add(EBTCFeePerLQTYStaked);
        emit F_EBTCUpdated(F_EBTC);
    }

    // --- Pending reward functions ---

    function getPendingETHGain(address _user) external view override returns (uint) {
        return _getPendingETHGain(_user);
    }

    function _getPendingETHGain(address _user) internal view returns (uint) {
        uint F_ETH_Snapshot = snapshots[_user].F_ETH_Snapshot;
        uint ETHGain = stakes[_user].mul(F_ETH.sub(F_ETH_Snapshot)).div(DECIMAL_PRECISION);
        return ETHGain;
    }

    function getPendingEBTCGain(address _user) external view override returns (uint) {
        return _getPendingEBTCGain(_user);
    }

    function _getPendingEBTCGain(address _user) internal view returns (uint) {
        uint F_EBTC_Snapshot = snapshots[_user].F_EBTC_Snapshot;
        uint EBTCGain = stakes[_user].mul(F_EBTC.sub(F_EBTC_Snapshot)).div(DECIMAL_PRECISION);
        return EBTCGain;
    }

    // --- Internal helper functions ---

    function _updateUserSnapshots(address _user) internal {
        snapshots[_user].F_ETH_Snapshot = F_ETH;
        snapshots[_user].F_EBTC_Snapshot = F_EBTC;
        emit StakerSnapshotsUpdated(_user, F_ETH, F_EBTC);
    }

    function _sendETHGainToUser(uint ETHGain) internal {
        emit EtherSent(msg.sender, ETHGain);
        (bool success, ) = msg.sender.call{value: ETHGain}("");
        require(success, "LQTYStaking: Failed to send accumulated ETHGain");
    }

    // --- 'require' functions ---

    function _requireCallerIsCdpManager() internal view {
        require(msg.sender == cdpManagerAddress, "LQTYStaking: caller is not CdpM");
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "LQTYStaking: caller is not BorrowerOps");
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "LQTYStaking: caller is not ActivePool");
    }

    function _requireUserHasStake(uint currentStake) internal pure {
        require(currentStake > 0, "LQTYStaking: User must have a non-zero stake");
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, "LQTYStaking: Amount must be non-zero");
    }

    receive() external payable {
        _requireCallerIsActivePool();
    }
}
