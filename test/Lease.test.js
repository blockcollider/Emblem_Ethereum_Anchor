var {increaseTimeTo, duration} = require('./helpers/increaseTime')
var latestTime = require('./helpers/latestTime')
var {advanceBlock} = require('./helpers/advanceToBlock')
var {EVMRevert} = require('./helpers/EVMRevert')
const BigNumber = require('bignumber.js');
var utf8 = require('utf8');
var EMB = artifacts.require("Emblem");
var LEMB = artifacts.require("LeasedEmblem");
var Lease= artifacts.require("NewLeaseExchange");
var ExistingLease = artifacts.require('ExistingLeaseExchange');
var EMBExchange= artifacts.require("EMBExchange");
var VanityExchange = artifacts.require("VanityExchange");

var constants = require('../constants.js')(web3);

let DURATION = 15768000;

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bignumber')(BigNumber))
    .should();

contract('L-EMB', async function(accounts) {

  beforeEach(async function () {
    EMB.defaults({
      from: accounts[0]
    });

    LEMB.defaults({
      gasPrice:21000,
      gasLimit: 80000000000000,
      from: accounts[0]
    });

    Lease.defaults({
      gasPrice:21000,
      gasLimit: 800000000000000,
      from: accounts[0]
    });

    let e = {
      _name: constants.name,
      _ticker: constants.ticker,
      _decimal: constants.decimals,
      _supply: constants.supply,
      _wallet: accounts[0]
    }

    this.lemb = await LEMB.new("LEMB","LEMB");
    this.emb = await EMB.new(e._name,e._ticker,e._decimal,e._supply,e._wallet);
    this.lease = await Lease.new(this.emb.address, this.lemb.address,e._wallet);
    this.existingLease = await ExistingLease.new(this.emb.address, this.lemb.address,e._wallet);
    this.vanityExchange = await VanityExchange.new(this.emb.address,e._wallet);
    this.embExchange = await EMBExchange.new(this.emb.address,this.lemb.address,e._wallet);
    await this.emb.setLEMB(this.lease.address)
    await this.emb.setLeaseExchange(this.lease.address);
    await this.lemb.setLeaseExchange(this.lease.address);
  });
  //
  it("should place an offer and cancel it", async function() {
    let id = 1, price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = false,  maker = accounts[0];

    //assign approval to the lease contract for the right amount of EMB
    await this.emb.approve(this.lease.address,amount);

    //check allowance rules are properly set
    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker});

    //check that the allowance has been reset to zero
    assert.equal((await this.emb.allowance(maker,this.lease.address)).toString(),(0).toString());
    // check there is one order
    assert.equal((await this.lease.retrieveOrders()).length,1);

    //check EMB was taken from user
    assert.equal((await this.emb.balanceOf(maker)).toString(),(await this.emb.totalSupply()).minus(amount).toString());

    //check the lease has the right amount of EMB
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(amount).toString());

    //check that the user has been assigned that order
    assert.equal((await this.lease.retrieveMyOrders() )[0],id);

    await this.lease.cancelOrder(id);

    //check there are no orders
    assert.equal((await this.lease.retrieveOrders()).length,0);

    //check EMB was sent back to user
    assert.equal((await this.emb.balanceOf(maker)).toString(),(await this.emb.totalSupply()).minus(0).toString());

    //check the lease has the right amount of EMB
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());

    //check the user has been removed of this order
    assert.equal((await await this.lease.retrieveMyOrders()).length,0);
  });
  //
  it('should be able to place a demand and cancel it', async function() {
    let id = 1, price = web3.utils.toWei('2','ether'), amount = Math.pow(10,8), demand = true, maker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{value:amount*price/Math.pow(10,8),from:maker});
    // check there is one order
    assert.equal((await this.lease.retrieveOrders()).length,1);

    //check the lease has the right amount of ETH
    assert.equal((await web3.eth.getBalance(this.lease.address)).toString(),(amount*price/Math.pow(10,8)).toString());

    //check that the user has been assigned that order
    assert.equal((await this.lease.retrieveMyOrders()) [0],id);

    await this.lease.cancelOrder(id);

    //check there are no orders
    assert.equal((await this.lease.retrieveOrders()).length,0);

    //check the lease has the right amount of ETH
    assert.equal((await web3.eth.getBalance(this.lease.address)).toString(),(0).toString());

    //check the user has been removed of this order
    assert.equal((await await this.lease.retrieveMyOrders()).length,0);
  });

  it("should place an offer and fulfill it completely", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = false,  maker = accounts[0], taker = accounts[1];

    //assign approval to the lease contract for the right amount of EMB
    await this.emb.approve(this.lease.address,amount,{from:maker});

    //check allowance rules are properly set
    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker});

    let oldMakerBalance = await web3.eth.getBalance(maker);

    let id = await this.lease.getNewId() - 1;

    //take offer
    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker,value:amount*price/Math.pow(10,8)});

    let newMakerBalance = await web3.eth.getBalance(maker);

    //check that the maker recieved the right amount of eth
    // assert.equal(oldMakerBalance.toString(), (newMakerBalance.sub(amount*price/Math.pow(10,8))).toString())

    //check that the taker has the right amount of LEMB
    assert.equal((await this.lemb.getAmountForUser(taker)).toString(),(amount*0.999).toString());

    //check the lease has the right amount of ETH and EMB
    assert.equal((await web3.eth.getBalance(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(amount*0.999).toString());

    //check there are no orders
    assert.equal((await this.lease.retrieveOrders()).length,0);
  });

  it("should place a demand and fulfill it completely", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});

    let oldTakerBalance = await web3.eth.getBalance(taker);

    let id = await this.lease.getNewId() - 1;
    //assign approval and take the demand
    await this.emb.approve(this.lease.address,amount,{from:taker});
    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    let newTakerBalance = await web3.eth.getBalance(taker);

    //check that the taker recieved the right amount of eth and gave up the righta amount of emb
    assert.isTrue(newTakerBalance.greaterThan(oldTakerBalance));
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(amount*0.999).toString());

    //check that the maker has the right amount of LEMB
    assert.equal((await this.lemb.getAmountForUser(maker)).toString(),(amount*0.999).toString());

    //check the lease has the right amount of ETH and EMB
    assert.equal((await web3.eth.getBalance(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(amount*0.999).toString());

    //check there are no orders
    assert.equal((await this.lease.retrieveOrders()).length,0);
  });

  it("should place a demand and fulfill it partially", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});

    let oldTakerBalance = await web3.eth.getBalance(taker);

    amount = amount / 2;

    let id = await this.lease.getNewId() - 1;

    //assign approval and take the demand
    await this.emb.approve(this.lease.address,amount,{from:taker});
    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    let newTakerBalance = await web3.eth.getBalance(taker);

    //check that the taker recieved the right amount of eth and gave up the righta amount of emb
    assert.isTrue(newTakerBalance.greaterThan(oldTakerBalance));

    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(amount*0.999).toString());


    assert.equal((await this.lemb.getAmountForUser(maker)).toString(),(amount*0.999).toString());

    //check the lease has the right amount of ETH and EMB
    assert.equal((await web3.eth.getBalance(this.lease.address)).toString(),(price/2).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(amount*0.999).toString());

    //check there are no orders
    assert.equal((await this.lease.retrieveOrders()).length,1);
  });


  it("should take a demand and be able to start mining and not be able to sell that EMB, nor transfer the LEMB", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    await this.emb.approve(this.lease.address,amount,{from:maker});
    await this.lease.startMining(id,{from:maker});
    assert.equal((await this.emb.balanceOf(maker)).toString(),(amount*0.999).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(amount*0.999).toString());

    await this.emb.transfer(taker,amount,{from:maker}).should.be.rejectedWith(EVMRevert);
  });


  it("should take a demand and be able to lease EMB and only transfer EMB up until his lease amount", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    await this.emb.approve(this.lease.address,amount,{from:maker});

    await this.lease.startMining(id,{from:maker});
    assert.equal((await this.emb.balanceOf(maker)).toString(),(amount*0.999).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(amount*0.999).toString());

    await this.emb.transfer(maker,100,{from:taker});

    await this.emb.transfer(taker,amount,{from:maker}).should.be.rejectedWith(EVMRevert);

    await this.emb.transfer(taker,99,{from:maker});

    await this.emb.transfer(taker,1,{from:maker});

    await this.emb.transfer(taker,1,{from:maker}).should.be.rejectedWith(EVMRevert);
  });


  it('should not be able to retrieve EMB before the lease end date',async function(){
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    await this.emb.approve(this.lease.address,amount,{from:maker});
    await this.lease.startMining(id,{from:maker});
    await this.lease.retrieveEMB(id,{from:taker}).should.be.rejectedWith(EVMRevert);
  });

  it('should be able to retrieve EMB after the lease end date',async function(){
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    await this.emb.approve(this.lease.address,amount,{from:maker});
    await this.lease.startMining(id,{from:maker});

    await increaseTimeTo(latestTime() + duration.seconds(DURATION + 1));

    await this.lease.retrieveEMB(id,{from:taker});
    await this.emb.transfer(maker,amount,{from:taker});
    await this.emb.transfer(taker,amount,{from:maker});
    assert.equal((await this.emb.balanceOf(maker)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(0).toString());
  });


  it('should not be able to transfer LEMB when mining is started', async function(){
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});
    await this.emb.approve(this.lease.address,amount,{from:maker});
    await this.lease.startMining(id,{from:maker});
    await this.lemb.transferFrom(maker,accounts[2],{from:maker}).should.be.rejectedWith(EVMRevert);
  });

  it('should be able to transfer LEMB and start mining and correctly retrieve EMB', async function(){
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    await this.lemb.transferFrom(maker,accounts[2],id,{from:maker});
    await this.emb.approve(this.lease.address,amount,{from:accounts[2]});
    await this.lease.startMining(id,{from:accounts[2]});
    assert.equal((await this.emb.balanceOf(accounts[2])).toString(),(amount*0.999).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(amount*0.999).toString());

    await increaseTimeTo(latestTime() + duration.seconds(DURATION+1));
    await this.lease.retrieveEMB(id,{from:taker});
    await this.emb.transfer(accounts[2],amount,{from:taker});
    await this.emb.transfer(taker,amount,{from:accounts[2]});

    assert.equal((await this.emb.balanceOf(maker)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(this.lease.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(await this.emb.totalSupply()).minus(0).toString());
  });

  it('should be able to place an order for LEMB, and fulfill a partial amount', async function(){
    let price = web3.utils.toWei('1','ether'), amount = 2*Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    let tokenId = await this.lemb.tokenOfOwnerByIndex(maker,0);

    await this.existingLease.placeOrder(price, amount, true, DURATION, DURATION - 1000, 0,fromUtf8("hello"),{from: accounts[2],value:amount*price/Math.pow(10,8)});
    //
    await this.lemb.approve(this.existingLease.address,tokenId,{from:maker});
    await this.existingLease.takeOrder(1,amount/2, tokenId,fromUtf8("hello"),{from:maker});

    let owner = await this.lemb.ownerOf(tokenId);

    assert.equal(owner,maker);
    assert.equal((await this.lemb.getAmountForUser(this.existingLease.address)).toString(),(0).toString());
    assert.equal((await this.lemb.getAmountForUser(maker)).toString(),(99800000).toString());
    assert.equal((await this.lemb.getAmountForUser(accounts[2])).toString(),(99900000).toString());
  });

  it('should be able to place an order with LEMB, and fulfill a partial amount', async function(){
    let price = web3.utils.toWei('1','ether'), amount = 2*Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];

    await this.lease.placeOrder(price, amount, demand, DURATION,fromUtf8("hello"),{from:maker,value:amount*price/Math.pow(10,8)});
    await this.emb.approve(this.lease.address,amount,{from:taker});

    let id = await this.lease.getNewId() - 1;

    await this.lease.takeOrder(id,amount,fromUtf8("hello"),{from:taker});

    let tokenId = await this.lemb.tokenOfOwnerByIndex(maker,0);

    await this.lemb.approve(this.existingLease.address,tokenId,{from:maker});

    amount = amount * 0.999;

    await this.existingLease.placeOrder(price, amount, false, DURATION, 0, tokenId,fromUtf8("hello"),{from: maker});

    let owner = await this.lemb.ownerOf(tokenId);

    await this.existingLease.takeOrder(1,amount/2, 0,fromUtf8("hello"),{from:accounts[2],value:amount/2*price/Math.pow(10,8)});

    assert.equal(owner,this.existingLease.address);

    assert.equal((await this.lemb.getAmountForUser(this.existingLease.address)).toString(),(amount/2).toString());
    assert.equal((await this.lemb.getAmountForUser(maker)).toString(),(0).toString());
    assert.equal((await this.lemb.getAmountForUser(accounts[2])).toString(),(amount/2*0.999).toString());
  });

  //
  function padToBytes32(n) {
      while (n.length < 24) {
          n = n + "0";
      }
      return "0x" + n;
  }

  function fromUtf8(str) {
      str = utf8.encode(str);
      var hex = "";
      for (var i = 0; i < str.length; i++) {
          var code = str.charCodeAt(i);
          if (code === 0) {
              break;
          }
          var n = code.toString(16);
          hex += n.length < 2 ? '0' + n : n;
      }

      return padToBytes32(hex);
  };
  //
  it('should be able to purchase Vanity and sell it', async function(){
    let price = web3.utils.toWei('1','ether'), amount = 100*Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];
    let vanityText = fromUtf8("ARJUNRAJJAIN");

    // await this.emb.approve(this.emb.address,amount,{from:taker});
    // assert.equal(await this.emb.allowance(taker,this.emb.address),amount);
    await this.emb.purchaseVanity(fromUtf8("aRUNRAJJAIN"),{from:taker}).should.be.rejectedWith(EVMRevert);

    await this.emb.purchaseVanity(fromUtf8(" RUNRAJJAIN"),{from:taker}).should.be.rejectedWith(EVMRevert);

    await this.emb.purchaseVanity(fromUtf8("RUNRAJJAIN"),{from:taker}).should.be.rejectedWith(EVMRevert);

    await this.emb.purchaseVanity(fromUtf8("AR UNRA-JAIN"),{from:taker}).should.be.rejectedWith(EVMRevert);

    await this.emb.purchaseVanity(fromUtf8("ABCDEFGHIJKL"),{from:taker});

    await this.emb.purchaseVanity(vanityText,{from:taker});
    //
    let owner = await this.emb.getVanityOwner(vanityText);
    assert.equal(owner,taker);

    await this.emb.approveVanity(this.vanityExchange.address,vanityText,{from:taker});

    await this.vanityExchange.placeOrder(price,vanityText,false,fromUtf8('blah'),{from:taker});

    owner = await this.emb.getVanityOwner(vanityText);
    assert.equal(owner,this.vanityExchange.address);

    await this.vanityExchange.takeOrder(1,vanityText,{from:maker,value:price});

    owner = await this.emb.getVanityOwner(vanityText);
    assert.equal(owner,maker);
  });


  it('should be able to place an order for a vanity address', async function(){
    let price = web3.utils.toWei('1','ether'), amount = 100*Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[0];
    let vanityText = fromUtf8("ARJUNRAJJAIN");

    await this.emb.approve(this.emb.address,amount,{from:taker});
    assert.equal(await this.emb.allowance(taker,this.emb.address),amount);

    await this.emb.purchaseVanity(vanityText,{from:taker});
    //
    let owner = await this.emb.getVanityOwner(vanityText);
    assert.equal(owner,taker);

    await this.vanityExchange.placeOrder(price,vanityText,true,fromUtf8('blah'),{from:maker,value:price});

    await this.emb.approveVanity(this.vanityExchange.address,vanityText,{from:taker});
    await this.vanityExchange.takeOrder(1,vanityText,{from:taker});

    owner = await this.emb.getVanityOwner(vanityText);
    assert.equal(owner,maker);
  });

  it("should take a demand of EMB", async function() {
    let price = web3.utils.toWei('1','ether'), amount = Math.pow(10,8), demand = true,  maker = accounts[1], taker = accounts[2];

    await this.emb.transfer(taker,amount,{from:accounts[0]});
    let van = fromUtf8("hello");
    await this.embExchange.placeOrder(price, amount, demand,van, {from:maker,value:amount*price/Math.pow(10,8)});

    await this.emb.approve(this.embExchange.address,amount,{from:taker});

    let id = await this.embExchange.getNewId() - 1;

    await this.embExchange.takeOrder(id,amount,van,{from:taker});

    assert.equal((await this.emb.balanceOf(maker)).toString(),(amount*0.999).toString());
    assert.equal((await this.emb.balanceOf(accounts[0])).toString(),(await this.emb.totalSupply()).minus(amount).add(amount*.001).toString());

    assert.equal((await this.emb.balanceOf(this.embExchange.address)).toString(),(0).toString());
    assert.equal((await this.emb.balanceOf(taker)).toString(),(0));
  });

});
