// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/EbtcFeed.sol";
import "../contracts/Interfaces/IOracleCaller.sol";
import "../contracts/TestContracts/MockAlwaysTrueAuthority.sol";

contract MockCLCaller is IPriceFetcher {
    uint256 public getLatestPrice;

    function setPrice(uint256 newPrice) external {
        getLatestPrice = newPrice;
    }

    function fetchPrice() external returns (uint256) {
        return getLatestPrice;
    }
}

contract ScamRevertBomb {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    function toggleAttack() external {
        attack = !attack;
    }

    function revBytes(uint256 _bytes) internal pure {
        assembly {
            revert(0, _bytes)
        }
    }

    function getLatestPrice() external view returns (uint256) {
        if (!attack) {
            return DEFAULT_GOOD_PRICE;
        } else {
            revBytes(2_000_000);
        }
    }
}

contract ScamReturnBomb {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    function toggleAttack() external {
        attack = !attack;
    }

    function retBytes(uint256 _bytes) public pure {
        assembly {
            return(0, _bytes)
        }
    }

    function getLatestPrice() external view returns (uint256) {
        if (!attack) {
            return DEFAULT_GOOD_PRICE;
        } else {
            retBytes(2_000_000);
        }
    }
}

contract ScamReturnBytes {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    function toggleAttack() external {
        attack = !attack;
    }

    function getLatestPrice() external view returns (bytes memory) {
        if (!attack) {
            return abi.encode(DEFAULT_GOOD_PRICE);
        } else {
            uint256[] memory entries = new uint256[](250);
            return abi.encode(entries);
        }
    }
}

contract ScamRevertWithCustomError {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    error InvalidAddress();

    function toggleAttack() external {
        attack = !attack;
    }

    function getLatestPrice() external view returns (uint256) {
        if (!attack) {
            return DEFAULT_GOOD_PRICE;
        } else {
            revert InvalidAddress();
        }
    }
}

contract ScamRevertWithCustomErrorAndParam {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    error InvalidNumber(uint224);

    function toggleAttack() external {
        attack = !attack;
    }

    function getLatestPrice() external view returns (uint256) {
        if (!attack) {
            return DEFAULT_GOOD_PRICE;
        } else {
            revert InvalidNumber(12346);
        }
    }
}

contract ScamBurnAllGas {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    function toggleAttack() external {
        attack = !attack;
    }

    function getLatestPrice() external view returns (uint256) {
        if (!attack) {
            return DEFAULT_GOOD_PRICE;
        } else {
            uint256 counter;
            while (true) {
                counter += 1;
            }
        }
    }
}

contract ScamSelfDestruct {
    uint256 DEFAULT_GOOD_PRICE = 1e18;

    bool public attack;

    uint256 counter;

    function toggleAttack() external {
        selfdestruct(payable(msg.sender)); // LOL
    }

    function getLatestPrice() external view returns (uint256) {
        return DEFAULT_GOOD_PRICE;
    }
}

/**
  List of attacks we test for our oracle reader
    - Return Bomb
    - Revert Bomb
    - Return Bytes
    - Burn all gas
    - Contract doesn't exist
*/

contract EbtcFeedUnit is Test {
    MockCLCaller mockCl;
    EbtcFeed feed;
    MockAlwaysTrueAuthority internal authority;

    function setUp() public {
        authority = new MockAlwaysTrueAuthority();
        mockCl = new MockCLCaller();
        mockCl.setPrice(123);
        feed = new EbtcFeed(address(authority), address(mockCl), address(0));
    }

    function testTinfoilCalls(uint256 price) public {
        if (price == 0) {
            price = 1;
        }
        mockCl.setPrice(price);
        assertEq(mockCl.getLatestPrice(), price, "Mock CL has bug");

        assertEq(feed.fetchPrice(), price, "Feed and CL Match");
    }

    /**
      ScamRevertBomb
      ScamReturnBomb
      ScamReturnBytes
      ScamBurnAllGas
      ScamSelfDestruct
     */
    function testScamRevertBomb() public {
        ScamRevertBomb revertBomb = new ScamRevertBomb();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(revertBomb), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        revertBomb.toggleAttack();
        uint256 outcomeAttack = feed.tinfoilCall(address(revertBomb), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamReturnBomb() public {
        ScamReturnBomb returnBomb = new ScamReturnBomb();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(returnBomb), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        returnBomb.toggleAttack();
        uint256 outcomeAttack = feed.tinfoilCall(address(returnBomb), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamReturnBytes() public {
        ScamReturnBytes returnBytes = new ScamReturnBytes();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(returnBytes), oracleRequestCalldata);
        assertTrue(outcome == 0, "Is Zero"); // Since it's bytes it's always invalid

        // Revert Case
        returnBytes.toggleAttack();
        uint256 outcomeAttack = feed.tinfoilCall(address(returnBytes), oracleRequestCalldata);
        console2.log("outcomeAttack", outcomeAttack);
        // Fails, because it returns 32 which is the length of the array
        // NOTE: We could add a check to prevent even that level of griefing
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamBurnAllGas() public {
        ScamBurnAllGas burnAllGas = new ScamBurnAllGas();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(burnAllGas), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        burnAllGas.toggleAttack();
        uint256 outcomeAttack = feed.tinfoilCall(address(burnAllGas), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamSelfDestruct() public {
        ScamSelfDestruct selfDestructor = new ScamSelfDestruct();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(selfDestructor), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        selfDestructor.toggleAttack();

        // NOTE: Foundry doesn't allow to test selfdestruct
        // For this reason we test this way
        uint256 outcomeAttack = feed.tinfoilCall(address(123), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamCustomError() public {
        ScamRevertWithCustomError scamCustomError = new ScamRevertWithCustomError();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(scamCustomError), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        scamCustomError.toggleAttack();

        // NOTE: Foundry doesn't allow to test selfdestruct
        // For this reason we test this way
        uint256 outcomeAttack = feed.tinfoilCall(address(scamCustomError), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }

    function testScamCustomErrorWith32Length() public {
        ScamRevertWithCustomErrorAndParam scamCustomError = new ScamRevertWithCustomErrorAndParam();
        bytes memory oracleRequestCalldata = abi.encodeCall(IOracleCaller.getLatestPrice, ());

        // Normal Case
        uint256 outcome = feed.tinfoilCall(address(scamCustomError), oracleRequestCalldata);
        assertTrue(outcome != 0, "Not Zero");

        // Revert Case
        scamCustomError.toggleAttack();

        // NOTE: Foundry doesn't allow to test selfdestruct
        // For this reason we test this way
        uint256 outcomeAttack = feed.tinfoilCall(address(scamCustomError), oracleRequestCalldata);
        assertTrue(outcomeAttack == 0, "Is Zero");
    }
}
