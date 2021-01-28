pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Emblem.sol";

contract VanityExchange is ReentrancyGuard, Ownable {
  using SafeMath for uint256;

  struct Order {
    uint256 id;
    address payable maker;
    bytes12 makerVanity;
    uint256 price;
    bytes12 vanity;
    bool demand;
    uint256 createdAt;
  }

  // order id -> order
  mapping(uint256 => Order) public orders;

  // Array with all order ids, used for enumeration
  uint256[] internal allOrders;

  // Mapping from order id to position in the allOrders array
  mapping(uint256 => uint256) internal allOrdersIndex;

  // Mapping from owner to list of owned order IDs
  mapping(address => uint256[]) internal ownedOrders;

  // Mapping from owner to map of order ID to index of the owner orders list
  mapping(address => mapping (uint256 => uint256)) internal ownedOrdersIndex;

  // weiSend of current tx
  uint256 private weiSend = 0;

  uint256 private highestId = 1;

  Emblem EMB;

  uint256 makerFee = 1;
  uint256 takerFee = 1;
  uint256 feeDenomination = 1000;
  address payable feeReciever;


  // makes sure weiSend of current tx is reset
  modifier weiSendGuard() {
    weiSend = msg.value;
    _;
    weiSend = 0;
  }

  // logs
  event OrderPlaced(uint256 id, address maker, uint256 price, bytes12 vanity, bool demand, uint256 createdAt);

  event OrderFilled(uint256 id, address maker, address taker, uint256 price, bytes12 vanity, bool demand, uint256 fulfilledAt);

  event OrderCancelled(uint256 id, address maker, uint256 price, bytes12 vanity, bool demand);

  constructor(address _emb,address payable _feeReciever) public {
    EMB = Emblem(_emb);
    feeReciever = _feeReciever;
  }

  function exists(uint256 id) public view returns (bool) {
    return (orders[id].id == id);
  }

  function setFees(uint256 _makerFee, uint256 _takerFee, uint256 _denomination) public onlyOwner {
    require(_makerFee < _denomination && _takerFee < _denomination);
    makerFee = _makerFee;
    takerFee = _takerFee;
    feeDenomination = _denomination;
  }

  function getFee(address owner, bytes12 vanity, bool isMaker) public view returns (uint256){
    if(EMB.getVanityOwner(vanity) == owner && EMB.enabledVanityFee(vanity)) return EMB.getFee(vanity);
    else {
      if(isMaker) return makerFee;
      else return takerFee;
    }
  }

  function getNewId() public view returns(uint256) {
    return highestId;
  }

  function _placeOrder(address payable maker, uint256 price, bytes12 vanity, bool demand, bytes12 makerVanity) internal returns (bool){

    // validate input
    if (price <= 0) return (false);

    if(demand) {
      if(weiSend <= 0 || weiSend < price) return (false);
    }
    else {
      if (!EMB.vanityAllowance(maker, vanity,address(this))) return (false);
    }

    uint256 id = getNewId();

    orders[id] = Order(id, maker,makerVanity, price,vanity, demand, block.timestamp);
    allOrders.push(id);
    allOrdersIndex[id] = allOrders.length.sub(1);

    if(demand) weiSend = weiSend.sub(price);
    else EMB.transferVanityFrom(maker, address(this), vanity);

    _addOrderToUser(maker, id);

    emit OrderPlaced(id, maker, price, vanity, demand, block.timestamp);

    highestId = highestId + 1;

    return (true);
  }

  function _takeOrder(address payable taker, uint256 id, bytes12 vanity) internal returns (bool) {

    if (id <= 0) return (false);
    Order storage order = orders[id];
    if (order.id != id) return (false);

    if(order.demand){

      if (!EMB.vanityAllowance(taker, order.vanity,address(this))) return (false);


      EMB.transferVanityFrom(taker,order.maker,order.vanity);

      uint256 fee_taker = order.price.mul(getFee(taker, vanity, true));

      feeReciever.transfer(fee_taker);

      taker.transfer(order.price - fee_taker);
    }
    //
    else {
      if (weiSend <= 0 || weiSend < order.price) return (false);

      weiSend = weiSend.sub(order.price);

      EMB.transferVanity(order.vanity,taker);

      uint256 fee_maker = order.price.mul(getFee(order.maker, order.makerVanity, true));

      feeReciever.transfer(fee_maker);

      order.maker.transfer(order.price - fee_maker);
    }
    //
    emit OrderFilled(id, order.maker, taker, order.price,order.vanity, order.demand, block.timestamp);

    // _deleteOrder(id);
    uint256 orderIndex = allOrdersIndex[id];
    uint256 lastOrderIndex = allOrders.length.sub(1);
    uint256 lastOrder = allOrders[lastOrderIndex];

    allOrders[orderIndex] = lastOrder;
    delete allOrdersIndex[id];
    allOrdersIndex[lastOrder] = orderIndex;
    allOrders.pop();

    _removeOrderFromUser(orders[id].maker, id);

    delete orders[id];

    return (true);
  }

  function _deleteOrder(uint256 id) internal returns (bool) {

    if (
      id <= 0 ||
      orders[id].id != id
    ) return (false);

    // // Reorg all orders
    uint256 orderIndex = allOrdersIndex[id];
    uint256 lastOrderIndex = allOrders.length.sub(1);
    uint256 lastOrder = allOrders[lastOrderIndex];
    allOrders[orderIndex] = lastOrder;
    delete allOrdersIndex[id];
    allOrdersIndex[lastOrder] = orderIndex;
    allOrders.pop();

    //pay back on cancellation
    if(orders[id].demand == false){
      EMB.transferVanity(orders[id].vanity,orders[id].maker);
    }
    else {
      orders[id].maker.transfer(orders[id].price);
    }
    //remove order from user
    _removeOrderFromUser(orders[id].maker, id);

    delete orders[id];

    return (true);
  }

  function retrieveMyOrders() public view returns(uint256[] memory) {
    return ownedOrders[msg.sender];
  }

  function retrieveOrders() public view returns(uint256[] memory) {
    return allOrders;
  }

  function getOrderData(uint256 id) public view returns (uint256, address, uint256, bytes12, bool, uint256) {
    require(orders[id].id == id);
    return (orders[id].id, orders[id].maker, orders[id].price, orders[id].vanity, orders[id].demand, orders[id].createdAt);
  }

  function _addOrderToUser(address _to, uint256 _orderId) internal {
    uint256 length = ownedOrders[_to].length;
    ownedOrders[_to].push(_orderId);
    ownedOrdersIndex[_to][_orderId] = length;
  }

  function _removeOrderFromUser(address _from, uint256 _orderId) internal {
    uint256 orderIndex = ownedOrdersIndex[_from][_orderId];
    uint256 lastOrderIndex = ownedOrders[_from].length.sub(1);
    uint256 lastOrderId = ownedOrders[_from][lastOrderIndex];

    ownedOrders[_from][orderIndex] = lastOrderId;
    ownedOrders[_from].pop();
    delete ownedOrdersIndex[_from][_orderId];
    ownedOrdersIndex[_from][lastOrderId] = orderIndex;
  }

  function placeOrder(uint256 price, bytes12 vanity, bool demand, bytes12 makerVanity)  external payable weiSendGuard nonReentrant returns (bool)  {
    bool success = _placeOrder(msg.sender, price, vanity, demand,makerVanity);

    //send back excess ETH
    if (weiSend > 0) msg.sender.transfer(weiSend);

    return success;
  }

  function takeOrder(uint256 id,bytes12 vanity)  external payable weiSendGuard nonReentrant returns (bool) {
    require(orders[id].id == id);

    bool success = _takeOrder(msg.sender, id, vanity);

    //send back excess ETH
    if (weiSend > 0) msg.sender.transfer(weiSend);

    return success;
  }

  function cancelOrder(uint256 id) external nonReentrant returns (bool) {
    require(
      id > 0 &&
      orders[id].id == id &&
      orders[id].maker == msg.sender
    );

    uint256 price = orders[id].price;
    bytes12 vanity = orders[id].vanity;
    bool demand = orders[id].demand;

    bool success = _deleteOrder(id);
    if(success) emit OrderCancelled(id, msg.sender,price, vanity,demand);

    return success;
  }
}
