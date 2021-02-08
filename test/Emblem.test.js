var {increaseTimeTo, duration} = require('./helpers/increaseTime');
var latestTime = require('./helpers/latestTime')
var {EVMRevert} = require('./helpers/EVMRevert')
const BigNumber = require('bignumber.js');
var Emblem = artifacts.require("Emblem");
var LEMB = artifacts.require("LeasedEmblem");
var constants = require('../constants.js')(web3);

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bignumber')(BigNumber))
    .should();

contract('Emblem', async function(accounts) {

  beforeEach(async function () {
    Emblem.defaults({
      from: accounts[0],
      // gas: 472197
    })

    let e = {
      _name: constants.name,
      _ticker: constants.ticker,
      _decimal: constants.decimals,
      _supply: constants.supply,
      _wallet: accounts[0]
    }

    // this.token = await Emblem.new(e._name,e._ticker,e._decimal,e._supply,e._wallet);

	  // this.lemb = await LEMB.new("LEMB","LEMB");
	  this.token = await Emblem.new(e._name,e._ticker,e._decimal,e._supply,e._wallet);

    await increaseTimeTo(latestTime() + duration.days(1));
  });

  it("should have token details set", async function() {
    assert.equal(await this.token.name(), 'Emblem');
    assert.equal(await this.token.symbol(), 'EMB');
    assert.equal(await this.token.decimals(), 8);
    assert.equal((await this.token.totalSupply()).toString(),constants.supply.toString());
    // assert.equal((await this.token.balanceOf(accounts[0])).toString(), (await this.token.totalSupply()).minus(constants.sum).toString());
  });

  it("should be able to set ticker", async function() {
    await this.token.setTicker("NRG");
    assert.equal(await this.token.symbol(), 'NRG');
  });

  it("should not be able to set ticker", async function() {
    await this.token.setTicker("NRG",{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
  });

  it("should be able to transfer", async function() {
    await this.token.transfer(accounts[1], 2000,{from:accounts[0]});
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '2000');
    await this.token.transfer(accounts[0], 1000,{from:accounts[1]})
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
    assert.equal((await this.token.balanceOf(accounts[0])).toString(), (await this.token.totalSupply()).minus(1000).toString());
  });

  it("should not be able to transfer if balance is not enough", async function() {
    await this.token.transfer(accounts[0], 2000,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
  });

  it("should only allow the owner to freeze transfers",async function() {
    await increaseTimeTo(latestTime() + duration.days(1));
    await this.token.freezeTransfers(true,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[1], 1000)
    await increaseTimeTo(latestTime() + duration.days(1));
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
    await this.token.freezeTransfers(true);
    await this.token.transfer(accounts[1], 1000).should.be.rejectedWith(EVMRevert);
  });

  function padToBytes12(n) {
      while (n.length < 24) {
          n = "0" + n;
      }
      return n;
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

  it("should allow an external freezer to freeze an account", async function(){
    await this.token.transfer(accounts[1], 1000);
    await this.token.setExternalFreezer(accounts[2],true);
    await this.token.externalFreezeAccount(accounts[1],true,{from:accounts[2]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[2], 100,{from:accounts[1]});
    await this.token.freezeMe(true,{from:accounts[1]});
    assert.equal((await this.token.canFreeze(accounts[1])), true);

    await this.token.externalFreezeAccount(accounts[1],true,{from:accounts[2]});
    assert.equal((await this.token.isFrozen(accounts[1])), true);
    await this.token.transfer(accounts[2], 100,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
    await this.token.freezeMe(false,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
    await this.token.externalFreezeAccount(accounts[1],false,{from:accounts[2]});
    await this.token.freezeMe(false,{from:accounts[1]});
    assert.equal((await this.token.canFreeze(accounts[1])), false);
    assert.equal((await this.token.isFrozen(accounts[1])), false);

    await this.token.externalFreezeAccount(accounts[1],true,{from:accounts[2]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[2], 100,{from:accounts[1]});

    await this.token.setExternalFreezer(accounts[2],false);
    await this.token.freezeMe(true,{from:accounts[1]});
    await this.token.externalFreezeAccount(accounts[1],true,{from:accounts[2]}).should.be.rejectedWith(EVMRevert);

    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '800');
    assert.equal((await this.token.balanceOf(accounts[2])).toString(), '200');
  });

  it("should allow owner to freeze transfer an account and then unfreeze and allow for transfers to work again",async function() {
    await this.token.freezeAccount(accounts[1],true);
    await this.token.transfer(accounts[1], 1000)
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
    await this.token.transfer(accounts[0], 1000,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
    await this.token.freezeAccount(accounts[1],false);
    await this.token.transfer(accounts[0], 1000,{from:accounts[1]})
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '0');
  });

  it("should not allow another user to freeze an account",async function() {
    await this.token.freezeAccount(accounts[1],{from:accounts[2]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[1], 1000);
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
  });

});
