// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { FusePoolDirectory, CTokenInterface, ComptrollerInterface } from "./interfaces/IRari.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";
import { IRollupProcessor } from "../../interfaces/IRollupProcessor.sol";

// import 'hardhat/console.sol';

contract FuseBridge is IDefiBridge {
  using SafeMath for uint256;

  // /// @notice address that can approve fuse pools
  // address public immutable admin;

  address public immutable rollupProcessor;
  mapping(address => bool) approvedMarkets;
  mapping(address => address) marketUnderlying;


  constructor(address _rollupProcessor) public payable {
    rollupProcessor = _rollupProcessor;
    // admin = msg.sender;
  }

  receive() external payable {}

  // function getFusePoolMarket(uint256 _pool, address underlying) public view returns (address market){
  //   address _comptroller = fDirectory.pools(_pool).comptroller;
  //   market  = ComptrollerInterface(_comptroller).cTokensByUnderlying(underlying);
  // }
  // function isUnderlying(address market, address underlying) public view returns(bool){
  //   address _comptroller = fDirectory.pools(_pool).comptroller;
  //   return ComptrollerInterface(_comptroller).cTokensByUnderlying(underlying) == market;
  // }

  function approveFusePoolMarket(address _comptroller, address _underlying) external {
    // require(msg.sender == admin, "FuseBridge: NOT_AUTHORIZED");
    address market  = ComptrollerInterface(_comptroller).cTokensByUnderlying(_underlying);

    require(!approvedMarkets[market]);
    
    address[] memory cTokens = new address[](1);
    cTokens[0] = market;
    ComptrollerInterface(_comptroller).enterMarkets(cTokens);

    approvedMarkets[market] = true;
    marketUnderlying[market] = _underlying;
  }

  /// The outputvalues calc might be incorrect, def need to crosscheck
  /// @dev if auxData is "1" mint fuse tokens else redeem
  /// @param inputAssetA    for mints inputAssetA is underlying to deposit into fuse vault
  ///                       for redeem inputAssetA is fuse vault "fToken" 
  /// @param outputAssetA   for mints outputAssetA is fToken
  ///                       for redeem outputAssetA is fToken underlying 
  function convert(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 inputValue,
    uint256 interactionNonce,
    uint64 auxData
  )
    external
    payable
    override
    returns (
      uint256 outputValueA,
      uint256,
      bool isAsync
    )
  {
    require(msg.sender == rollupProcessor, "FuseBridge: INVALID_CALLER");
    isAsync = false;
    
    uint256 balanceBefore;
    uint256 balanceAfter;

    if( auxData == 1){
      require(approvedMarkets[outputAssetA.erc20Address], "FuseBridge: MARKET_NOT_APPROVED");
      require(marketUnderlying[outputAssetA.erc20Address] == inputAssetA.erc20Address, "FuseBridge: MARKET_UNDERLYING_MISMATCH");

      CTokenInterface fToken = CTokenInterface(outputAssetA.erc20Address);
      bool fEther = fToken.isCEther();
      balanceBefore = ERC20(address(fToken)).balanceOf(address(this)); 

      if(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20){
        require(!fEther);
        // Allow fToken to spend input token
        ERC20(inputAssetA.erc20Address).approve(address(fToken), inputValue);
        // mint fToken
        fToken.mint(inputValue);

      }else if(inputAssetA.assetType == AztecTypes.AztecAssetType.ETH){
        require(fEther);
        // mint fToken with ETH
        fToken.mint{value: inputValue}();
      }

      balanceAfter = ERC20(address(fToken)).balanceOf(address(this)); 


    } else {
      require(approvedMarkets[inputAssetA.erc20Address], "FuseBridge: MARKET_NOT_APPROVED");
      require(marketUnderlying[inputAssetA.erc20Address] == outputAssetA.erc20Address, "FuseBridge: MARKET_UNDERLYING_MISMATCH");

      CTokenInterface fToken = CTokenInterface(inputAssetA.erc20Address);
      balanceBefore = fToken.isCEther() ? address(this).balance : ERC20(outputAssetA.erc20Address).balanceOf(address(this)); 
      //redeem fToken
      fToken.redeem(inputValue);
      balanceAfter = fToken.isCEther() ? address(this).balance : ERC20(outputAssetA.erc20Address).balanceOf(address(this)); 

    }
    // outputValue = balanceAfter - balanceBefore
    outputValueA = balanceAfter.sub(balanceBefore);

    // approve output token to rollup-processor if output token is ERC20 token
    // send ETH to rollup-proceesor if output token is ETH
    if(outputAssetA.assetType == AztecTypes.AztecAssetType.ETH){
      // transfer eth to rollup-processor
      IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
    }else{
      ERC20(outputAssetA.erc20Address).approve(rollupProcessor, outputValueA);  
    }

  }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    uint256,
    uint64
  ) external payable override returns (uint256, uint256, bool) {
    require(false);
  }
}
