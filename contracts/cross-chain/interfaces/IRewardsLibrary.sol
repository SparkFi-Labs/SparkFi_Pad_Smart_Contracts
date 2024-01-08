pragma solidity ^0.8.0;

interface IRewardsLibrary {
  function getReward(
    address,
    address,
    uint256
  ) external view returns (uint256);
}
