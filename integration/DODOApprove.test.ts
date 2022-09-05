import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, Signer, BigNumber } from 'ethers';
import chai from 'chai';
import { solidity } from "ethereum-waffle";
chai.use(solidity);

describe('DODOApprove: init with normal proxy', function () {
  let dodoApprove: Contract;
  let token1: Contract;
  let alice: Signer, bob: Signer, proxy1: Signer, proxy2: Signer;
  let aliceAddr: string, bobAddr: string, proxy1Addr: string, proxy2Addr: string;

  const BIG_NUMBER_1E18 = BigNumber.from(10).pow(18)

  beforeEach(async () => {
    const DODOApprove = await ethers.getContractFactory('DODOApprove');
    dodoApprove =  await DODOApprove.deploy();
    await dodoApprove.deployed();

    [, alice, bob, proxy1, proxy2] = await ethers.getSigners();
    aliceAddr = await alice.getAddress();
    bobAddr = await bob.getAddress();
    proxy1Addr = await proxy1.getAddress();
    proxy2Addr = await proxy2.getAddress();

    await dodoApprove.init(aliceAddr, proxy1Addr);
    expect(await dodoApprove._OWNER_()).eq(aliceAddr);
    expect(await dodoApprove._DODO_PROXY_()).eq(proxy1Addr);

    const ERC20Mock = await ethers.getContractFactory('ERC20Mock');
    token1 = await ERC20Mock.deploy("Token1", "tk1");
    await token1.transfer(aliceAddr, BIG_NUMBER_1E18.mul(100));
    expect(await token1.balanceOf(aliceAddr)).eq(BIG_NUMBER_1E18.mul(100));
  });

  it('should be able to get proxy name', async () => {
    expect(await dodoApprove.getDODOProxy()).eq(proxy1Addr);
  }); 

  it('should be able to set new proxy after 3 days', async () => {
    await dodoApprove.connect(alice).unlockSetProxy(proxy2Addr);
    await ethers.provider.send('evm_increaseTime', [3 * (24 * 60 * 60)]);
    await dodoApprove.connect(alice).setDODOProxy();
    expect(await dodoApprove._DODO_PROXY_()).eq(proxy2Addr);
  });

  it('should not be able to set new proxy before 3 days', async () => {
    await dodoApprove.connect(alice).unlockSetProxy(proxy2Addr);
    await ethers.provider.send('evm_increaseTime', [2 * (24 * 60 * 60)]);
    await expect(dodoApprove.connect(alice).setDODOProxy()).to.be.revertedWith('SetProxy is timelocked');
    expect(await dodoApprove._DODO_PROXY_()).eq(proxy1Addr);
  });

  it('should be able to claim tokens by proxy', async () => {
    await token1.connect(alice).approve(dodoApprove.address, BIG_NUMBER_1E18.mul(50));
    await dodoApprove.connect(proxy1).claimTokens(token1.address, aliceAddr, bobAddr, BIG_NUMBER_1E18.mul(50));
    expect(await token1.balanceOf(bobAddr)).eq(BIG_NUMBER_1E18.mul(50));
  });
})

describe('DODOApprove: init with address(0) as proxy', function () {
  let dodoApprove: Contract;
  let alice: Signer, proxy1: Signer, proxy2: Signer;
  let aliceAddr: string, proxy1Addr: string, proxy2Addr: string;
  let addressZero = ethers.constants.AddressZero;

  beforeEach(async () => {
    const DODOApprove = await ethers.getContractFactory('DODOApprove');
    dodoApprove =  await DODOApprove.deploy();
    await dodoApprove.deployed();

    [, alice, proxy1, proxy2] = await ethers.getSigners();
    aliceAddr = await alice.getAddress();
    proxy1Addr = await proxy1.getAddress();
    proxy2Addr = await proxy2.getAddress();

    await dodoApprove.init(aliceAddr, addressZero);
    expect(await dodoApprove._OWNER_()).eq(aliceAddr);
    expect(await dodoApprove._DODO_PROXY_()).eq(addressZero);
  });

  it('should be able to set new proxy after 24 hours', async () => {
    await dodoApprove.connect(alice).unlockSetProxy(proxy2Addr);
    await ethers.provider.send('evm_increaseTime', [1 * (24 * 60 * 60)]);
    await dodoApprove.connect(alice).setDODOProxy();
    expect(await dodoApprove._DODO_PROXY_()).eq(proxy2Addr);
  });

  it('should not be able to set new proxy before 24 hours', async () => {
    await dodoApprove.connect(alice).unlockSetProxy(proxy2Addr);
    await ethers.provider.send('evm_increaseTime', [0.5 * (24 * 60 * 60)]);
    await expect(dodoApprove.connect(alice).setDODOProxy()).to.be.revertedWith('SetProxy is timelocked');
    expect(await dodoApprove._DODO_PROXY_()).eq(addressZero);
  });
})