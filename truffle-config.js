require('babel-register');
require('babel-polyfill');
const HDWalletProvider = require("truffle-hdwallet-provider-privkey");

module.exports = {
  confirmations: 0, // # of confs to wait between deployments. (default: 0)
  skipDryRun: true,
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys:{
    etherscan:process.env.ETHERSCAN
  },
  networks: {
    confirmations: 0, // # of confs to wait between deployments. (default: 0)
    skipDryRun: true,
    'development': {
      network_id: '*',
      host: "localhost",
      port: 7545,
   },
   main: {
      confirmations: 0, // # of confs to wait between deployments. (default: 0)
      skipDryRun: true,
      from: '0x16673a035fb4f6e8e5fe1e50ae8d60376a9b04ed',
      provider: () => {
        let wallet = new HDWalletProvider(['d905ed4643b977a1385d2d248860e7ebf44273711e18f4635f853e85babf54dd'], 'https://mainnet.infura.io/v3/91bde5069afd459d9a0397ebc96e0da9')
        return wallet
      },
      network_id: 1,
      gasPrice: 140000000000
   },
   ropsten: {
      confirmations: 0, // # of confs to wait between deployments. (default: 0)
      skipDryRun: true,
      from: '0x16673a035fb4f6e8e5fe1e50ae8d60376a9b04ed',
      provider: function() {
       let wallet = new HDWalletProvider(['d905ed4643b977a1385d2d248860e7ebf44273711e18f4635f853e85babf54dd'], 'https://ropsten.infura.io/v3/e041a4fb9c564ceba008159781e924f6')
       return wallet
      },
      network_id: 3,
      gasPrice : 15000000000,
   },
   proxy: {
        host: "127.0.0.1",
        port: 9545,
        network_id: "*",
        gasPrice: 0
    },
   testrpc: {
      host: 'localhost',
      port: 8545,
      network_id: '*', // eslint-disable-line camelcase
    },
    ganache: {
      host: 'localhost',
      port: 7545,
      network_id: '*', // eslint-disable-line camelcase
    },
    "live": {
      network_id: 1,
      host: "127.0.0.1",
      port: 8545
    }
  },
  compilers:{
    solc: {
      version:'0.7.6'
    }
  },
};
