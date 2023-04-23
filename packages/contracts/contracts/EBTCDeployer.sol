// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Dependencies/Create3.sol";
import "./Dependencies/Ownable.sol";

contract EBTCDeployer is Ownable {
    string public constant name = "eBTC Deployer";

    string public constant AUTHORITY = "ebtc.v1.authority";
    string public constant LIQUIDATION_LIBRARY = "ebtc.v1.liquidationLibrary";
    string public constant CDP_MANAGER = "ebtc.v1.cdpManager";
    string public constant BORROWER_OPERATIONS = "ebtc.v1.borrowerOperations";
    
    string public constant PRICE_FEED = "ebtc.v1.priceFeed";
    string public constant SORTED_CDPS = "ebtc.v1.sortedCdps";
    
    string public constant ACTIVE_POOL = "ebtc.v1.activePool";
    string public constant GAS_POOL = "ebtc.v1.gasPool";
    string public constant DEFAULT_POOL = "ebtc.v1.defaultPool";
    string public constant COLL_SURPLUS_POOL = "ebtc.v1.collSurplusPool";

    string public constant HINT_HELPERS = "ebtc.v1.hintHelpers";
    string public constant EBTC_TOKEN = "ebtc.v1.eBTCToken";
    string public constant FEE_RECIPIENT = "ebtc.v1.feeRecipient";
    string public constant MULTI_CDP_GETTER = "ebtc.v1.multiCdpGetter";
    
    event ContractDeployed(address indexed contractAddress, string contractName, bytes32 salt);

    struct EbtcAddresses {
        address authorityAddress;
        address liquidationLibraryAddress;
        address cdpManagerAddress;
        address borrowerOperationsAddress;
        address priceFeedAddress;
        address sortedCdpsAddress;
        address activePoolAddress;
        address gasPoolAddress;
        address defaultPoolAddress;
        address collSurplusPoolAddress;
        address hintHelpersAddress;
        address ebtcTokenAddress;
        address feeRecipientAddress;
        address multiCdpGetterAddress;
    }

    /**
    @notice Helper method to return a set of future addresses for eBTC. Intended to be used in the order specified.
    
    @dev The order is as follows:
    0: authority
    1: liquidationLibrary
    2: cdpManager
    3: borrowerOperations
    4: priceFeed
    5; sortedCdps
    6: activePool
    7: gasPool
    8: defaultPool
    9: collSurplusPool
    10: hintHelpers
    11: eBTCToken
    12: feeRecipient
    13: multiCdpGetter


     */
    function getFutureEbtcAddresses() public view returns (EbtcAddresses memory) {

        EbtcAddresses memory addresses = EbtcAddresses(
          Create3.addressOf(keccak256(abi.encodePacked(AUTHORITY))),
          Create3.addressOf(keccak256(abi.encodePacked(LIQUIDATION_LIBRARY))),
          Create3.addressOf(keccak256(abi.encodePacked(CDP_MANAGER))),
          Create3.addressOf(keccak256(abi.encodePacked(BORROWER_OPERATIONS))),
          Create3.addressOf(keccak256(abi.encodePacked(PRICE_FEED))),
          Create3.addressOf(keccak256(abi.encodePacked(SORTED_CDPS))),
          Create3.addressOf(keccak256(abi.encodePacked(ACTIVE_POOL))),
          Create3.addressOf(keccak256(abi.encodePacked(GAS_POOL))),
          Create3.addressOf(keccak256(abi.encodePacked(DEFAULT_POOL))),
          Create3.addressOf(keccak256(abi.encodePacked(COLL_SURPLUS_POOL))),
          Create3.addressOf(keccak256(abi.encodePacked(HINT_HELPERS))),
          Create3.addressOf(keccak256(abi.encodePacked(EBTC_TOKEN))),
          Create3.addressOf(keccak256(abi.encodePacked(FEE_RECIPIENT))),
          Create3.addressOf(keccak256(abi.encodePacked(MULTI_CDP_GETTER)))
        );

        // address[] memory addresses = new address[](14);
        // bytes32 salt = keccak256(abi.encodePacked(abi.encodePacked(msg.sender)));
        // addresses[0] = Create3.addressOf(keccak256(abi.encodePacked(AUTHORITY))); 
        // addresses[1] = Create3.addressOf(keccak256(abi.encodePacked(LIQUIDATION_LIBRARY)));
        // addresses[2] = Create3.addressOf(keccak256(abi.encodePacked(CDP_MANAGER)));
        // addresses[3] = Create3.addressOf(keccak256(abi.encodePacked(BORROWER_OPERATIONS)));
        // addresses[4] = Create3.addressOf(keccak256(abi.encodePacked(PRICE_FEED)));
        // addresses[5] = Create3.addressOf(keccak256(abi.encodePacked(SORTED_CDPS)));
        // addresses[6] = Create3.addressOf(keccak256(abi.encodePacked(ACTIVE_POOl)));
        // addresses[7] = Create3.addressOf(keccak256(abi.encodePacked(GAS_POOL)));
        // addresses[8] = Create3.addressOf(keccak256(abi.encodePacked(DEFAULT_POOL)));
        // addresses[9] = Create3.addressOf(keccak256(abi.encodePacked(COLL_SURPLUS_POOL)));
        // addresses[10] = Create3.addressOf(keccak256(abi.encodePacked(HINT_HELPERS)));
        // addresses[11] = Create3.addressOf(keccak256(abi.encodePacked(EBTC_TOKEN)));
        // addresses[12] = Create3.addressOf(keccak256(abi.encodePacked(FEE_RECIPIENT)));
        // addresses[13] = Create3.addressOf(keccak256(abi.encodePacked(MULTI_CDP_GETTER)));
        return addresses;
    }

    /**
        @notice Deploy a contract using salt in string format and arbitrary runtime code.
        @dev Intended use is: get the future eBTC addresses, then deploy the appropriate contract to each address via this method, building the constructor using the mapped addresses
        @dev no enforcment of bytecode at address as we can't know the runtime code in this contract due to space constraints
        @dev gated to given deployer EOA to ensure no interference with process, given proper actions by deployer
     */
    function deploy(string memory _saltString, bytes memory _creationCode) external returns (address deployedAddress) {
        bytes32 _salt = keccak256(abi.encodePacked(_saltString));
        deployedAddress = Create3.create3(_salt, _creationCode);
        emit ContractDeployed(deployedAddress, _saltString, _salt );
    }

    function addressOf(string memory _saltString) external view returns (address) {
      bytes32 _salt = keccak256(abi.encodePacked(_saltString));
        return Create3.addressOf(_salt);
    }

    function addressOfSalt(bytes32 _salt) external view returns (address) {
        return Create3.addressOf(_salt);
    }

    /**
        @notice Create the creation code for a contract with the given runtime code.
        @dev credit: https://github.com/0xsequence/create3/blob/master/contracts/test_utils/Create3Imp.sol
     */
    function creationCodeFor(bytes memory _code) internal pure returns (bytes memory) {
    /*
      0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
      0x01    0x80         0x80        DUP1                size size
      0x02    0x60         0x600e      PUSH1 14            14 size size
      0x03    0x60         0x6000      PUSH1 00            0 14 size size
      0x04    0x39         0x39        CODECOPY            size
      0x05    0x60         0x6000      PUSH1 00            0 size
      0x06    0xf3         0xf3        RETURN
      <CODE>
    */

    return abi.encodePacked(
      hex"63",
      uint32(_code.length),
      hex"80_60_0E_60_00_39_60_00_F3",
      _code
    );
  }
}
