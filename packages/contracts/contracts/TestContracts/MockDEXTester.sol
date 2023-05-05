// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
pragma abicoder v2;

import "../Dependencies/IBalancerV2Vault.sol";
import "./EBTCTokenTester.sol";
import "./CollateralTokenTester.sol";

contract MockDEXTester is IBalancerV2Vault {
    // swap output slippage
    uint public slippage = 50;
    uint public constant MAX_SLIPPAGE = 10000;
    // collateral(stETH) to eBTC
    uint public price = 7428 * 1e13;

    CollateralTokenTester public collateral;
    EBTCTokenTester public ebtcToken;

    constructor(address _ebtcTester, address _collTester) {
        collateral = CollateralTokenTester(payable(_collTester));
        ebtcToken = EBTCTokenTester(ebtcToken);
    }

    function setSlippage(uint _slippage) public {
        require(_slippage < MAX_SLIPPAGE, "!max slippage");
        slippage = _slippage;
    }

    // price in decimal 18
    function setPrice(uint _price) public {
        price = _price;
    }

    // calculate output amount based on input amount, slippage and price
    function _internalSwap(bool _tradeCollForEBTC, uint256 _inputAmt) internal returns (uint256) {
        require(_inputAmt > 0, "!swap input amount");

        uint256 _outputAmt;
        if (_tradeCollForEBTC) {
            collateral.transferFrom(msg.sender, address(this), _inputAmt);
            _outputAmt = (((_inputAmt * price) / 1e18) * (MAX_SLIPPAGE - slippage)) / MAX_SLIPPAGE;
            ebtcToken.unprotectedMint(msg.sender, _outputAmt);
        } else {
            ebtcToken.transferFrom(msg.sender, address(this), _inputAmt);
            uint256 amountCalculatedInOut =
                (((_inputAmt * 1e18) / price) * (MAX_SLIPPAGE - slippage)) /
                MAX_SLIPPAGE;
            require(address(this).balance >= _outputAmt, "!not enough ether for collateral output");
            collateral.deposit{value: _outputAmt}();
            collateral.transfer(msg.sender, _outputAmt);
        }
        return _outputAmt;
    }

    //////////////////////////////////////////////////////////////////////////////////////
    // Balancer V2
    //////////////////////////////////////////////////////////////////////////////////////

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256) {
        bool _tradeCollForEBTC = singleSwap.assetIn == address(collateral) ? true : false;
        uint256 amountCalculatedInOut = _internalSwap(_tradeCollForEBTC, singleSwap.amount);

        return amountCalculatedInOut;
    }

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        FundManagement calldata funds,
        int256[] calldata limits,
        uint256 deadline
    ) external returns (int256[] memory) {
        int256[] memory assetDeltas;
        return assetDeltas;
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        FundManagement calldata funds
    ) external returns (int256[] memory) {
        int256[] memory assetDeltas;
        return assetDeltas;
    }

    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization) {
        return (address(0), PoolSpecialization.TWO_TOKEN);
    }

    function getPoolTokens(
        bytes32 poolId
    ) external view returns (address[] memory, uint256[] memory, uint256 lastChangeBlock) {
        address[] memory tokens;
        uint256[] memory balances;
        uint256 lastChangeBlock = block.timestamp;
        return (tokens, balances, lastChangeBlock);
    }
}