import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, Signer, BigNumber } from 'ethers';
import chai from 'chai';
import { solidity } from "ethereum-waffle";
chai.use(solidity);

// TODO add approve whitelist test
// TODO add attack data test 
describe('DODORouteProxy', function () {
  let weth: Contract;
  let dodoApprove: Contract;
  let dodoApproveProxy: Contract;
  let dodoRouteProxy: Contract;
  let mockAdapter: Contract;
  let token1: Contract, token2: Contract;
  let alice: Signer, bob: Signer, proxy1: Signer, broker: Signer;
  let aliceAddr: string, bobAddr: string, proxy1Addr: string, brokerAddr: string;

  const BIG_NUMBER_1E18 = BigNumber.from(10).pow(18)

  beforeEach(async () => {
    [, alice, bob, broker, proxy1] = await ethers.getSigners();
    aliceAddr = await alice.getAddress();
    bobAddr = await bob.getAddress();
    brokerAddr  = await broker.getAddress();
    proxy1Addr = await proxy1.getAddress();

    // pre-work
    const weth9 = await ethers.getContractFactory('WETH9');
    weth = await weth9.connect(alice).deploy();

    
    const DODOApprove = await ethers.getContractFactory('DODOApprove');
    dodoApprove =  await DODOApprove.connect(alice).deploy();

    const DODOApproveProxy = await ethers.getContractFactory('DODOApproveProxy');
    dodoApproveProxy =  await DODOApproveProxy.connect(alice).deploy(dodoApprove.address);
    await dodoApprove.init(aliceAddr, dodoApproveProxy.address);

    
    const DODORouteProxy = await ethers.getContractFactory('DODORouteProxy');
    dodoRouteProxy =  await DODORouteProxy.connect(alice).deploy(weth.address, dodoApproveProxy.address);
    await dodoApproveProxy.init(aliceAddr, [dodoRouteProxy.address]);

    
    // set route fee
    await dodoRouteProxy.connect(alice).changeRouteFeeRate("2000000000000000")
    await dodoRouteProxy.connect(alice).changeRouteFeeReceiver(proxy1Addr)
    console.log("ok")
    
    // create tokens
    const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
    token1 = await ERC20Mock.deploy("Token1", "tk1");
    await token1.transfer(aliceAddr, BIG_NUMBER_1E18.mul(100).toString());
    await token1.transfer(bobAddr, BIG_NUMBER_1E18.mul(100).toString());
    expect(await token1.balanceOf(aliceAddr)).eq(BIG_NUMBER_1E18.mul(100));

    token2 = await ERC20Mock.deploy("Token2", "tk2");
    await token2.transfer(aliceAddr, BIG_NUMBER_1E18.mul(100));
    await token2.transfer(bobAddr, BIG_NUMBER_1E18.mul(100));
    expect(await token2.balanceOf(aliceAddr)).eq(BIG_NUMBER_1E18.mul(100));

    console.log("ok2")
    
    //create mock adapter
    const MockAdapter = await ethers.getContractFactory('MockAdapter');
    
    mockAdapter = await MockAdapter.deploy(token1.address, token2.address, BIG_NUMBER_1E18.toString());
    await mockAdapter.deployed();

    await token1.transfer(mockAdapter.address, BIG_NUMBER_1E18.mul(1000).toString());
    await token2.transfer(mockAdapter.address, BIG_NUMBER_1E18.mul(1000).toString());
    await mockAdapter.connect(alice).update();

    console.log("ok3")
    // approve
    await token1.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token2.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token1.connect(bob).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token2.connect(bob).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    
  });

  

  // assetTo must to routeProxy
  it('mix swap', async () => {
    console.log(brokerAddr, aliceAddr)
    let abiCoder = new ethers.utils.AbiCoder();
    let feeData = await abiCoder.encode(["address", "uint256"], [brokerAddr, "2000000000000000"])

    console.log(feeData)
    /*
        function mixSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory mixAdapters,
        address[] memory mixPairs,
        address[] memory assetTo,
        uint256 directions,
        bytes[] memory moreInfos,
        bytes memory feeData,
        uint256 deadLine
    */
   let beforeBob = await token2.balanceOf(bobAddr)
    await dodoRouteProxy.connect(bob).mixSwap(
        token1.address,
        token2.address,
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        [mockAdapter.address],
        [mockAdapter.address],
        [mockAdapter.address, dodoRouteProxy.address],
        0,
        [feeData],
        feeData,
        "99999999999"
    )
    let afterBalance = await token2.balanceOf(bobAddr)
    let afterReceiver = await token2.balanceOf(proxy1Addr)
    let afterBroker = await token2.balanceOf(brokerAddr)
    console.log("mixSwap bob:", afterBalance, afterReceiver, afterBroker)
  });

  it('multi swap', async () => {
    console.log(brokerAddr, aliceAddr)
    let abiCoder = new ethers.utils.AbiCoder();
    let feeData = await abiCoder.encode(["address", "uint256"], [brokerAddr, "2000000000000000"])

    let poolEdi = 2, weight = 20, dire = 0;
    let mixPara = (dire << 17) + (weight << 9) + poolEdi;

    let sequenceOne = await abiCoder.encode(["address", "address", "uint256", "bytes"], [mockAdapter.address, mockAdapter.address, mixPara, feeData])
    /*
    function dodoMutliSwap(
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        uint256[] memory totalWeight, // TODO: fix totalWeight and del this param
        uint256[] memory splitNumber,  
        address[] memory midToken,
        address[] memory assetFrom,
        bytes[] memory sequence, 
        bytes memory feeData,
        uint256 deadLine
    )

    (address pool, address adapter, uint256 mixPara, bytes memory moreInfo) = abi
                        .decode(swapSequence[j], (address, address, uint256, bytes));
    */
   let beforeBob = await token2.balanceOf(bobAddr)
    await dodoRouteProxy.connect(bob).dodoMutliSwap(
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        [20],
        [0, 1],
        [token1.address, token2.address],
        [mockAdapter.address, dodoRouteProxy.address],
        [sequenceOne],
        feeData,
        "99999999999"
    )
    let afterBalance = await token2.balanceOf(bobAddr)
    let afterReceiver = await token2.balanceOf(proxy1Addr)
    let afterBroker = await token2.balanceOf(brokerAddr)
    console.log("multiSwap bob:", afterBalance, afterReceiver, afterBroker)
  });

  it('external swap', async () => {
    // set approve white list and swap white list
    await dodoRouteProxy.connect(alice).addWhiteList(mockAdapter.address);
    await dodoRouteProxy.connect(alice).addApproveWhiteList(mockAdapter.address);

    console.log(brokerAddr, aliceAddr)
    let abiCoder = new ethers.utils.AbiCoder();
    let feeData = await abiCoder.encode(["address", "uint256"], [brokerAddr, "2000000000000000"])

    let ABI = ["function externalSwap(address to, address fromToken, address toToken, uint256 fromAmount)"]
    let itf = new ethers.utils.Interface(ABI)
    let callData = itf.encodeFunctionData("externalSwap", [dodoRouteProxy.address, token1.address, token2.address, BIG_NUMBER_1E18.mul(1).toString()])

    /*
    function externalSwap(
        address fromToken,
        address toToken,
        address approveTarget,
        address swapTarget,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        bytes memory feeData,
        bytes memory callDataConcat,
        uint256 deadLine
    */
    let beforeBob = await token2.balanceOf(bobAddr)
    await dodoRouteProxy.connect(bob).externalSwap(
        token1.address,
        token2.address,
        mockAdapter.address,
        mockAdapter.address,
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        feeData,
        callData,
        "99999999999"
    )
    let afterBalance = await token2.balanceOf(bobAddr)
    let afterReceiver = await token2.balanceOf(proxy1Addr)
    let afterBroker = await token2.balanceOf(brokerAddr)
    console.log("externalSwap bob:", afterBalance, afterReceiver, afterBroker)
    
    
  }); 
})


