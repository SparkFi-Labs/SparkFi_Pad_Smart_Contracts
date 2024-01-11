pragma solidity ^0.8.0;

interface IRouter {
  function swapLocal(
    address to,
    uint256 amount,
    address sourcePoolId,
    uint256 destinationChain,
    address destinationPoolId
  ) external payable;

  function swapRemote(
    address to,
    uint256 amount,
    address localPoolId,
    uint256 sourceChainId,
    address sourcePoolId
  ) external;

  function addLiquidity(address poolId, uint256 amount) external;

  function creditChainPath(
    address localPoolId,
    uint256 destinationChain,
    address destinationPoolId,
    uint256 amount
  ) external;

  function removeCreditLocal(
    address localPoolId,
    uint256 destinationChain,
    address destinationPoolId,
    uint256 amount
  ) external;

  function removeCreditRemote(
    address localPoolId,
    uint256 sourceChainId,
    address sourcePoolId,
    uint256 amount
  ) external;

  function createPool(
    address token,
    string memory name,
    string memory symbol,
    address feeTaker,
    address feeRewardLibrary,
    uint256 sharedDecimals,
    uint256 localDecimals
  ) external returns (address);
}
