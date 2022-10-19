import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, Signer, BigNumber } from 'ethers';
import chai from 'chai';
import { BigNumber as LocBN} from 'bignumber.js'
import { solidity } from "ethereum-waffle";
import { equal } from 'assert';
chai.use(solidity);

// TODO add approve whitelist test
// TODO add attack data test 
describe('DODORouteProxy', function () {
  let weth: Contract;
  let dodoApprove: Contract;
  let dodoApproveProxy: Contract;
  let dodoRouteProxy: Contract;
  let mockAdapter: Contract;
  let mockAdapter2_w: Contract, mockAdapterw_2: Contract, mockAdapter3_2:Contract;
  let token1: Contract, token2: Contract, token3: Contract;
  let alice: Signer, bob: Signer, proxy1: Signer, broker: Signer;
  let aliceAddr: string, bobAddr: string, proxy1Addr: string, brokerAddr: string;

  const BIG_NUMBER_1E18 = BigNumber.from(10).pow(18)
  const BIG_NUMBER_1E15 = BigNumber.from(10).pow(15)
  const _ETH_ = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

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

    token3 = await ERC20Mock.deploy("Token3", "tk3");
    await token3.transfer(aliceAddr, BIG_NUMBER_1E18.mul(100));
    await token3.transfer(bobAddr, BIG_NUMBER_1E18.mul(100));
    expect(await token3.balanceOf(aliceAddr)).eq(BIG_NUMBER_1E18.mul(100));

    console.log("ok2")
    
    //create mock adapter， token1 -token2
    const MockAdapter = await ethers.getContractFactory('MockAdapter');
    await weth.connect(alice).deposit({value: ethers.utils.parseEther("100.0")})
    
    mockAdapter = await MockAdapter.deploy(token1.address, token2.address, BIG_NUMBER_1E18.toString());
    await mockAdapter.deployed();
    await token1.transfer(mockAdapter.address, BIG_NUMBER_1E18.mul(1000).toString());
    await token2.transfer(mockAdapter.address, BIG_NUMBER_1E18.mul(1000).toString());
    await mockAdapter.connect(alice).update();

    mockAdapter2_w = await MockAdapter.deploy(token2.address, weth.address, BIG_NUMBER_1E15.mul(50).toString()); // 0.056
    await mockAdapter2_w.deployed();
    await weth.connect(alice).transfer(mockAdapter2_w.address, BIG_NUMBER_1E18.mul(20).toString());
    await token2.transfer(mockAdapter2_w.address, BIG_NUMBER_1E18.mul(1000).toString());
    await mockAdapter2_w.connect(alice).update();

    mockAdapterw_2 = await MockAdapter.deploy(weth.address, token2.address,BIG_NUMBER_1E18.mul(20).toString()); //20
    await mockAdapterw_2.deployed();
    await weth.connect(alice).transfer(mockAdapterw_2.address, BIG_NUMBER_1E18.mul(20).toString());
    await token2.transfer(mockAdapterw_2.address, BIG_NUMBER_1E18.mul(1000).toString());
    await mockAdapterw_2.connect(alice).update();

    mockAdapter3_2 = await MockAdapter.deploy(token3.address, token2.address, BIG_NUMBER_1E15.mul(100).toString()); //0.1
    await mockAdapter3_2.deployed();
    await token3.transfer(mockAdapter3_2.address, BIG_NUMBER_1E18.mul(1000).toString());
    await token2.transfer(mockAdapter3_2.address, BIG_NUMBER_1E18.mul(1000).toString());
    await mockAdapter3_2.connect(alice).update();

    console.log("ok3")
    // approve
    await token1.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token2.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token3.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token1.connect(bob).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token2.connect(bob).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    await token3.connect(bob).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(1000).toString())
    
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
   // token-token
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
    expect(etherToNumber(afterBalance.toString()) == 100.996, "mixSwap token-token failed")
    console.log("mixSwap bob token-token:", etherToNumber(afterBalance.toString()), afterReceiver, afterBroker)

    // eth -token
    await dodoRouteProxy.connect(bob).mixSwap(
      _ETH_,
      token2.address,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      [mockAdapter2_w.address],
      [mockAdapter2_w.address],
      [mockAdapter2_w.address, dodoRouteProxy.address],
      1,
      [feeData],
      feeData,
      "99999999999",

      {value: ethers.utils.parseEther("1.0")}
    )
    afterBalance = await token2.balanceOf(bobAddr)
    afterReceiver = await token2.balanceOf(proxy1Addr)
    afterBroker = await token2.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance)== 101.0458, "mixSwap eth-token failed")
    console.log("mixSwap bob eth-token:", etherToNumber(afterBalance), afterReceiver, afterBroker)

    //token -eth
    await dodoRouteProxy.connect(bob).mixSwap(
      token2.address,
      _ETH_,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      [mockAdapterw_2.address],
      [mockAdapterw_2.address],
      [mockAdapterw_2.address, dodoRouteProxy.address],
      1,
      [feeData],
      feeData,
      "99999999999",
    )
    afterBalance = await ethers.provider.getBalance(bobAddr)
    afterReceiver = await token2.balanceOf(proxy1Addr)
    afterBroker = await token2.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance) > 10018, "mixSwap token-eth failed")
    console.log("mixSwap bob token-eth:", etherToNumber(afterBalance), afterReceiver, afterBroker)
  });

  it('multi swap', async () => {
    let totalWeight = 100
    console.log(brokerAddr, aliceAddr)
    let abiCoder = new ethers.utils.AbiCoder();
    let feeData = await abiCoder.encode(["address", "uint256"], [brokerAddr, "2000000000000000"])

    let poolEdi = 2, weight = totalWeight, dire = 0;
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
        //[20],
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
    expect(etherToNumber(afterBalance)== 100.996, "multiSwap eth-token failed")
    console.log("multiSwap bob:", etherToNumber(afterBalance.toString()), afterReceiver, afterBroker)

    //token - eth 
    let poolEdi2 = 2, weight2 = totalWeight / 2, dire2 = 0;
    let mixPara2 = (dire2 << 17) + (weight2 << 9) + poolEdi2;
    let sequence2_1 = await abiCoder.encode(["address", "address", "uint256", "bytes"], [mockAdapter2_w.address, mockAdapter2_w.address, mixPara2, feeData])

    let poolEdi3 = 1, weight3 = totalWeight / 2, dire3 = 1;
    let mixPara3 = (dire3 << 17) + (weight3 << 9) + poolEdi3;
    let sequence2_2 = await abiCoder.encode(["address", "address", "uint256", "bytes"], [mockAdapterw_2.address, mockAdapterw_2.address, mixPara3, feeData])

    await dodoRouteProxy.connect(bob).dodoMutliSwap(
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        //[20, 20],
        [0, 1, 3],
        [token1.address, token1.address, token2.address, weth.address, _ETH_],
        [mockAdapter.address, dodoRouteProxy.address, dodoRouteProxy.address],
        [sequenceOne, sequence2_1, sequence2_2],
        feeData,
        "99999999999"
    )
    afterBalance = await ethers.provider.getBalance(bobAddr)
    afterReceiver = await weth.balanceOf(proxy1Addr)
    afterBroker = await weth.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance) > 10038, "multiSwap token-eth failed")
    console.log("multiSwap bob token-eth:", etherToNumber(afterBalance.toString()), afterReceiver, afterBroker)

    // eth-token
    await dodoRouteProxy.connect(alice).changeTotalWeight(120);
    totalWeight = 120;
    beforeBob = await token2.balanceOf(bobAddr)
    let poolEdiTwo = 1, weightTwo = totalWeight, direTwo = 0;
    let mixParaTwo = (direTwo << 17) + (weightTwo << 9) + poolEdiTwo;
    let sequenceTwo = await abiCoder.encode(["address", "address", "uint256", "bytes"], [mockAdapterw_2.address, mockAdapterw_2.address, mixParaTwo, feeData])
    await dodoRouteProxy.connect(bob).dodoMutliSwap(
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        //[20],
        [0, 1],
        [_ETH_, weth.address, token2.address],
        [mockAdapterw_2.address, dodoRouteProxy.address],
        [sequenceTwo],
        feeData,
        "99999999999",

        {value: ethers.utils.parseEther("1.0")}
    )
    afterBalance = await token2.balanceOf(bobAddr)
    afterReceiver = await token2.balanceOf(proxy1Addr)
    afterBroker = await token2.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance) == 101.0458, "multiSwap eth-token failed")
    console.log("multiSwap bob:", etherToNumber(afterBalance.toString()), etherToNumber(beforeBob), afterReceiver, afterBroker)
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
   // token -token
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
    expect(etherToNumber(afterBalance) == 100.996, "externalSwap token-token failed")
    console.log("externalSwap bob:", etherToNumber(afterBalance), afterReceiver, afterBroker)
    
    //token -eth

    await dodoRouteProxy.connect(alice).addWhiteList(mockAdapter2_w.address);
    await dodoRouteProxy.connect(alice).addApproveWhiteList(mockAdapter2_w.address);
    beforeBob = await ethers.provider.getBalance(bobAddr)
    let callDataETH = itf.encodeFunctionData("externalSwap", [dodoRouteProxy.address, token2.address, weth.address, BIG_NUMBER_1E18.mul(1).toString()])
    await dodoRouteProxy.connect(bob).externalSwap(
      token2.address,
      _ETH_,
      mockAdapter2_w.address,
      mockAdapter2_w.address,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      feeData,
      callDataETH,
      "99999999999"
    )
    afterBalance = await ethers.provider.getBalance(bobAddr)
    afterReceiver = await token2.balanceOf(proxy1Addr)
    afterBroker = await token2.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance) - etherToNumber(beforeBob) > 0.04, "externalSwap token - eth failed")
    console.log("externalSwap bob token-eth:", etherToNumber(afterBalance) - etherToNumber(beforeBob), afterReceiver, afterBroker)

    //eth-token

    beforeBob = await token2.balanceOf(bobAddr)
    await dodoRouteProxy.connect(alice).addWhiteList(mockAdapterw_2.address);
    await dodoRouteProxy.connect(alice).addApproveWhiteList(mockAdapterw_2.address);
    let callData2 = itf.encodeFunctionData("externalSwap", [dodoRouteProxy.address, _ETH_, token2.address, BIG_NUMBER_1E18.mul(1).toString()])
    await dodoRouteProxy.connect(bob).externalSwap(
      _ETH_,
      token2.address,
      mockAdapterw_2.address,
      mockAdapterw_2.address,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      feeData,
      callData2,
      "99999999999",

      {value: ethers.utils.parseEther("1.0")}
    )
    afterBalance = await token2.balanceOf(bobAddr)
    afterReceiver = await token2.balanceOf(proxy1Addr)
    afterBroker = await token2.balanceOf(brokerAddr)
    expect(etherToNumber(afterBalance) == 19.92, "externalSwap eth - token failed")
    console.log("externalSwap bob eth-token:", etherToNumber(afterBalance) - etherToNumber(beforeBob), afterReceiver, afterBroker)
  }); 

  it("external failed test",async () => {

    let abiCoder = new ethers.utils.AbiCoder();
    let feeData = await abiCoder.encode(["address", "uint256"], [brokerAddr, "2000000000000000"])

    let ABI = ["function externalSwap(address to, address fromToken, address toToken, uint256 fromAmount)"]
    let itf = new ethers.utils.Interface(ABI)

    
    await dodoRouteProxy.connect(alice).addApproveWhiteList(mockAdapterw_2.address);
    await dodoRouteProxy.connect(alice).addWhiteList(mockAdapterw_2.address);
    let callData2 = itf.encodeFunctionData("externalSwap", [dodoRouteProxy.address, _ETH_, token2.address, BIG_NUMBER_1E18.mul(1).toString()])
    await dodoRouteProxy.connect(bob).externalSwap(
      _ETH_,
      token2.address,
      mockAdapterw_2.address,
      mockAdapterw_2.address,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      feeData,
      callData2,
      "99999999999",

      {value: ethers.utils.parseEther("1.0")}
    )

    await dodoRouteProxy.connect(alice).removeApproveWhiteList(mockAdapterw_2.address);
    await expect(
      dodoRouteProxy.connect(bob).externalSwap(
        _ETH_,
        token2.address,
        mockAdapterw_2.address,
        mockAdapterw_2.address,
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        feeData,
        callData2,
        "99999999999",
  
        {value: ethers.utils.parseEther("1.0")}
      )
    ).revertedWith(
      "DODORouteProxy: Not Whitelist Appprove Contract"
    )
    
    await dodoRouteProxy.connect(alice).removeWhiteList(mockAdapterw_2.address);
    await expect(
      dodoRouteProxy.connect(bob).externalSwap(
        _ETH_,
        token2.address,
        mockAdapterw_2.address,
        mockAdapterw_2.address,
        BIG_NUMBER_1E18.mul(1).toString(),
        "1",
        feeData,
        callData2,
        "99999999999",
  
        {value: ethers.utils.parseEther("1.0")}
      )
    ).revertedWith(
      "DODORouteProxy: Not Whitelist Contract"
    )
    

    await dodoRouteProxy.connect(alice).addWhiteList(mockAdapter.address);
    await dodoRouteProxy.connect(alice).addApproveWhiteList(mockAdapter.address);

    let ABIFailed = ["function externalSwapFail(address to, address fromToken, address toToken, uint256 fromAmount)"]
    let itfFailed = new ethers.utils.Interface(ABIFailed)
    let callDataFailed = itfFailed.encodeFunctionData("externalSwapFail", [dodoRouteProxy.address, _ETH_, token2.address, BIG_NUMBER_1E18.mul(1).toString()])
    await expect(dodoRouteProxy.connect(bob).externalSwap(
      token1.address,
      token2.address,
      mockAdapter.address,
      mockAdapter.address,
      BIG_NUMBER_1E18.mul(1).toString(),
      "1",
      feeData,
      callDataFailed,
      "99999999999"
    )).revertedWith(
      "external swap failed"
    )

  })

  it("superWithdraw", async() => {
    await token1.connect(bob).transfer(dodoRouteProxy.address, BIG_NUMBER_1E18.mul(1).toString())
    let token1Amount = await token1.balanceOf(dodoRouteProxy.address)
    expect(token1Amount.eq(BIG_NUMBER_1E18.mul(1)))

    let beforeProxy = await token1.balanceOf(proxy1Addr)
    await dodoRouteProxy.connect(alice).superWithdraw(token1.address)
    let afterProxy = await token1.balanceOf(proxy1Addr)
    expect((etherToNumber(afterProxy) - etherToNumber(beforeProxy)) == (Number(1)))

    await alice.sendTransaction({
      to: dodoRouteProxy.address,
      value: ethers.utils.parseEther("1.0")
    })
    let ethAmount = await ethers.provider.getBalance(dodoRouteProxy.address)
    expect(ethAmount.eq(BIG_NUMBER_1E18.mul(1)))

    beforeProxy = await ethers.provider.getBalance(proxy1Addr)
    await dodoRouteProxy.connect(alice).superWithdraw(_ETH_)
    afterProxy = await ethers.provider.getBalance(proxy1Addr)
    expect((etherToNumber(afterProxy) - etherToNumber(beforeProxy)) == (Number(1)))
  })
})

export function etherToNumber(utilsN: BigNumber) {
  return Number(ethers.utils.formatEther(utilsN).toString())
}


