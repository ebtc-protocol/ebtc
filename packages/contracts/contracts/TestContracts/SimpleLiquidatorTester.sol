pragma solidity 0.6.11;

interface ICdpManager {
    function liquidate(bytes32 _troveId) external;
}

contract SimpleLiquidationTester {
    uint public _onReceiveType; //0-nothing, 1-reenter, 2-revert
    ICdpManager public _cdpManager;
    bytes32 public _reEnterLiqCdpId = bytes32(0); // only for _onReceiveType == 1

    event EtherReceived(address, uint);

    function setCdpManager(address _cdpMgr) external {
        _cdpManager = ICdpManager(_cdpMgr);
    }

    function setReceiveType(uint _type) external {
        _onReceiveType = _type;
    }

    function setReEnterLiqCdpId(bytes32 _cdpId) external {
        _reEnterLiqCdpId = _cdpId;
    }

    function liquidateCdp(bytes32 _troveId) external {
        _cdpManager.liquidate(_troveId);
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
        if (_onReceiveType == 1) {
            _cdpManager.liquidate(_reEnterLiqCdpId); //reenter liquidation
        } else if (_onReceiveType == 2) {
            revert("revert on receive");
        }
    }
}
