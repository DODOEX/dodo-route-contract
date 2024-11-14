import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { BSC_CONFIG as config } from "../config/all-config";
import { BigNumber } from "@ethersproject/bignumber";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  //await deployOffsetOracle();
  await verifyContract("0x2A35640ae08c079e98F9697967F6Dd3e46C3d9ca");

  async function deployOffsetOracle() {
    const offsetOracleAddr = await deployContract("offsetOracle", "OffsetOracle", []);
    sleep(10);
    config.deployedAddress["offsetOracle"] = offsetOracleAddr;
    verifyContract(offsetOracleAddr);
  }


  async function deployContract(name: string, contract: string, args: any[]) {
    if (!config.deployedAddress[name] || config.deployedAddress[name] == "") {
      const deployResult = await deploy(contract, {
        from: deployer,
        args: args,
        log: true,
      });
      return deployResult.address;
    } else {
      return config.deployedAddress[name];
    }
  }

  async function verifyContract(address: string, args?: any[]) {
    if (typeof args == 'undefined') {
      args = []
    }
    try {
      await hre.run("verify:verify", {
        address: address,
        constructorArguments: args,
      });
    } catch (e: any) {
      if (e.message != "Contract source code already verified") {
        throw(e)
      }
      console.log(e)
    }
  }


  // ---------- helper function ----------

  function padZeros(origin: number, count: number) {
    return origin.toString() + '0'.repeat(count);
  }

  function sleep(s: number) {
    return new Promise(resolve => setTimeout(resolve, s * 1000));
  }
};

export default func;
func.tags = ["MockERC20"];
