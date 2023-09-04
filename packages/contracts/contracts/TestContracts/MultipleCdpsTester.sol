pragma solidity 0.8.17;

interface IBorrowerOperations {
    function openCdp(
        uint256 _maxFeePercentage,
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable;
}

interface ISortedCdps {
    function cdpOfOwnerByIndex(address owner, uint256 index) external view returns (bytes32);

    function dummyId() external returns (bytes32);
}

contract MultipleCdpsTester {
    IBorrowerOperations public borrowerOperations;
    ISortedCdps public sortedCdps;
    bytes32 _dummyId;

    event CdpOpened(bytes32 _cdpId);

    function initiate(address _bo, address _st) external {
        borrowerOperations = IBorrowerOperations(_bo);
        sortedCdps = ISortedCdps(_st);
        _dummyId = sortedCdps.dummyId();
    }

    function openCdps(
        uint256 _count,
        uint256 _maxFeePercentage,
        uint256 _EBTCAmount,
        bytes32 _upperHint,
        bytes32 _lowerHint
    ) external payable {
        uint256 _idx;
        for (; _idx < _count; ) {
            uint256 _singleCol = msg.value / _count;
            require(_singleCol > 0, "!msgVal");
            borrowerOperations.openCdp{value: _singleCol}(
                _maxFeePercentage,
                _EBTCAmount,
                _upperHint,
                _lowerHint
            );
            bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(this), _idx);
            require(_cdpId != _dummyId, "!cdpId");
            emit CdpOpened(_cdpId);
            _idx++;
        }
    }
}
