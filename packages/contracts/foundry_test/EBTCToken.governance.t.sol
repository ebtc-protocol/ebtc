// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/Dependencies/EbtcMath.sol";
import {eBTCBaseFixture} from "./BaseFixture.sol";

/*
 * Test suite that tests opened CDPs with two different operations: repayDebt and withdrawDebt
 * Test include testing different metrics such as each CDP ICR, also TCR changes after operations are executed
 */
contract EBTCTokenGovernanceTest is eBTCBaseFixture {
    // Storage array of cdpIDs when impossible to calculate array size
    bytes32[] cdpIds;
    uint256 public mintAmount = 1e18;

    function setUp() public override {
        eBTCBaseFixture.setUp();

        eBTCBaseFixture.connectCoreContracts();
        eBTCBaseFixture.connectLQTYContractsToCore();
    }

    // -------- eBTC Minting governance cases --------

    function testEBTCUserWithoutMintingPermisionCannotMint() public {
        address user = _utils.getNextUserAddress();

        vm.startPrank(user);
        vm.deal(user, type(uint96).max);
        vm.expectRevert("EBTC: Caller is neither BorrowerOperations nor CdpManager nor authorized");
        eBTCToken.mint(user, mintAmount);
        vm.stopPrank();
    }

    function testEBTCUserWithMintingPermisionCanMint() public {
        // TODO: add additional Fuzz by user, address minted to, and mint amount
        address user = _utils.getNextUserAddress();

        // Grant mint permissions to user
        vm.prank(defaultGovernance);
        authority.setUserRole(user, 1, true);

        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(user);

        // User mints
        vm.startPrank(user);
        vm.deal(user, type(uint96).max);

        eBTCToken.mint(user, mintAmount);

        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(user);

        assertEq(totalSupply1 - totalSupply0, mintAmount);
        assertEq(balanceOfUser1 - balanceOfUser0, mintAmount);

        // Ensure arbitrary user still cannot mint
        address secondUser = _utils.getNextUserAddress();
        uint256 balanceOfSecondUser1 = eBTCToken.balanceOf(secondUser);

        vm.startPrank(secondUser);
        vm.deal(secondUser, type(uint96).max);

        vm.expectRevert("EBTC: Caller is neither BorrowerOperations nor CdpManager nor authorized");
        eBTCToken.mint(secondUser, mintAmount);

        vm.stopPrank();

        uint256 totalSupply2 = eBTCToken.totalSupply();
        uint256 balanceOfUser2 = eBTCToken.balanceOf(user);
        uint256 balanceOfSecondUser2 = eBTCToken.balanceOf(secondUser);

        assertEq(totalSupply2, totalSupply1);
        assertEq(balanceOfUser2, balanceOfUser1);
        assertEq(balanceOfSecondUser2, balanceOfSecondUser1);
    }

    // -------- eBTC Burning governance cases --------

    function testEBTCUserWithoutBurningPermisionCannotBurn() public {
        address user = _utils.getNextUserAddress();

        // @dev burn call will fail on permission level before we get to actually decrementing balance
        vm.prank(defaultGovernance);
        eBTCToken.mint(user, mintAmount);

        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(user);

        vm.startPrank(user);

        // Attempt to burn fails
        vm.expectRevert("EBTC: Caller is neither BorrowerOperations nor CdpManager nor authorized");
        eBTCToken.burn(user, mintAmount);

        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(user);

        assertEq(totalSupply1 - totalSupply0, 0);
        assertEq(balanceOfUser1 - balanceOfUser0, 0);
    }

    function testEBTCUserWithBurningPermisionCanBurn() public {
        address user = _utils.getNextUserAddress();

        // Grant user burning permissions
        vm.startPrank(defaultGovernance);
        eBTCToken.mint(user, mintAmount);
        authority.setUserRole(user, 2, true);
        vm.stopPrank();

        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(user);

        vm.startPrank(user);

        // Burn succeeds
        eBTCToken.burn(user, mintAmount);

        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(user);

        assertEq(totalSupply0 - totalSupply1, mintAmount);
        assertEq(balanceOfUser0 - balanceOfUser1, mintAmount);
    }

    function testEBTCUserWithBurningPermisionCanBurnWithoutAddress() public {
        address user = _utils.getNextUserAddress();

        // Grant user burning permissions
        vm.startPrank(defaultGovernance);
        eBTCToken.mint(user, mintAmount);
        authority.setUserRole(user, 2, true);
        vm.stopPrank();

        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(user);

        vm.startPrank(user);

        // Burn succeeds
        eBTCToken.burn(mintAmount);

        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(user);

        assertEq(totalSupply0 - totalSupply1, mintAmount);
        assertEq(balanceOfUser0 - balanceOfUser1, mintAmount);
    }

    /// @dev Normal minting via CDP opening should work even when authority is bricked
    function testCdpManagerMintWorksWhenAuthorityBricked() public {
        // TODO
    }

    /// @dev Normal burning via CDP closing should work even when authority is bricked
    function testCdpManagerBurnWorksWhenAuthorityBricked() public {
        // TODO
    }

    // TODO: Remove minting and burning rights from CDPManager when cont. interest is removed.

    /// @dev ensure mint invariants are maintained on successful mint operation
    /// @dev totalSupply changes as expected
    /// @dev mint recipient balance changes as expected
    function _mintMacro(address minter, address recipient, uint256 amount) internal {
        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(recipient);

        vm.startPrank(minter);
        eBTCToken.mint(recipient, amount);
        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(recipient);

        assertEq(totalSupply1 - totalSupply0, amount);
        assertEq(balanceOfUser1 - balanceOfUser0, amount);
    }

    /// @dev ensure burn invariants are maintained on successful burn operation
    /// @dev totalSupply changes as expected
    /// @dev mint recipient balance changes as expected
    function _burnMacro(address minter, address recipient, uint256 amount) internal {
        uint256 totalSupply0 = eBTCToken.totalSupply();
        uint256 balanceOfUser0 = eBTCToken.balanceOf(recipient);

        vm.startPrank(minter);
        eBTCToken.mint(recipient, amount);
        vm.stopPrank();

        uint256 totalSupply1 = eBTCToken.totalSupply();
        uint256 balanceOfUser1 = eBTCToken.balanceOf(recipient);

        assertEq(totalSupply0 - totalSupply1, mintAmount);
        assertEq(balanceOfUser0 - balanceOfUser1, mintAmount);
    }
}
