pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IFeeLibrary.sol";
import "./interfaces/IRewardsLibrary.sol";
import "../helpers/TransferHelper.sol";

contract Pool is Context, ERC20, IPool, ReentrancyGuard, Pausable {
  using SafeMath for uint256;

  address public router;
  address public feeRewardLibrary;
  address public feeTaker;

  IERC20 public poolToken;

  uint256 public constant ONE_MONTH = 2419200;
  uint256 public AVAILABLE_LP_PROVIDERS_REWARD;
  uint256 public sharedDecimals; // Lowest decimal between chains
  uint256 public localDecimals; // The decimals of the token on this chain

  struct SwapMessage {
    address to;
    uint256 amount;
    uint256 feeTakerAmount;
    uint256 lpProviderAmount;
  }

  struct ChainObj {
    bool created;
    uint256 destinationChainId;
    address destinationPoolId;
    uint256 balance;
    uint256 credits;
  }

  ChainObj[] chainObjs;
  mapping(uint256 => mapping(address => uint256)) public chainObjToIndex;
  mapping(address => uint256) public lastRewardTime;

  event Swap(address indexed to, uint256 indexed amount, uint256 indexed timestamp, uint256 destinationChainId, address destinationPoolId);
  event SwapRemote(address indexed to, uint256 indexed amount, uint256 indexed timestamp, uint256 sourceChainId, address sourcePoolId);
  event ChainPathCreated(uint256 indexed destinationChainId, address indexed destinationPoolId);
  event ChainCredited(uint256 indexed destinationChainId, address indexed destinationPoolId, uint256 newBalance);
  event BalanceDepleted(uint256 indexed destinationChainId, address indexed destinationPoolId, uint256 amount);
  event ChainCreditRemoved(uint256 indexed destinationChainId, address indexed destinationPoolId, uint256 amount);
  event ChainPathRemoved(uint256 indexed destinationChainId, address indexed destinationPoolId);

  constructor(
    string memory _name,
    string memory _symbol,
    address _poolToken,
    address _router,
    address _feeTaker,
    address _feeRewardLibrary,
    uint256 _sharedDecimals,
    uint256 _localDecimals
  ) ERC20(_name, _symbol) {
    router = _router;
    feeTaker = _feeTaker;
    poolToken = IERC20(_poolToken);
    feeRewardLibrary = _feeRewardLibrary;
    sharedDecimals = _sharedDecimals;
    localDecimals = _localDecimals;
  }

  modifier onlyRouter() {
    require(_msgSender() == router, "only router");
    _;
  }

  modifier onlyAMonthFromLastRewardTime(address acc) {
    require(block.timestamp.sub(lastRewardTime[acc]) >= ONE_MONTH, "must be a month from last disbursement");
    _;
  }

  function decimals() public view virtual override returns (uint8) {
    return uint8(sharedDecimals);
  }

  function convertRate() public view returns (uint256) {
    return 10**(uint256(localDecimals).sub(sharedDecimals));
  }

  function mint(address to, uint256 amount) external whenNotPaused onlyRouter {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external whenNotPaused onlyRouter {
    _burn(from, amount);
  }

  function _getChainObj(uint256 destinationChainId, address destinationPoolId) internal view returns (ChainObj storage) {
    uint256 index = chainObjToIndex[destinationChainId][destinationPoolId];
    return chainObjs[index];
  }

  function swap(
    address to,
    uint256 amount,
    uint256 destinationChainId,
    address destinationPoolId
  ) external whenNotPaused nonReentrant onlyRouter returns (SwapMessage memory) {
    ChainObj storage chainObj = _getChainObj(destinationChainId, destinationPoolId);

    require(chainObj.created, "chain object not created on this chain");
    uint256 amountSD = _amountLDtoSD(amount);

    SwapMessage memory s = IFeeLibrary(feeRewardLibrary).getFees(amountSD);

    s.amount = amountSD.sub(s.feeTakerAmount).sub(s.lpProviderAmount);
    s.to = to;

    require(chainObj.balance >= s.amount, "not enough balance on destination chain");

    chainObj.balance = chainObj.balance.sub(s.amount);
    emit Swap(to, amount, block.timestamp, destinationChainId, destinationPoolId);
    return s;
  }

  function swapRemote(
    uint256 sourceChainId,
    address sourcePoolId,
    address to,
    SwapMessage memory s
  ) external nonReentrant onlyRouter {
    TransferHelpers._safeTransferERC20(address(poolToken), feeTaker, s.feeTakerAmount);
    AVAILABLE_LP_PROVIDERS_REWARD = AVAILABLE_LP_PROVIDERS_REWARD.add(s.lpProviderAmount);

    uint256 amountLD = _amountSDtoLD(s.amount);
    TransferHelpers._safeTransferERC20(address(poolToken), to, amountLD);
    emit SwapRemote(to, s.amount, block.timestamp, sourceChainId, sourcePoolId);
  }

  function dispenseReward(address to) external nonReentrant onlyRouter onlyAMonthFromLastRewardTime(to) {
    uint256 reward = IRewardsLibrary(feeRewardLibrary).getReward(address(this), to, AVAILABLE_LP_PROVIDERS_REWARD);
    reward = _amountSDtoLD(reward);
    require(reward > 0, "no reward");
    TransferHelpers._safeTransferERC20(address(poolToken), to, reward);
    AVAILABLE_LP_PROVIDERS_REWARD = AVAILABLE_LP_PROVIDERS_REWARD.sub(reward);
    setLastRewardTime(to, block.timestamp);
  }

  function getChainInfo(uint256 destinationChainId, address destinationPoolId) public view returns (ChainObj memory) {
    return _getChainObj(destinationChainId, destinationPoolId);
  }

  function _amountLDtoSD(uint256 amount) internal view returns (uint256) {
    return amount.div(convertRate());
  }

  function _amountSDtoLD(uint256 amount) internal view returns (uint256) {
    return amount.mul(convertRate());
  }

  function setLastRewardTime(address account, uint256 time) public {
    require(_msgSender() == address(this) || _msgSender() == router, "only this contract or router");
    lastRewardTime[account] = time;
  }

  function creditRemote(
    uint256 destinationChainId,
    address destinationPoolId,
    uint256 newBalance
  ) external nonReentrant onlyRouter returns (uint256 totalBalance) {
    ChainObj storage chainObj = _getChainObj(destinationChainId, destinationPoolId);
    require(chainObj.created, "chain object not created on this chain");
    chainObj.balance = chainObj.balance.add(newBalance);
    totalBalance = chainObj.balance;
    emit ChainCredited(destinationChainId, destinationPoolId, newBalance);
  }

  function removeCreditLocal(
    uint256 sourceChainId,
    address sourcePoolId,
    address account,
    uint256 amount
  ) external nonReentrant onlyRouter returns (uint256) {
    uint256 amountLD = _amountSDtoLD(amount);
    TransferHelpers._safeTransferERC20(address(poolToken), account, amountLD);
    emit BalanceDepleted(sourceChainId, sourcePoolId, amount);
    return amountLD;
  }

  function removeCreditRemote(
    uint256 destinationChainId,
    address destinationPoolId,
    uint256 amount
  ) external nonReentrant onlyRouter returns (uint256) {
    ChainObj storage chainObj = _getChainObj(destinationChainId, destinationPoolId);
    chainObj.balance = chainObj.balance > amount ? chainObj.balance.sub(amount) : 0;
    emit ChainCreditRemoved(destinationChainId, destinationPoolId, amount);
    return amount;
  }

  function createChainPath(uint256 destinationChainId, address destinationPoolId)
    external
    nonReentrant
    whenNotPaused
    onlyRouter
    returns (ChainObj memory)
  {
    for (uint256 i = 0; i < chainObjs.length; ++i) {
      ChainObj memory chainObj = chainObjs[i];
      require(chainObj.destinationChainId != destinationChainId && chainObj.destinationPoolId != destinationPoolId, "chain object already created");
    }

    ChainObj memory _chainObj = ChainObj({
      created: true,
      destinationChainId: destinationChainId,
      destinationPoolId: destinationPoolId,
      balance: 0,
      credits: 0
    });

    chainObjToIndex[destinationChainId][destinationPoolId] = chainObjs.length;
    chainObjs.push(_chainObj);
    emit ChainPathCreated(destinationChainId, destinationPoolId);
    return _chainObj;
  }

  function removeChainPath(uint256 destinationChainId, address destinationPoolId)
    external
    nonReentrant
    onlyRouter
    returns (ChainObj memory chainObj)
  {
    chainObj = getChainInfo(destinationChainId, destinationPoolId);
    delete chainObjs[chainObjToIndex[destinationChainId][destinationPoolId]];
    emit ChainPathRemoved(destinationChainId, destinationPoolId);
  }

  function setFeeLibrary(address _feeLibraryAddr) external onlyRouter {
    require(_feeLibraryAddr != address(0x0), "fee library can't be 0x0");
    feeRewardLibrary = _feeLibraryAddr;
  }

  function pause() external onlyRouter {
    _pause();
  }

  function unpause() external onlyRouter {
    _unpause();
  }
}
