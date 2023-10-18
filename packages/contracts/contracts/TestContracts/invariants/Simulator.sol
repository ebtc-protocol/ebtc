pragma solidity 0.8.17;

import {BorrowerOperations} from "../../BorrowerOperations.sol";
import {CdpManager} from "../../CdpManager.sol";
import {SortedCdps} from "../../SortedCdps.sol";
import {Actor} from "./Actor.sol";

contract Simulator {
    uint256 public constant TRUE = uint256(keccak256(abi.encodePacked("TRUE")));
    event Log(string);

    Actor[] private actors;
    CdpManager private cdpManager;
    SortedCdps private sortedCdps;
    BorrowerOperations private borrowerOperations;

    constructor(
        Actor[] memory _actors,
        CdpManager _cdpManager,
        SortedCdps _sortedCdps,
        BorrowerOperations _borrowerOperations
    ) {
        actors = _actors;
        cdpManager = _cdpManager;
        sortedCdps = _sortedCdps;
        borrowerOperations = _borrowerOperations;
    }

    function simulateRepayEverythingAndCloseCdps() external {
        bool success;

        bytes32 currentCdp = sortedCdps.getFirst();
        while (currentCdp != bytes32(0) && sortedCdps.getSize() > 1) {
            Actor actor = Actor(payable(sortedCdps.getOwnerAddress(currentCdp)));
            (uint256 entireDebt, ) = cdpManager.getSyncedDebtAndCollShares(currentCdp);

            (success, ) = actor.proxy(
                address(borrowerOperations),
                abi.encodeWithSelector(BorrowerOperations.closeCdp.selector, currentCdp)
            );
            require(success);

            currentCdp = sortedCdps.getNext(currentCdp);
        }

        _success();
    }

    function _success() private {
        uint256 ans = TRUE;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, ans)
            revert(ptr, 32)
        }
    }
}
