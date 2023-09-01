// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

abstract contract EIP712Base {
    string internal constant _VERSION = "1";

    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;

    string public immutable NAME;

    mapping(address => uint256) internal _nonces; // TODO: Bring consumer fn down

    constructor() {
        bytes32 hashedName = keccak256(bytes(NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return domainSeparator();
    }

    function domainSeparator() public view override returns (bytes32) {
        if (_chainID() == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _chainID() private view returns (uint256) {
        return block.chainid;
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 name,
        bytes32 version
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, name, version, _chainID(), address(this)));
    }

    function nonces(address _borrower) external view returns (uint256) {
        // FOR EIP 2612
        return _nonces[_borrower];
    }

    function version() external pure returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() public pure virtual returns (bytes32);
}