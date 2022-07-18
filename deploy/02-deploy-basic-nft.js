const { network } = require("hardhat")
const { developmentChains} = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

module.exports = async function ({ getNamedAccounts, deployments }) {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    log("----------------------------------------")
    const BasicNft = await deploy("BasicNft", {
        from: deployer,
        args: [],
        log: true,
        waitConfirmations: network.config.blockConfirmations || 1,
    })
    log("----------------------------------------")
    log(`BasicNft contract deployed at: ${BasicNft.address}`)

    //verifying the contract
    //verifying the contract on rinkeby.etherscan.io
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        log("verifying...")
        await verify(BasicNft.address, [])
        log("Contract Verified on Etherscan...")
    }
}

module.exports.tags = ["all", "BasicNft", "main"]
