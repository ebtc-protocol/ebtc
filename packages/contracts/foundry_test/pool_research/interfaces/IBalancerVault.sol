// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import {IAsset} from "./IAsset.sol";

interface IBalancerVault {
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT
    }

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    event AuthorizerChanged(address indexed newAuthorizer);
    event ExternalBalanceTransfer(
        address indexed token,
        address indexed sender,
        address recipient,
        uint256 amount
    );
    event FlashLoan(
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 feeAmount
    );
    event InternalBalanceChanged(address indexed user, address indexed token, int256 delta);
    event PausedStateChanged(bool paused);
    event PoolBalanceChanged(
        bytes32 indexed poolId,
        address indexed liquidityProvider,
        address[] tokens,
        int256[] deltas,
        uint256[] protocolFeeAmounts
    );
    event PoolBalanceManaged(
        bytes32 indexed poolId,
        address indexed assetManager,
        address indexed token,
        int256 cashDelta,
        int256 managedDelta
    );
    event PoolRegistered(bytes32 indexed poolId, address indexed poolAddress, uint8 specialization);
    event RelayerApprovalChanged(address indexed relayer, address indexed sender, bool approved);
    event Swap(
        bytes32 indexed poolId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokensDeregistered(bytes32 indexed poolId, address[] tokens);
    event TokensRegistered(bytes32 indexed poolId, address[] tokens, address[] assetManagers);

    function WETH() external view returns (address);

    function batchSwap(
        uint8 kind,
        IVault.BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        IVault.FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory assetDeltas);

    function deregisterTokens(bytes32 poolId, address[] memory tokens) external;

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request
    ) external;

    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;

    function getActionId(bytes4 selector) external view returns (bytes32);

    function getAuthorizer() external view returns (address);

    function getDomainSeparator() external view returns (bytes32);

    function getInternalBalance(
        address user,
        address[] memory tokens
    ) external view returns (uint256[] memory balances);

    function getNextNonce(address user) external view returns (uint256);

    function getPausedState()
        external
        view
        returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);

    function getPool(bytes32 poolId) external view returns (address, uint8);

    function getPoolTokenInfo(
        bytes32 poolId,
        address token
    )
        external
        view
        returns (uint256 cash, uint256 managed, uint256 lastChangeBlock, address assetManager);

    function getPoolTokens(
        bytes32 poolId
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    function getProtocolFeesCollector() external view returns (address);

    function hasApprovedRelayer(address user, address relayer) external view returns (bool);

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request
    ) external payable;

    function managePoolBalance(IVault.PoolBalanceOp[] memory ops) external;

    function manageUserBalance(IVault.UserBalanceOp[] memory ops) external payable;

    function queryBatchSwap(
        uint8 kind,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        IVault.FundManagement memory funds
    ) external returns (int256[] memory);

    function registerPool(uint8 specialization) external returns (bytes32);

    function registerTokens(
        bytes32 poolId,
        address[] memory tokens,
        address[] memory assetManagers
    ) external;

    function setAuthorizer(address newAuthorizer) external;

    function setPaused(bool paused) external;

    function setRelayerApproval(address sender, address relayer, bool approved) external;

    function swap(
        IVault.SingleSwap memory singleSwap,
        IVault.FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256 amountCalculated);

    receive() external payable;
}

interface IVault {
    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct PoolBalanceOp {
        uint8 kind;
        bytes32 poolId;
        address token;
        uint256 amount;
    }

    struct UserBalanceOp {
        uint8 kind;
        address asset;
        uint256 amount;
        address sender;
        address recipient;
    }

    struct SingleSwap {
        bytes32 poolId;
        uint8 kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }
}
