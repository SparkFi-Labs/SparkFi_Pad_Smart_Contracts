pragma solidity ^0.8.0;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IWETH.sol";
import "../helpers/TransferHelper.sol";
import "../exchange-aggregator/interfaces/ISparkfiRouter.sol";

contract Bridge is OAppSender, OAppReceiver, AccessControl {
  address public feeReceiver;
  IWETH public WETH;
  uint256 public immutable chainId;
  ISparkfiRouter public swapRouter;

  struct BridgeMessage {
    address tokenAddress;
    uint256 amount;
    address receiver;
    bytes32 messageID;
    uint256 srcChainID;
  }

  mapping(address => bytes32[]) public messageIDs;
  mapping(bytes32 => bool) public messageRedeemed;
  mapping(bytes32 => address) public tokensMap;

  bytes32 public maintainerRole = keccak256(abi.encodePacked("MAINTAINER_ROLE"));

  uint256 public constant FEE_DENOM = 1e4;
  uint256 public MIN_FEE = 0;

  constructor(
    address _endpoint,
    address _feeReceiver,
    address _weth,
    uint256 _chainId,
    address _swapRouter
  ) OAppCore(_endpoint, _msgSender()) {
    feeReceiver = _feeReceiver;
    WETH = IWETH(_weth);
    chainId = _chainId;
    swapRouter = ISparkfiRouter(_swapRouter);
  }

  modifier onlyMaintainer() {
    require(hasRole(maintainerRole, _msgSender()), "only maintainer");
    _;
  }

  function setMaintainer(address maintainer) external onlyOwner {
    require(!hasRole(maintainerRole, maintainer), "already maintainer");
    _grantRole(maintainerRole, maintainer);
  }

  function removeMaintainer(address maintainer) external onlyOwner {
    require(hasRole(maintainerRole, maintainer), "does not have maintainer role");
    _grantRole(maintainerRole, maintainer);
  }

  function _applyFee(uint256 _amountIn, uint256 _fee) internal view returns (uint256) {
    require(_fee >= MIN_FEE, "not enough fee");
    return (_amountIn * (FEE_DENOM - _fee)) / FEE_DENOM;
  }

  function quoteFee(
    uint32 _destinationEID,
    BridgeMessage memory _message,
    bytes memory _options,
    bool _payInLzToken
  ) public view returns (MessagingFee memory fee) {
    bytes memory payload = abi.encode(_message);
    fee = _quote(_destinationEID, payload, _options, _payInLzToken);
  }

  function _send(
    uint32 _destID,
    bytes memory _message,
    bytes memory _options,
    MessageFee memory _messageFee,
    address _refundAddress
  ) private payable returns (MessagingReceipt memory) {
    return _lzSend(_destID, _message, _options, messageFee, _refundAddress);
  }

  function send(
    uint32 _destinationEID,
    address _tokenAddress,
    uint256 _amount,
    address _receiver,
    uint256 _fee,
    bytes memory _options
  ) external payable {
    if (_tokenAddress == address(0)) {
      require(msg.value >= _amount, "value");
    }

    uint256 fee = _applyFee(_amount, _fee);
    uint256 feeIn = _amount - fee;
    bytes32 messageID = keccak256(abi.encodePacked(_destinationEID, tokenAddress, _amount, receiver, _msgSender(), block.timestamp));

    BridgeMessage memory message = BridgeMessage({
      tokenAddress: _tokenAddress,
      amount: _amount - feeIn,
      receiver: _receiver,
      messageID: messageID,
      srcChainID: chainId
    });
    MessagingFee memory msgFee = quoteFee(_destinationEID, message, _options, false);

    if (_tokenAddress != address(0)) {
      TransferHelpers._safeTransferFromERC20(_tokenAddress, _msgSender(), feeReceiver, feeIn);
      TransferHelpers._safeTransferFromERC20(_tokenAddress, _msgSender(), address(this), _amount - feeIn);

      if (address(this).balance < msgFee.nativeFee) {
        FormattedOffer memory offer = swapRouter.findBestPath(IERC20(_tokenAddress).balanceOf(address(this)) / 4, _tokenAddress, address(WETH), 4);

        swapRouter.swap(Trade({path: offer.path, amountIn: offer.amounts[0], amountOut: 0, adapters: offer.adapters}), address(this), 99);
      }
    } else {
      TransferHelpers._safeTransferEther(feeReceiver, feeIn);
    }

    bytes memory payload = abi.encode(message);
    _send{value: msgFee.nativeFee}(_destinationEID, payload, _options, msgFee, _msgSender());
  }

  function setFee(uint256 _minFee) external onlyMaintainer {
    MIN_FEE = _minFee;
  }

  function getTokensMapperId(uint256 _chainId, address _token) public view returns (bytes32 memory mapperId) {
    mapperId = keccak256(abi.encodePacked(_chainId, _token));
  }

  function mapTokens(
    uint256 _chainId,
    address _otherToken,
    address _thisToken
  ) external onlyMaintainer {
    bytes32 mapId = getTokensMapperId(_chainId, _otherToken);
    tokensMap[mapId] = _thisToken;
  }
}
