var Migrations = artifacts.require("Migrations");

module.exports = function(deployer,network,accounts) {
  let wallet = accounts[0];
  console.log({wallet})
  deployer.deploy(Migrations,{from:wallet});
};
