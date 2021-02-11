var {increaseTimeTo, duration} = require('./helpers/increaseTime');
var latestTime = require('./helpers/latestTime')
var {EVMRevert} = require('./helpers/EVMRevert')
const BigNumber = require('bignumber.js');
var Emblem = artifacts.require("Emblem");
var LEMB = artifacts.require("LeasedEmblem");
var constants = require('../constants.js')(web3);
var contributions = require('../contributors.json');

function padToBytes7(n) {
    while (n.length < 14) {
        n = "0" + n;
    }
    return n;
}

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bignumber')(BigNumber))
    .should();

contract('Emblem', async function(accounts) {

  beforeEach(async function () {
    Emblem.defaults({
      from: accounts[0]
    })

    let e = {
      _name: constants.name,
      _ticker: constants.ticker,
      _decimal: constants.decimals,
      _supply: constants.supply,
      _wallet: accounts[0]
    }

	  this.token = await Emblem.new(e._name,e._ticker,e._decimal,e._supply,e._wallet);

    await increaseTimeTo(await latestTime() + duration.days(1));
  });

  it("should have token details set", async function() {
    assert.equal(await this.token.name(), 'Emblem');
    assert.equal(await this.token.symbol(), 'EMB');
    assert.equal(await this.token.decimals(), 8);
    assert.equal((await this.token.totalSupply()).toString(),constants.supply.toString());
    // assert.equal((await this.token.balanceOf(accounts[0])).toString(), (await this.token.totalSupply()).minus(constants.sum).toString());
  });

  // it("should deploy correctly", async function() {
  //   let addressesAndAmounts = contributions.map(({address,balance}) => {
  //     return `${address}${padToBytes7(Math.round(balance*Math.pow(10,8)).toString(16))}`
  //   });
  //
  //   let split = 230;
  //   for (let j = 1; j <= Math.ceil(contributions.length/split); j++){
  //     let addressesAndAmounts2 = addressesAndAmounts.filter((key,i)=>{
  //       return i >= (split * (j-1)) && i < split*j;
  //     });
  //     await this.token.multiTransfer(addressesAndAmounts2);
  //   }
  //   await this.token.freezeTransfers(true)
  //   await this.token.transfer(accounts[1], 2000,{from:accounts[0]}).should.be.rejectedWith(EVMRevert);
  //
  //   for(let {address,balance} of contributions){
  //     assert.equal((await this.token.balanceOf(address)).toString(), Math.round(balance*Math.pow(10,8)));
  //   }
  // });

  it("should be able to transfer", async function() {
    await this.token.transfer(accounts[1], 2000,{from:accounts[0]});
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '2000');
    await this.token.transfer(accounts[0], 1000,{from:accounts[1]})
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
    let newsupply = (await this.token.totalSupply());
    assert.equal((await this.token.balanceOf(accounts[0])).toString(), (newsupply - 1000).toString());
  });

  it("should not be able to transfer if balance is not enough", async function() {
    await this.token.transfer(accounts[0], 2000,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
  });

  it("should only allow the owner to freeze transfers",async function() {
    await increaseTimeTo(await latestTime() + duration.days(1));
    await this.token.freezeTransfers(true,{from:accounts[1]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[1], 1000)
    await increaseTimeTo(await latestTime() + duration.days(1));
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
    await this.token.freezeTransfers(true);
    await this.token.transfer(accounts[1], 1000).should.be.rejectedWith(EVMRevert);
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
    await this.token.freezeAccount(accounts[1],true,{from:accounts[2]}).should.be.rejectedWith(EVMRevert);
    await this.token.transfer(accounts[1], 1000);
    assert.equal((await this.token.balanceOf(accounts[1])).toString(), '1000');
  });

});
