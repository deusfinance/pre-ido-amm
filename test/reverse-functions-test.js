const { expect } = require("chai");

describe("PreIDOToken", function() {
  it("Should reverse functions be correct!", async function() {
    const Power = await ethers.getContractFactory("Power");
    const power = await Power.deploy();
    await power.deployed();

    const _factory = "0x0000000000000000000000000000000000000001";
    const _ammID = 0;
    const _fee = 0;
    const _collateralAddress = "0x19875868EfC944561405EeEaBe153354ACA4D071";
    const _startBlock = 0;
    const _cw = "250000";
    const _collateralReserve = "";
    const _name = "Test PreIDO Token";
    const _symbol = "TPT";

    const PreIDOToken = await ethers.getContractFactory("PreIDOToken");
    const preIDOToken = await PreIDOToken.deploy(_factory, _ammID, _fee, _collateralAddress, power.address, _startBlock, _cw, _name, _symbol);
    await preIDOToken.deployed();

    

    expect().to.equal();
  });
});
