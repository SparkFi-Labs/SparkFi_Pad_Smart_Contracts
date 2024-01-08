pragma solidity ^0.8.0;

import "./interfaces/IFeeLibrary.sol";
import "./interfaces/IRewardsLibrary.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeAndRewardsLibrary is IFeeLibrary, IRewardsLibrary {
  using SafeMath for uint256;

  uint256 public constant FEE_DENOM = 1e4;
  uint256 public constant REWARDS_MULTIPLIER = 1e8;
  uint256 public MIN_FEE = 0;
  uint16 public FEE_TAKER_FEE = 2000;
  uint16 public LP_PROVIDER_FEE = 8000;

  function _applyFee(uint256 _amountIn, uint256 _fee) internal view returns (uint256) {
    require(_fee >= MIN_FEE, "not enough fee");
    return (_amountIn * (FEE_DENOM - _fee)) / FEE_DENOM;
  }

  function getFees(uint256 amount) external view returns (Pool.SwapMessage memory s) {
    uint256 feeTakerFee = _applyFee(amount, FEE_TAKER_FEE);
    uint256 lpProviderFee = _applyFee(amount, LP_PROVIDER_FEE);

    s.feeTakerAmount = amount.sub(feeTakerFee);
    s.lpProviderAmount = amount.sub(lpProviderFee);
    return s;
  }

  function getReward(
    address pool,
    address account,
    uint256 totalRewards
  ) external view returns (uint256 reward) {
    IERC20 pToken = IERC20(pool);
    uint256 balance = pToken.balanceOf(account);
    uint256 totalSupply = pToken.totalSupply();
    uint256 calculatedReward = balance.mul(REWARDS_MULTIPLIER).mul(totalRewards).div(totalSupply);
    reward = calculatedReward.div(REWARDS_MULTIPLIER);
  }
}
