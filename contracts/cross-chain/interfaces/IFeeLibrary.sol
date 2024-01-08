pragma solidity ^0.8.0;

import "../Pool.sol";

interface IFeeLibrary {
  function getFees(uint256 amount) external view returns (Pool.SwapMessage memory);
}
