pragma solidity 0.8.17;

import {IERC3156FlashBorrower} from "../Interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "../Interfaces/IERC3156FlashLender.sol";
import {IERC20} from "../Dependencies/IERC20.sol";

interface ICdpManager {
    function liquidate(bytes32 _cdpId) external;
}

interface IRebasableTokenTester {
    function setEthPerShare(uint256 _ePerS) external;
}

contract SimpleLiquidationTester is IERC3156FlashBorrower {
    uint256 public _onReceiveType; //0-nothing, 1-reenter, 2-revert
    ICdpManager public _cdpManager;
    bytes32 public _reEnterLiqCdpId = bytes32(0); // only for _onReceiveType == 1

    event EtherReceived(address, uint256);

    function setCdpManager(address _cdpMgr) external {
        _cdpManager = ICdpManager(_cdpMgr);
    }

    function setReceiveType(uint256 _type) external {
        _onReceiveType = _type;
    }

    function setReEnterLiqCdpId(bytes32 _cdpId) external {
        _reEnterLiqCdpId = _cdpId;
    }

    function liquidateCdp(bytes32 _cdpId) external {
        _cdpManager.liquidate(_cdpId);
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
        if (_onReceiveType == 1) {
            _onReceiveType = 0; // just to stop at reenter once
            _cdpManager.liquidate(_reEnterLiqCdpId); //reenter liquidation
        } else if (_onReceiveType == 2) {
            revert("revert on receive");
        }
    }

    function initFlashLoan(address lender, address token, uint256 amount, uint256 _ppfs) external {
        IERC3156FlashLender(lender).flashLoan(
            IERC3156FlashBorrower(address(this)),
            token,
            amount,
            abi.encodePacked(_ppfs)
        );
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        uint256 _ppfs = abi.decode(data, (uint256));
        if (_ppfs == 0) {
            return keccak256("ERC3156FlashBorrower.onFlashLoanRevert");
        }

        IRebasableTokenTester(token).setEthPerShare(_ppfs);

        IERC20(token).approve(msg.sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // dummy test functions for activePool.sweepToken()
    function balanceOf(address account) external view returns (uint256) {
        return 1234567890;
    }

    // non-standard transfer() without returning bool
    function transfer(address recipient, uint256 amount) external {
        return;
    }
}
