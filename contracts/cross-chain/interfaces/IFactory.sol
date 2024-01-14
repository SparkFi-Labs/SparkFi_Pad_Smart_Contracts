pragma solidity ^0.8.0;

interface IFactory {
  function createPool(
    string memory _name,
    string memory _symbol,
    address _poolToken,
    address _feeTaker,
    address _feeRewardLibrary,
    uint256 _sharedDecimals,
    uint256 _localDecimals
  ) external returns (address);

  function allPoolsLength() external view returns (uint256);
}
