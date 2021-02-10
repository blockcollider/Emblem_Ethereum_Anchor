// Returns the time of the last mined block in seconds
async function latestTime () {
  return (await web3.eth.getBlock('latest')).timestamp;
}

module.exports = latestTime
