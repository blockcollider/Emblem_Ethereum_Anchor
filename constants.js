const BigNumber = require('bignumber.js');

module.exports = function(web3) {

  let bcexponent = (new BigNumber(10)).pow(8);
  return {
    name: "Emblem",
    ticker : "EMB",
    decimals : 8,
    supply : (new BigNumber(300000000)).times(bcexponent),
    freezeDuration : 0
  }
}
