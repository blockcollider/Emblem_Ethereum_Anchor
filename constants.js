
module.exports = function(web3) {
  let contributors = [];
  let contributorBalances = [];
  let contributorsMap = {};
  let bcexponent = (new web3.BigNumber(10)).pow(8);
  return {
    name: "Emblem",
    ticker : "EMB",
    decimals : 8,
    supply : (new web3.BigNumber(300000000)).mul(bcexponent),
    freezeDuration : 0
  }
}
