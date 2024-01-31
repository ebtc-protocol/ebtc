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
    string public constant EBTC_FEED = "ebtc.v1.ebtcFeed";
    string public constant SORTED_CDPS = "ebtc.v1.sortedCdps";

    string public constant ACTIVE_POOL = "ebtc.v1.activePool";
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
        address collSurplusPoolAddress;
        address hintHelpersAddress;
        address ebtcTokenAddress;
        address feeRecipientAddress;
        address multiCdpGetterAddress;
        address ebtcFeedAddress;
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
    7: collSurplusPool
    8: hintHelpers
    9: eBTCToken
    10: feeRecipient
    11: multiCdpGetter
    12: ebtcFeed


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
            Create3.addressOf(keccak256(abi.encodePacked(COLL_SURPLUS_POOL))),
            Create3.addressOf(keccak256(abi.encodePacked(HINT_HELPERS))),
            Create3.addressOf(keccak256(abi.encodePacked(EBTC_TOKEN))),
            Create3.addressOf(keccak256(abi.encodePacked(FEE_RECIPIENT))),
            Create3.addressOf(keccak256(abi.encodePacked(MULTI_CDP_GETTER))),
            Create3.addressOf(keccak256(abi.encodePacked(EBTC_FEED)))
        );

        return addresses;
    }

    /**
        @notice Deploy a contract using salt in string format and arbitrary runtime code.
        @dev Intended use is: get the future eBTC addresses, then deploy the appropriate contract to each address via this method, building the constructor using the mapped addresses
        @dev no enforcment of bytecode at address as we can't know the runtime code in this contract due to space constraints
        @dev gated to given deployer EOA to ensure no interference with process, given proper actions by deployer
     */
    function deploy(
        string memory _saltString,
        bytes memory _creationCode
    ) public returns (address deployedAddress) {
        bytes32 _salt = keccak256(abi.encodePacked(_saltString));
        deployedAddress = Create3.create3(_salt, _creationCode);
        emit ContractDeployed(deployedAddress, _saltString, _salt);
    }

    function deployWithCreationCodeAndConstructorArgs(
        string memory _saltString,
        bytes memory creationCode,
        bytes memory constructionArgs
    ) external returns (address) {
        bytes memory _data = abi.encodePacked(creationCode, constructionArgs);
        return deploy(_saltString, _data);
    }

    function deployWithCreationCode(
        string memory _saltString,
        bytes memory creationCode
    ) external returns (address) {
        return deploy(_saltString, creationCode);
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

        return
            abi.encodePacked(hex"63", uint32(_code.length), hex"80_60_0E_60_00_39_60_00_F3", _code);
    }
}
