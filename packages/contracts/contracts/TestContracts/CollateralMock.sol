pragma solidity 0.6.11;

import "../Dependencies/ICollateralToken.sol";
import "../Dependencies/IERC20.sol";

/**
    Variant that takes in a specified WETH token as deposit coin
    Because we can't mint ETH on testnet ;)
 */
contract CollateralMock is ICollateralToken {
    string public override name = "Collateral Token Tester in eBTC";
    string public override symbol = "CollTester";
    uint8 public override decimals = 18;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    uint private _ethPerShare = 1e18;

    IERC20 public wETH;

    constructor(address _wethAddres) public {
        wETH = IERC20(_wethAddres);
    }

    receive() external payable {
        revert("Takes WETH token as deposit");
    }

    function deposit(uint256 wad) public {
        require(wETH.transferFrom(msg.sender, address(this), wad));
        balanceOf[msg.sender] += wad;
        emit Deposit(msg.sender, wad);
    }

    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        require(wETH.transfer(msg.sender, wad));
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view override returns (uint) {
        return wETH.balanceOf(address(this));
    }

    // helper to set allowance in test
    function nonStandardSetApproval(address owner, address guy, uint wad) external returns (bool) {
        allowance[owner][guy] = wad;
        emit Approval(owner, guy, wad);
        return true;
    }

    function approve(address guy, uint wad) public override returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public override returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public override returns (bool) {
        require(balanceOf[src] >= wad, "ERC20: transfer amount exceeds balance");

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }

    // tests should adjust the ratio by this function
    function setEthPerShare(uint _ePerS) external {
        _ethPerShare = _ePerS;
    }

    function getSharesByPooledEth(uint256 _ethAmount) external override returns (uint256) {
        uint _tmp = _mul(1e18, _ethAmount);
        return _div(_tmp, _ethPerShare);
    }

    function getPooledEthByShares(uint256 _sharesAmount) external override returns (uint256) {
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
