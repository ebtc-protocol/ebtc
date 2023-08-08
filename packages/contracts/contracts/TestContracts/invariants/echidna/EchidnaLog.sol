pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaLog is EchidnaBaseTester {
    event Log(string, uint256);

    modifier log() {
        uint256 price = priceFeedTestnet.getPrice();
        uint256 coll = cdpManager.getEntireSystemColl();
        uint256 debt = cdpManager.getEntireSystemDebt();

        emit Log("Price", price);
        emit Log("TCR", cdpManager.getTCR(price));
        emit Log("ICR", cdpManager.getCurrentICR(sortedCdps.getFirst(), price));
        emit Log("C", coll);
        emit Log("U", collateral.getPooledEthByShares(coll));
        emit Log("D", debt);
        emit Log("RecoveryMode", cdpManager.checkRecoveryMode(price) ? 1 : 0);
        emit Log("EthPerShare", collateral.getEthPerShare());
        _;
    }
}
