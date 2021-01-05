var EMB = artifacts.require("Emblem");
var LEMB = artifacts.require("LeasedEmblem");
var constants = require('../constants.js')(web3);

module.exports = function(deployer, network, accounts) {
  let wallet = accounts[0];
  let e = {
    _name: constants.name,
    _ticker: constants.ticker,
    _decimal: constants.decimals,
    _supply: constants.supply,
    _wallet: wallet
  }
  deployer.then(function() {
    return LEMB.new("L-EMB","L-EMB",{from:wallet});
  }).then(function(instance) {
    lemb = instance;
    return EMB.new(e._name,e._ticker,e._decimal,e._supply,e._wallet,lemb.address,{from:wallet});
  })
};
