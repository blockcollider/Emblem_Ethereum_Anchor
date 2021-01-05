require('babel-register');
require('babel-polyfill');

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys:{
    etherscan:process.env.ETHERSCAN
  },
  networks: {
  "development": {
    network_id: '*',
    host: "localhost",
    port: 7545,
    gas: 6721975
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
      version:'0.4.24',
      optimizer: {
        enabled: true,
        runs: 200
      }
    },
  },
  "config": {
          "chainId": 42,
          "homesteadBlock": 0,
          "eip155Block": 0,
          "eip158Block": 0
      }
};
