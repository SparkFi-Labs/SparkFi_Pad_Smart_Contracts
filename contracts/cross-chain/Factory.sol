pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFactory.sol";
import "./Pool.sol";

contract Factory is Ownable, IFactory {
  address[] public pools;
  address public immutable router;

  constructor(address _router) {
    router = _router;
  }

  function allPoolsLength() external view returns (uint256) {
    return pools.length;
  }

  function createPool(
    string memory _name,
    string memory _symbol,
    address _poolToken,
    address _feeTaker,
    address _feeRewardLibrary,
    uint256 _sharedDecimals,
    uint256 _localDecimals
  ) external returns (address poolId) {
    bytes memory constructorArgs = abi.encode(_name, _symbol, _poolToken, router, _feeTaker, _feeRewardLibrary, _sharedDecimals, _localDecimals);
    bytes memory bytecode = abi.encodePacked(type(Pool).creationCode, constructorArgs);
    bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp, router));

    assembly ("memory-safe") {
      poolId := create2(0, add(bytecode, 32), mload(bytecode), salt)
      if iszero(extcodesize(poolId)) {
        revert(0, "could not deploy pool contract")
      }
    }

    pools.push(poolId);
  }
}
