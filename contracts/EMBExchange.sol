pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LeasedEmblem.sol";
import "./Emblem.sol";

contract EMBExchange is ReentrancyGuard, Ownable {
  using SafeMath for uint256;

  struct Order {
    uint256 id;
    address payable maker;
    bytes12 makerVanity;
    uint256 amount;
    uint256 price;
    bool demand;
    uint256 createdAt;
  }

  // order id -> order
  mapping(uint256 => Order) public orders;

  // Array with all order ids, used for enumeration
  uint256[]  allOrders;

  // Mapping from order id to position in the allOrders array
  mapping(uint256 => uint256)  allOrdersIndex;

  // Mapping from owner to list of owned order IDs
  mapping(address => uint256[])  ownedOrders;

  // Mapping from owner to map of order ID to index of the owner orders list
  mapping(address => mapping (uint256 => uint256))  ownedOrdersIndex;

  // weiSend of current tx
  uint256 private weiSend = 0;
  uint256 private highestId = 1;
  uint256 private EMBPrecision = (10**8);

  uint256 makerFee = 1;
  uint256 takerFee = 1;
  uint256 feeDenomination = 1000;

  Emblem EMB;
  LeasedEmblem LEMB;
  address payable feeReciever;

  // makes sure weiSend of current tx is reset
  modifier weiSendGuard() {
    weiSend = msg.value;
    _;
    weiSend = 0;
  }

  // logs
  event OrderPlaced(uint256 id, address maker, uint256 amount, uint256 price, bool demand);

  event OrderFilled(uint256 id, address maker, address taker, uint256 originalAmount, uint256 amountFilled, uint256 price, bool demand, uint256 fulfilledAt);

  event OrderCancelled(uint256 id, address maker, uint256 amount, uint256 price, bool demand, uint256 createdAt);

  constructor(address _emb, address _lemb, address payable _feeReciever) public {
    EMB = Emblem(_emb);
    LEMB = LeasedEmblem(_lemb);
    feeReciever = _feeReciever;
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

  function exists(uint256 id) public view returns (bool) {
    return (orders[id].id == id);
  }

  function getNewId() public view returns(uint256) {
    return highestId;
  }

  function _placeOrder(address payable maker, uint256 price, uint256 amount, bool demand,bytes12 vanity) internal returns (bool){

    // validate input
    if (amount <= 0 ||
      price <= 0 ||
      amount.mul(price) < (EMBPrecision)
    ) return (false);

    if(demand) {
      if(weiSend <= 0 || weiSend < amount.mul(price).div(EMBPrecision)) return (false);
    }
    else {
      if ( EMB.balanceOf(maker) - LEMB.getAmountForUserMining(maker) < amount || (EMB.allowance(maker, address(this)) - LEMB.getAmountForUserMining(maker) < amount)) return (false);
    }

    uint256 id = getNewId();

    orders[id] = Order(id, maker,vanity, amount, price, demand,block.timestamp);
    allOrders.push(id);
    allOrdersIndex[id] = allOrders.length.sub(1);

    if(demand) weiSend = weiSend.sub(amount.mul(price).div(EMBPrecision));
    else EMB.transferFrom(maker, address(this), amount);

    _addOrderToUser(maker, id);

    emit OrderPlaced(id, maker, amount, price,demand);

    highestId = highestId + 1;

    return (true);
  }

  //returns the amount to send to the user
  function getTransferAmount(uint256 amount, uint256 price,uint256 fee,bool isTaker, bool isEMB) internal view returns (uint256){
    if(isTaker) {
      if(isEMB) return amount.mul(fee).div(feeDenomination);
      else return amount.mul(price).div(EMBPrecision).mul(fee).div(feeDenomination);
    }
    else {
      if(isEMB) return amount.mul((uint256(1)).sub(fee.div(feeDenomination)));
      else return amount.mul(price).div(EMBPrecision).mul((uint256(1)).sub(fee.div(feeDenomination)));
    }
  }

  function _takeOrder(address payable taker, uint256 id, uint256 amount, bytes12 vanity) internal returns (bool) {
    // validate inputs
    if (id <= 0) return (false);

    // get order
    Order storage order = orders[id];

    // validate order
    if (
      order.id != id ||
      amount <= 0
    ) return (false);

    //if above, set amount to that of the order's amount
    if(amount > order.amount) amount = order.amount;

    if(order.demand){

      //ensure that you cannot game the allowance of EMB
      if ( EMB.balanceOf(taker) - LEMB.getAmountForUserMining(taker) < amount || (EMB.allowance(taker, address(this)) - LEMB.getAmountForUserMining(taker) < amount)) return (false);

      uint256 fee_maker = amount.mul(getFee(order.maker, order.makerVanity, true)).div(feeDenomination);

      //transfer EMB to feeReciever from maker
      EMB.transferFrom(taker, feeReciever, fee_maker);

      //transfer EMB from taker to maker
      EMB.transferFrom(taker, order.maker, amount - fee_maker);

      uint256 fee_taker = amount.mul(order.price).div(EMBPrecision).mul(getFee(taker, vanity, false)).div(feeDenomination);

      //transfer ETH to feeReciever from taker
      feeReciever.transfer(fee_taker);

      //pay taker
      taker.transfer(amount.mul(order.price).div(EMBPrecision) - fee_taker);
    }

    else {

      //ensure that you have sent the right amount of eth
      if (weiSend <= 0 || weiSend < amount.mul(order.price).div(EMBPrecision)) return (false);

      //pay maker
      weiSend = weiSend.sub(amount.mul(order.price).div(EMBPrecision));

      uint256 fee_maker = amount.mul(order.price).div(EMBPrecision).mul(getFee(order.maker, order.makerVanity, true)).div(feeDenomination);

      //transfer ETH to feeReciever from maker
      feeReciever.transfer(fee_maker);

      //transfer ETH from taker to maker
      order.maker.transfer(amount.mul(order.price).div(EMBPrecision) - fee_maker);

      uint256 fee_taker = amount.mul(getFee(taker, vanity, false)).div(feeDenomination);

      //transfer EMB to feeReciever from taker
      EMB.transfer(feeReciever, fee_taker);

      //pay taker
      EMB.transfer(taker, amount - fee_taker);
    }

    emit OrderFilled(id, order.maker, taker, order.amount, amount, order.price, order.demand, block.timestamp);

    order.amount = order.amount - amount;

    if(order.amount == 0){
      _deleteOrder(id);
    }

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
    if(orders[id].amount != 0){
      if(orders[id].demand == false){
        EMB.transfer(orders[id].maker,orders[id].amount);
      }
      else {
        orders[id].maker.transfer(orders[id].amount.mul(orders[id].price).div(EMBPrecision));
      }
    }

    //remove order from user
    _removeOrderFromUser(orders[id].maker, id);

    delete orders[id];

    return (true);
  }

  function retrieveEMBInOrder() public view returns(uint256){
    uint256 amount = 0;
    for(uint256 i = 0; i < allOrders.length; i++){
      if(orders[allOrders[i]].demand == false) {
        amount += orders[allOrders[i]].amount;
      }
    }
    return amount;
  }

  function retrieveMyOrders() public view returns(uint256[] memory) {
    return ownedOrders[msg.sender];
  }

  function retrieveOrders() public view returns(uint256[] memory) {
    return allOrders;
  }

  function getOrderData(uint256 id) public view returns (uint256, address, uint256, uint256, bool) {
    require(orders[id].id == id);
    return (orders[id].id, orders[id].maker, orders[id].amount, orders[id].price, orders[id].demand);
  }

  function _addOrderToUser(address _to, uint256 _orderId) internal {
    uint256 length = ownedOrders[_to].length;
    ownedOrders[_to].push(_orderId);
    ownedOrdersIndex[_to][_orderId] = length;
  }

  function _removeOrderFromUser(address _from, uint256 _orderId) internal  {
    uint256 orderIndex = ownedOrdersIndex[_from][_orderId];
    uint256 lastOrderIndex = ownedOrders[_from].length.sub(1);
    uint256 lastOrderId = ownedOrders[_from][lastOrderIndex];

    ownedOrders[_from][orderIndex] = lastOrderId;
    ownedOrders[_from].pop();
    delete ownedOrdersIndex[_from][_orderId];
    ownedOrdersIndex[_from][lastOrderId] = orderIndex;
  }

  function placeOrder(uint256 price, uint256 amount, bool demand,bytes12 vanity)  external payable weiSendGuard nonReentrant returns (bool)  {
    bool success = _placeOrder(msg.sender, price, amount, demand, vanity);

    //send back excess ETH
    if (weiSend > 0) msg.sender.transfer(weiSend);

    return success;
  }

  function takeOrder(uint256 id, uint256 amount,bytes12 vanity)  external payable weiSendGuard nonReentrant returns (bool) {
    require(orders[id].id == id);

    bool success = _takeOrder(msg.sender, id, amount, vanity);

    //send back excess ETH
    if (weiSend > 0) msg.sender.transfer(weiSend);

    return success;
  }

  //take a few orders and place Order if order to place
  function takeOrders(uint256[] memory ids, uint256[] memory amounts, uint256 price, uint256 amount, bool demand,bytes12 vanity) external payable weiSendGuard nonReentrant returns (bool) {
    require(ids.length == amounts.length);

    bool allSuccess = true;
    bool success = false;

    for (uint256 i = 0; i < ids.length; i++){
      require(orders[ids[i]].id == ids[i]);
      success = _takeOrder(msg.sender, ids[i], amounts[i],vanity);
      if (allSuccess && !success) allSuccess = success;
    }

    if(amount != 0){
      success = _placeOrder(msg.sender, price, amount, demand,vanity);
      if (allSuccess && !success) allSuccess = success;
    }

    if (weiSend > 0) msg.sender.transfer(weiSend);

    return allSuccess;
  }

  function cancelOrder(uint256 id) external nonReentrant returns (bool) {
    require(
      id > 0 &&
      orders[id].id == id &&
      orders[id].maker == msg.sender
    );

    uint256 amount = orders[id].amount;
    uint256 price = orders[id].price;
    bool demand = orders[id].demand;
    uint256 createdAt = orders[id].createdAt;

    bool success = _deleteOrder(id);
    if(success) emit OrderCancelled(id, msg.sender, amount, price, demand, createdAt);

    return success;
  }

}
