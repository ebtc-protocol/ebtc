pragma solidity 0.6.11;

interface ITroveManager{
    function liquidate(bytes32 _troveId) external;
    function partiallyLiquidate(bytes32 _troveId, uint256 _partialRatio) external;
}

contract SimpleLiquidationTester {

    uint public _onReceiveType;//0-nothing, 1-reenter, 2-revert
    ITroveManager public _troveManager;
	
    event EtherReceived(address, uint);
	
    function setTroveManager(address _troveMgr) external {
       _troveManager = ITroveManager(_troveMgr);
    }

    function setReceiveType(uint _type) external {
       _onReceiveType = _type;
    }

    function liquidateTrove(bytes32 _troveId) external {
       _troveManager.liquidate(_troveId);
    }

    function partiallyLiquidateTrove(bytes32 _troveId, uint256 _partialRatio) external {
       _troveManager.partiallyLiquidate(_troveId, _partialRatio);
    }
	
    receive() external payable {
       emit EtherReceived(msg.sender, msg.value);
       if (_onReceiveType == 1){
           _troveManager.liquidate(bytes32(0));//reenter liquidation
       } else if (_onReceiveType == 2){
           revert('revert on receive');
       }
    }
}