pragma solidity 0.8.17;

import {EchidnaBaseTester} from "./EchidnaBaseTester.sol";

abstract contract EchidnaLog is EchidnaBaseTester {
    event Log(string, uint256);

    modifier log() {
        {
            uint256 price = priceFeedTestnet.getPrice();

            emit Log("Price", price);
            emit Log("EthPerShare", collateral.getEthPerShare());
            emit Log("TCR", cdpManager.getTCR(price));
            emit Log("TC", cdpManager.getEntireSystemColl());
            emit Log("TU", collateral.getPooledEthByShares(cdpManager.getEntireSystemColl()));
            emit Log("TD", cdpManager.getEntireSystemDebt());
            emit Log("ICR(first)", cdpManager.getCurrentICR(sortedCdps.getFirst(), price));
            emit Log("ICR(last)", cdpManager.getCurrentICR(sortedCdps.getLast(), price));
        }
        _;
    }
}
