const path = require('path');
const envPath = path.join(__dirname, '.env');
require('dotenv').config({ path: envPath });

require('hardhat-deploy');
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-etherscan");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
	const accounts = await ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
	defaultNetwork: "hardhat",
	networks: {
		rinkeby: {
			url: `https://rinkeby.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
			accounts: [process.env.PK],
			chainId: 4,
			gas: "auto",
			gasPrice: 3100000000,
			gasMultiplier: 1.2
		},
	},
	solidity: {
		compilers: [
			{
				version: "0.8.10",
				settings: {
					optimizer: {
						enabled: true,
						runs: 100000
					}
				}
			}
		],
	},
	paths: {
		sources: "./contracts",
		tests: "./test",
		cache: "./cache",
		artifacts: "./artifacts"
	},
	mocha: {
		timeout: 360000
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY, // ETH Mainnet
		// apiKey: process.env.FANTOM_API_KEY, // FANTOM Mainnet
		// apiKey: process.env.POLYGON_API_KEY, // ETH Mainnet
		// apiKey: process.env.HECO_API_KEY, // HECO Mainnet
		// apiKey: process.env.BSCSCAN_API_KEY // BSC
	},
};

