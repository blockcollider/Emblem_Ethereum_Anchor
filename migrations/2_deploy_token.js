var EMB = artifacts.require("Emblem");
var LEMB = artifacts.require("LeasedEmblem");
var constants = require('../constants.js')(web3);
var contributions = require('../contributors.json');

function errOut(msg) {
  return function() {
    console.log(msg, arguments);
  }
}

function padToBytes7(n) {
    while (n.length < 14) {
        n = "0" + n;
    }
    return n;
}

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
    return EMB.new(e._name,e._ticker,e._decimal,e._supply,e._wallet,{from:wallet});
  }).then(async function(instance) {
    const multiTransfer = async () => {
      emb = instance;
      let addr = await emb.balanceOf(wallet)
      let addressesAndAmounts = contributions.map(({address,balance}) => {
        return `${address}${padToBytes7(Math.round(balance*Math.pow(10,8)).toString(16))}`
      });
      let split = 240;
      for (let j = 1; j <= Math.ceil(contributions.length/split); j++){
        let addressesAndAmounts2 = addressesAndAmounts.filter((key,i)=>{
          return i >= (split * (j-1)) && i < split*j;
        });
        let tx = await emb.multiTransfer(addressesAndAmounts2,{from:wallet});
        console.log(j);
      }
      await emb.setVanityPurchaseReceiver(wallet,{from:wallet})
      return 'hello';
    }
    await multiTransfer()
    return true;
  })
};
