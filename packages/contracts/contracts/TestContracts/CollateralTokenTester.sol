pragma solidity 0.6.11;

import "../Dependencies/ICollateralToken.sol";

// based on WETH9 contract
contract CollateralTokenTester is ICollateralToken {
    string public override name = "Collateral Token Tester in eBTC";
    string public override symbol = "CollTester";
    uint8 public override decimals = 18;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad, uint _share);
    event Deposit(address indexed dst, uint wad, uint _share);
    event Withdrawal(address indexed src, uint wad, uint _share);

    mapping(address => uint) private balances;
    mapping(address => mapping(address => uint)) public override allowance;

    uint private _ethPerShare = 1e18;
    uint private _totalBalance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        uint _share = getSharesByPooledEth(msg.value);
        balances[msg.sender] += _share;
        _totalBalance += _share;
        Deposit(msg.sender, msg.value, _share);
    }

    function withdraw(uint wad) public {
        uint _share = getSharesByPooledEth(wad);
        require(balances[msg.sender] >= _share);
        balances[msg.sender] -= _share;
        _totalBalance -= _share;
        msg.sender.transfer(wad);
        Withdrawal(msg.sender, wad, _share);
    }

    function totalSupply() public view override returns (uint) {
        return _totalBalance;
    }

    // helper to set allowance in test
    function nonStandardSetApproval(address owner, address guy, uint wad) external returns (bool) {
        allowance[owner][guy] = wad;
        Approval(owner, guy, wad);
        return true;
    }

    function approve(address guy, uint wad) public override returns (bool) {
        allowance[msg.sender][guy] = wad;
        Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public override returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public override returns (bool) {
        uint _share = getSharesByPooledEth(wad);
        require(balances[src] >= _share, "ERC20: transfer amount exceeds balance");

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balances[src] -= _share;
        balances[dst] += _share;

        Transfer(src, dst, wad, _share);

        return true;
    }

    // tests should adjust the ratio by this function
    function setEthPerShare(uint _ePerS) external {
        _ethPerShare = _ePerS;
    }

    function getSharesByPooledEth(uint256 _ethAmount) public view override returns (uint256) {
        uint _tmp = _mul(1e18, _ethAmount);
        return _div(_tmp, _ethPerShare);
    }

    function getPooledEthByShares(uint256 _sharesAmount) public view override returns (uint256) {
        uint _tmp = _mul(_ethPerShare, _sharesAmount);
        return _div(_tmp, 1e18);
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external override returns (bool) {
        approve(spender, allowance[msg.sender][spender] - subtractedValue);
        return true;
    }

    function balanceOf(address _usr) external view override returns (uint256) {
        uint _tmp = _mul(_ethPerShare, balances[_usr]);
        return _div(_tmp, 1e18);
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
}
