// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../Dependencies/ICollateralToken.sol";
import "../Dependencies/ICollateralTokenOracle.sol";
import "../Dependencies/Ownable.sol";

interface IEbtcInternalPool {
    function increaseSystemCollShares(uint256 _value) external;
}

// based on WETH9 contract
contract CollateralTokenTester is ICollateralToken, ICollateralTokenOracle, Ownable {
    string public override name = "Collateral Token Tester in eBTC";
    string public override symbol = "CollTester";
    uint8 public override decimals = 18;

    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);
    event Deposit(address indexed dst, uint256 wad, uint256 _share);
    event Withdrawal(address indexed src, uint256 wad, uint256 _share);
    event UncappedMinterAdded(address indexed account);
    event UncappedMinterRemoved(address indexed account);
    event MintCapSet(uint256 indexed newCap);
    event MintCooldownSet(uint256 indexed newCooldown);

    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => bool) public isUncappedMinter;
    mapping(address => uint256) public lastMintTime;

    // Faucet capped at 10 Collateral tokens per day
    uint256 public mintCap = 10e18;
    uint256 public mintCooldown = 60 * 60 * 24;

    // NOTE: Seeded a 1e18 to avoid bs
    uint256 _getTotalShares = 1e18;
    uint256 _getTotalPooledEther = 1e18;
    mapping(address => uint256) public shares;

    uint256 private epochsPerFrame = 225;
    uint256 private slotsPerEpoch = 32;
    uint256 private secondsPerSlot = 12;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        uint256 _share = getSharesByPooledEth(msg.value);
        shares[msg.sender] += _share;
        _getTotalShares += _share;
        _getTotalPooledEther += msg.value;

        emit Deposit(msg.sender, msg.value, _share);
    }

    /// @dev Deposit collateral without ether for testing purposes
    function forceDeposit(uint256 ethToDeposit) external {
        if (!isUncappedMinter[msg.sender]) {
            require(ethToDeposit <= mintCap, "CollTester: Above mint cap");
            require(
                lastMintTime[msg.sender] == 0 ||
                    lastMintTime[msg.sender] + mintCooldown < block.timestamp,
                "CollTester: Cooldown period not completed"
            );
            lastMintTime[msg.sender] = block.timestamp;
        }
        uint256 _share = getSharesByPooledEth(ethToDeposit);
        shares[msg.sender] += _share;
        _getTotalShares += _share;
        _getTotalPooledEther += ethToDeposit;

        emit Deposit(msg.sender, ethToDeposit, _share);
    }

    function withdraw(uint256 wad) public {
        uint256 _share = getSharesByPooledEth(wad);
        require(shares[msg.sender] >= _share);
        shares[msg.sender] -= _share;
        _getTotalShares -= _share;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad, _share);
    }

    function totalSupply() public view override returns (uint) {
        return _getTotalPooledEther;
    }

    // Permissioned functions
    function addUncappedMinter(address account) external onlyOwner {
        isUncappedMinter[account] = true;
        emit UncappedMinterAdded(account);
    }

    function removeUncappedMinter(address account) external onlyOwner {
        isUncappedMinter[account] = false;
        emit UncappedMinterRemoved(account);
    }

    function setMintCap(uint256 newCap) external onlyOwner {
        mintCap = newCap;
        emit MintCapSet(newCap);
    }

    function setMintCooldown(uint256 newCooldown) external onlyOwner {
        mintCooldown = newCooldown;
        emit MintCooldownSet(newCooldown);
    }

    // helper to set allowance in test
    function nonStandardSetApproval(
        address owner,
        address guy,
        uint256 wad
    ) external returns (bool) {
        allowance[owner][guy] = wad;
        emit Approval(owner, guy, wad);
        return true;
    }

    function approve(address guy, uint256 wad) public override returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public override returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public override returns (bool) {
        uint256 _share = getSharesByPooledEth(wad);
        require(shares[src] >= _share, "ERC20: transfer amount exceeds balance");

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        shares[src] -= _share;
        shares[dst] += _share;

        _emitTransferEvents(src, dst, wad, _share);

        return true;
    }

    // tests should adjust the ratio by this function
    function setEthPerShare(uint256 _ePerS) external {
        // We change this
        _getTotalPooledEther = _div(_mul(_getTotalShares, _ePerS), 1e18);
    }

    function getEthPerShare() external view returns (uint256) {
        return _div(_mul(1e18, _getTotalPooledEther), _getTotalShares);
    }

    /***
        function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
            return _ethAmount
                .mul(_getTotalShares())
                .div(_getTotalPooledEther());
        }
     */

    function getSharesByPooledEth(uint256 _ethAmount) public view override returns (uint256) {
        return _div(_mul(_ethAmount, _getTotalShares), _getTotalPooledEther);
    }

    /**
            function getPooledEthByShares(uint256 _sharesAmount) public view returns (uint256) {
            return _sharesAmount
                .mul(_getTotalPooledEther())
                .div(_getTotalShares());
        }
     */

    function getPooledEthByShares(uint256 _sharesAmount) public view override returns (uint256) {
        return _div(_mul(_sharesAmount, _getTotalPooledEther), _getTotalShares);
    }

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) public override returns (uint256) {
        uint256 _tknAmt = getPooledEthByShares(_sharesAmount);

        // NOTE: Changed here to transfer underlying shares without rounding
        shares[msg.sender] -= _sharesAmount;
        shares[_recipient] += _sharesAmount;

        _emitTransferEvents(msg.sender, _recipient, _tknAmt, _sharesAmount);

        return _tknAmt;
    }

    function sharesOf(address _account) public view override returns (uint256) {
        return shares[_account];
    }

    function getOracle() external view override returns (address) {
        return address(this);
    }

    function getBeaconSpec() public view override returns (uint64, uint64, uint64, uint64) {
        return (
            uint64(epochsPerFrame),
            uint64(slotsPerEpoch),
            uint64(secondsPerSlot),
            uint64(block.timestamp)
        );
    }

    function setBeaconSpec(
        uint64 _epochsPerFrame,
        uint64 _slotsPerEpoch,
        uint64 _secondsPerSlot
    ) external {
        epochsPerFrame = _epochsPerFrame;
        slotsPerEpoch = _slotsPerEpoch;
        secondsPerSlot = _secondsPerSlot;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external override returns (bool) {
        approve(spender, allowance[msg.sender][spender] - subtractedValue);
        return true;
    }

    function balanceOf(address _usr) external view override returns (uint256) {
        return getPooledEthByShares(shares[_usr]);
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external override returns (bool) {
        approve(spender, allowance[msg.sender][spender] + addedValue);
        return true;
    }

    // internal helper functions
    function _mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function _div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: zero denominator");
        uint256 c = a / b;
        return c;
    }

    // dummy test purpose
    function feeRecipientAddress() external view returns (address) {
        return address(this);
    }

    function authority() external view returns (address) {
        return address(this);
    }

    /**
     * @dev Emits {Transfer} and {TransferShares} events
     */
    function _emitTransferEvents(
        address _from,
        address _to,
        uint _tokenAmount,
        uint256 _sharesAmount
    ) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }
}
