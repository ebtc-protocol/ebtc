// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Interfaces/IEBTCToken.sol";

import "./Dependencies/AuthNoOwner.sol";

/*
 *
 * Based upon OpenZeppelin's ERC20 contract:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
 *
 * and their EIP2612 (ERC20Permit / ERC712) functionality:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol
 *
 *
 * --- Functionality added specific to the EBTCToken ---
 *
 * 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity contracts) in external
 * transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending EBTC directly to a Liquity
 * core contract, when they should rather call the right function.
 */

contract EBTCToken is IEBTCToken, AuthNoOwner {
    uint256 private _totalSupply;
    string internal constant _NAME = "EBTC Stablecoin";
    string internal constant _SYMBOL = "EBTC";
    string internal constant _VERSION = "1";
    uint8 internal constant _DECIMALS = 18;

    // --- Data for EIP2612 ---

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;

    mapping(address => uint256) private _nonces;

    // User data for EBTC token
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // --- Addresses ---
    address public immutable cdpManagerAddress;
    address public immutable borrowerOperationsAddress;

    constructor(
        address _cdpManagerAddress,
        address _borrowerOperationsAddress,
        address _authorityAddress
    ) {
        _initializeAuthority(_authorityAddress);

        cdpManagerAddress = _cdpManagerAddress;
        emit CdpManagerAddressChanged(_cdpManagerAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);

        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, hashedName, hashedVersion);
    }

    // --- Functions for intra-Liquity calls ---

    /**
     * @notice Mint new tokens
     * @dev Internal system function - only callable by BorrowerOperations or CDPManager
     * @dev Governance can also expand the list of approved minters to enable other systems to mint tokens
     * @param _account The address to receive the newly minted tokens
     * @param _amount The amount of tokens to mint
     */
    function mint(address _account, uint256 _amount) external override {
        _requireCallerIsBOorCdpMOrAuth();
        _mint(_account, _amount);
    }

    /**
     * @notice Burn existing tokens
     * @dev Internal system function - only callable by BorrowerOperations or CDPManager
     * @dev Governance can also expand the list of approved burners to enable other systems to burn tokens
     * @param _account The address to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _account, uint256 _amount) external override {
        _requireCallerIsBOorCdpMOrAuth();
        _burn(_account, _amount);
    }

    // --- External functions ---

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _requireValidRecipient(recipient);
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _requireValidRecipient(recipient);
        _transfer(sender, recipient, amount);

        uint256 cachedAllowances = _allowances[sender][msg.sender];
        require(cachedAllowances >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, cachedAllowances - amount);
        }
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external override returns (bool) {
        uint256 cachedAllowances = _allowances[msg.sender][spender];
        require(cachedAllowances >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(msg.sender, spender, cachedAllowances - subtractedValue);
        }
        return true;
    }

    // --- EIP 2612 Functionality (https://eips.ethereum.org/EIPS/eip-2612) ---

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

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "EBTC: expired deadline");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(
                    abi.encode(_PERMIT_TYPEHASH, owner, spender, amount, _nonces[owner]++, deadline)
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, "EBTC: invalid signature");
        _approve(owner, spender, amount);
    }

    function nonces(address owner) external view override returns (uint256) {
        // FOR EIP 2612
        return _nonces[owner];
    }

    // --- Internal operations ---

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

    // --- Internal operations ---
    // Warning: sanity checks (for sender and recipient) should have been done before calling these internal functions

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "EBTCToken: zero sender!");
        require(recipient != address(0), "EBTCToken: zero recipient!");

        uint256 cachedSenderBalances = _balances[sender];
        require(cachedSenderBalances >= amount, "ERC20: transfer amount exceeds balance");

        unchecked {
            // Safe because of the check above
            _balances[sender] = cachedSenderBalances - amount;
        }

        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "EBTCToken: mint to zero recipient!");

        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "EBTCToken: burn from zero account!");

        uint256 cachedBalance = _balances[account];
        require(cachedBalance >= amount, "ERC20: burn amount exceeds balance");

        unchecked {
            // Safe because of the check above
            _balances[account] = cachedBalance - amount;
        }

        _totalSupply = _totalSupply - amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "EBTCToken: zero approve owner!");
        require(spender != address(0), "EBTCToken: zero approve spender!");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // --- 'require' functions ---

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && _recipient != address(this),
            "EBTC: Cannot transfer tokens directly to the EBTC token contract or the zero address"
        );
        require(
            _recipient != cdpManagerAddress && _recipient != borrowerOperationsAddress,
            "EBTC: Cannot transfer tokens directly to the CdpManager or BorrowerOps"
        );
    }

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "EBTCToken: Caller is not BorrowerOperations"
        );
    }

    /// @dev authority check last to short-circuit in the case of use by usual immutable addresses
    function _requireCallerIsBOorCdpMOrAuth() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == cdpManagerAddress ||
                isAuthorized(msg.sender, msg.sig),
            "EBTC: Caller is neither BorrowerOperations nor CdpManager nor authorized"
        );
    }

    function _requireCallerIsCdpM() internal view {
        require(msg.sender == cdpManagerAddress, "EBTC: Caller is not CdpManager");
    }

    // --- Optional functions ---

    function name() external pure override returns (string memory) {
        return _NAME;
    }

    function symbol() external pure override returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    function version() external pure override returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() external pure override returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }
}
