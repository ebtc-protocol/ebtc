pragma solidity 0.6.11;

interface IBorrowerOperations{
    function openTrove(uint _maxFeePercentage, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external payable;
}
interface ISortedTroves{
    function cdpOfOwnerByIndex(address owner, uint256 index) external view returns (bytes32);
    function dummyId() external returns (bytes32);
}

contract MultipleTrovesTester {
    
    IBorrowerOperations public borrowerOperations;	
    ISortedTroves public sortedTroves;	
    bytes32 _dummyId;
	
    event TroveOpened(bytes32 _cdpId);

    function initiate(address _bo, address _st) external{
        borrowerOperations = IBorrowerOperations(_bo);
        sortedTroves = ISortedTroves(_st);
        _dummyId = sortedTroves.dummyId();
    }

    function openTroves(uint256 _count, uint _maxFeePercentage, uint _EBTCAmount, bytes32 _upperHint, bytes32 _lowerHint) external payable{
        uint256 _idx;
        for (;_idx < _count;){
             uint256 _singleCol = msg.value / _count;
             require(_singleCol > 0, '!msgVal');
             borrowerOperations.openTrove{value: _singleCol}(_maxFeePercentage, _EBTCAmount, _upperHint, _lowerHint);
             bytes32 _cdpId = sortedTroves.cdpOfOwnerByIndex(address(this), _idx);
             require(_cdpId != _dummyId, '!cdpId');
             emit TroveOpened(_cdpId);
             _idx++;
        }		
    }
}