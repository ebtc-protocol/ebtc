pragma solidity ^0.8.0;
import {ITokenMock} from "@crytic/properties/contracts/ERC20/external/util/ITokenMock.sol";
import {CryticERC20ExternalBasicProperties} from "@crytic/properties/contracts/ERC20/external/properties/ERC20ExternalBasicProperties.sol";
import {PropertiesConstants} from "@crytic/properties/contracts/util/PropertiesConstants.sol";
import "../../CollateralTokenTester.sol";

contract EchidnaCollateralTokenTester is CryticERC20ExternalBasicProperties {
    uint256 private constant MAX_REBASE_PERCENT = 1.1e18;

    constructor() payable {
        // Deploy ERC20
        token = ITokenMock(address(new CryticTokenMock(4 * INITIAL_BALANCE)));
        CollateralTokenTester(payable(address(token))).deposit{value: 4 * INITIAL_BALANCE}();
        token.transfer(USER1, INITIAL_BALANCE);
        token.transfer(USER2, INITIAL_BALANCE);
        token.transfer(USER3, INITIAL_BALANCE);
    }

    function setEthPerShare(uint256 _newEthPerShare) external {
        CollateralTokenTester collateral = CollateralTokenTester(payable(address(token)));
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = clampBetween(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1e18
        );
        collateral.setEthPerShare(_newEthPerShare);
    }
}

contract CryticTokenMock is CollateralTokenTester, PropertiesConstants {
    bool public isMintableOrBurnable;
    uint256 public initialSupply;
    event Log(string, uint256);

    constructor(uint256 _initialSupply) {
        initialSupply = _initialSupply;
        isMintableOrBurnable = true;
    }
}
