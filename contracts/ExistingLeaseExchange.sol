// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LeasedEmblem.sol";
import "./Emblem.sol";

contract ExistingLeaseExchange is ReentrancyGuard,Ownable {
  using SafeMath for uint256;

  struct Order {
    uint256 id;
    address payable maker;
    bytes12 makerVanity;
    uint256 amount;
    uint256 price;
    bool demand;
    uint256 duration;
    uint256 createdAt;
    uint256 tradeExpiry;
    uint256 lembId;
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

  uint256 sixMonths       = 15768000;
  uint256 twelveMonths    = 31536000;
  uint256 twentyFourMonths = 63072000;

  uint256 EMBPrecision = (10 ** 8);

  uint256 makerFee = 1;
  uint256 takerFee = 1;
  uint256 feeDenomination = 1000;

  LeasedEmblem LEMB;
  Emblem EMB;
  address payable feeReciever;


  // makes sure weiSend of current tx is reset
  modifier weiSendGuard() {
    weiSend = msg.value;
    _;
    weiSend = 0;
  }

  // logs
  event OrderPlaced(uint256 id, address maker, uint256 amount, uint256 price, bool demand, uint256 duration, uint256 createdAt, uint256 lembId);

  event OrderFilled(uint256 id, address maker, address taker, uint256 originalAmount, uint256 amountFilled, uint256 price, uint256 duration, uint256 lembId, uint256 fulfilledAt);

  event OrderCancelled(uint256 id, address maker, uint256 amount, uint256 price, bool demand, uint256 duration, uint256 createdAt);

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
    if(EMB.getVanityOwner(vanity) == owner && EMB.enabledVanityFee()) return EMB.getFee(vanity);
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

  function _placeOrder(address payable maker, uint256 price, uint256 amount, uint256 lembId, bool demand, uint256 duration, uint256 tradeDuration, bytes12 vanity) internal returns (bool){

    uint256 id = getNewId();
    // validate input
    if (
      amount <= 0 ||
      price <= 0 ||
      amount.mul(price) < (EMBPrecision) ||
      (duration != sixMonths && duration != twelveMonths && duration != twentyFourMonths)
    ) return (false);

    if(demand) {
      if(weiSend <= 0 || weiSend < amount.mul(price).div(EMBPrecision) || tradeDuration <= 0 || tradeDuration > sixMonths) return (false);
    }
    else {
      if(duration != LEMB.getDuration(lembId) || LEMB.ownerOf(lembId) != maker || amount > LEMB.getAmount(lembId) || LEMB.getApproved(lembId) != address(this)) return (false);
    }

    if(demand) {
      weiSend = weiSend.sub(amount.mul(price).div(EMBPrecision));
      orders[id] = Order(id, maker,vanity, amount, price, demand, duration,block.timestamp,block.timestamp + tradeDuration,0);
      emit OrderPlaced(id, maker, amount, price,demand, duration,block.timestamp,0);
    }
    else {
      LEMB.transferFrom(maker, address(this), lembId);
      if(amount < LEMB.getAmount(lembId)){
        uint256 newLembId = LEMB.getNewId();
        LEMB.splitLEMB(lembId, amount);
        LEMB.transferFrom(address(this),maker,lembId);
        orders[id] = Order(id, maker,vanity, amount, price, demand, duration,block.timestamp,LEMB.getTradeExpiry(lembId),newLembId);
        emit OrderPlaced(id, maker, amount, price,demand, duration,block.timestamp,newLembId);
      }
      else if(amount == LEMB.getAmount(lembId)){
        orders[id] = Order(id, maker,vanity, amount, price, demand, duration,block.timestamp,LEMB.getTradeExpiry(lembId),lembId);
        emit OrderPlaced(id, maker, amount, price,demand, duration,block.timestamp,lembId);
      }
    }

    allOrders.push(id);
    allOrdersIndex[id] = allOrders.length.sub(1);
    _addOrderToUser(maker, id);

    highestId = highestId + 1;

    return (true);
  }

  function _takeOrder(address payable taker, uint256 id, uint256 amount, uint256 lembId, uint256 fee_taker, uint256 fee_maker) internal returns (bool) {
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
      if(LEMB.ownerOf(lembId) != taker || amount > LEMB.getAmount(lembId) || LEMB.getApproved(lembId) != address(this)) return (false);

      //transfer EMB from taker to Lease Address
      LEMB.transferFrom(taker, address(this), lembId);

      if(amount < LEMB.getAmount(lembId)){
        //split the LEMB for the fee Reciever
        uint256 feeRecieverLembId = LEMB.getNewId();
        LEMB.splitLEMB(lembId, fee_maker);
        LEMB.transferFrom(address(this),feeReciever,feeRecieverLembId);

        //split the LEMB for the maker
        uint256 makerLembId = LEMB.getNewId();
        LEMB.splitLEMB(lembId, amount - fee_maker);
        LEMB.transferFrom(address(this),order.maker,makerLembId);

        //send back leftover LEMB
        LEMB.transferFrom(address(this),taker,lembId);

        emit OrderFilled(id, order.maker, taker, order.amount, amount, order.price, order.duration, makerLembId, block.timestamp);
      }
      else if(amount == LEMB.getAmount(lembId)){

        //split the LEMB for the fee Reciever
        uint256 feeRecieverLembId = LEMB.getNewId();
        LEMB.splitLEMB(lembId, fee_maker);
        LEMB.transferFrom(address(this),feeReciever,feeRecieverLembId);

        //send the rest of the lembId to the maker
        LEMB.transferFrom(address(this),order.maker,lembId);

        emit OrderFilled(id, order.maker, taker, order.amount, amount, order.price, order.duration, lembId, block.timestamp);
      }

      //
      feeReciever.transfer(fee_taker);

      //pay taker
      taker.transfer(amount.mul(order.price).div(EMBPrecision) - fee_taker);
    }
    else {

      //ensure that you have sent the right amount of eth
      if (weiSend <= 0 || weiSend < amount.mul(order.price).div(EMBPrecision)) return (false);

      //pay maker
      weiSend = weiSend.sub(amount.mul(order.price).div(EMBPrecision));

      feeReciever.transfer(fee_maker);
      order.maker.transfer(amount.mul(order.price).div(EMBPrecision) - fee_maker);

      //create LEMB for the taker
      if(amount < LEMB.getAmount(order.lembId)){

        //pay feeReciever
        uint256 feeRecieverLembId = LEMB.getNewId();
        LEMB.splitLEMB(order.lembId, fee_taker);
        LEMB.transferFrom(address(this),feeReciever,feeRecieverLembId);

        //pay fee Taker
        uint256 takerLembId = LEMB.getNewId();
        LEMB.splitLEMB(order.lembId, amount - fee_taker);
        LEMB.transferFrom(address(this),taker,takerLembId);

        emit OrderFilled(id, order.maker, taker, order.amount, amount, order.price, order.duration, takerLembId, block.timestamp);
      }
      else if(amount == LEMB.getAmount(lembId)){

        //split the LEMB for the fee Reciever
        uint256 feeRecieverLembId = LEMB.getNewId();
        LEMB.splitLEMB(order.lembId, fee_taker);
        LEMB.transferFrom(address(this),feeReciever,feeRecieverLembId);

        LEMB.transferFrom(address(this),taker,order.lembId);
        emit OrderFilled(id, order.maker, taker, order.amount, amount, order.price, order.duration, order.lembId, block.timestamp);
      }
    }

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
    if(orders[id].amount !=0) {
      if(orders[id].demand == false){
        LEMB.transferFrom(address(this), orders[id].maker, orders[id].lembId);
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

  function retrieveMyOrders() public view returns(uint256[] memory) {
    return ownedOrders[msg.sender];
  }

  function retrieveOrders() public view returns(uint256[] memory) {
    return allOrders;
  }

  function getOrderData(uint256 id) public view returns (
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    address,
    bool
  ) {
    require(orders[id].id == id);
    return (orders[id].id,orders[id].amount,orders[id].price,orders[id].duration,orders[id].tradeExpiry,orders[id].maker,orders[id].demand);
  }

  function getLembId(uint256 id) public view returns (
    uint256
  ) {
    require(orders[id].id == id);
    return (orders[id].lembId);
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

  function placeOrder(uint256 price, uint256 amount, bool demand, uint256 duration,uint256 tradeDuration,uint256 lembId,bytes12 vanity) external payable weiSendGuard nonReentrant returns (bool) {

    bool success = _placeOrder(msg.sender, price, amount, lembId, demand, duration, tradeDuration,vanity);

    if (weiSend > 0) msg.sender.transfer(weiSend);

    return success;
  }

  function takeOrder(uint256 id, uint256 amount,uint256 lembId,bytes12 vanity)  external payable weiSendGuard nonReentrant returns (bool) {
    Order memory order = orders[id];

    require(order.id == id && id != 0);

    bool success = false;

    if(order.demand){
      uint256 fee_maker = amount.mul(getFee(order.maker, order.makerVanity, true)).div(feeDenomination);
      uint256 fee_taker = amount.mul(order.price).div(EMBPrecision).mul(getFee(msg.sender, vanity, false)).div(feeDenomination);
      success = _takeOrder(msg.sender,id,amount,lembId,fee_taker,fee_maker);
    }
    else {
      uint256 fee_maker = amount.mul(order.price).div(EMBPrecision).mul(getFee(order.maker, order.makerVanity, true)).div(feeDenomination);
      uint256 fee_taker = amount.mul(getFee(msg.sender, vanity, false)).div(feeDenomination);
      success = _takeOrder(msg.sender,id,amount,lembId,fee_taker,fee_maker);
    }

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

    uint256 amount = orders[id].amount;
    uint256 price = orders[id].price;
    bool demand = orders[id].demand;
    uint256 duration = orders[id].duration;
    uint256 createdAt = orders[id].createdAt;

    bool success = _deleteOrder(id);
    if(success) emit OrderCancelled(id, msg.sender, amount, price, demand, duration, createdAt);

    return success;
  }

}
