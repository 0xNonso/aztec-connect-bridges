// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SecretVoter, GovernanceBravo } from "./SecretVoter.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";

// import 'hardhat/console.sol';

interface GovToken {
  function delegate(address delegatee) external;
}

contract VoteBridge is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;

  enum Status {
    Pending, 
    Executed, 
    NotExecuted
    }

  /// @notice supported Ids for voting. can be adjusted ie to only support 2 ids [1,2] 
  uint8[] supportID = [0,1,2];

  struct Interaction{
    uint proposalID;
    uint256 numVotes;
    address gov;
    address asset;
    bool finalised;
  }

  struct GovDetails{
    uint64 snapshot;
    uint64 startBlock;
    uint64 endBlock;
    bool approved;
    address voteAsset;
  }

  mapping(bytes32 => GovDetails) private govDetails;
  mapping(bytes32 => Status) govStatus;
  mapping(bytes32 => mapping(uint => address)) private secretVoter;
  mapping(uint256 => Interaction) interaction;


  constructor(address _rollupProcessor) payable {
    rollupProcessor = _rollupProcessor;
  }

  function gibSuffrage(address asset, address to) internal {
    GovToken(asset).delegate(to);
  }
  receive() external payable {}

  function approveVoting(address gov, address asset, uint _propId, uint64 _snapshot, uint64 _startBlock, uint64 _endBlock) external {
    bytes32 vHash = getVoteHash(gov, _propId);
    govDetails[vHash] = GovDetails({
      snapshot: _snapshot,
      startBlock: _startBlock,
      endBlock: _endBlock,
      approved: true,
      voteAsset: asset
    });
  }

  /// @dev deposits token which is delegated to a secret voter to vote then tokens are returned back
  /// @param inputAssetA token used for voting
  /// @param gov used to store governance address to vote
  /// @param outputAssetA token used for voting
  function convert(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata gov,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 inputValue,
    uint256 interactionNonce,
    uint64 data
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
    require(msg.sender == rollupProcessor, "VoteBridge: INVALID_CALLER");
    isAsync = true;

    Interaction storage persCache = interaction[interactionNonce];
    require(persCache.gov == address(0) && !persCache.finalised);

    /// expects data to be packed with voter's "choice" and "proposalID"
    (uint8 _support , uint256 _proposalId) = unpack(data);
    address _gov = gov.erc20Address;
    require(_gov != address(0));

    bytes32 vHash = getVoteHash(_gov, _proposalId);
    GovDetails memory govInfo = govDetails[vHash];
    require(govInfo.approved && block.timestamp < govInfo.snapshot);
    require(govInfo.voteAsset == inputAssetA.erc20Address);

    address sVoter = secretVoter[vHash][_support];
    if( sVoter == address(0)){
      SecretVoter voter = new SecretVoter();
      secretVoter[vHash][_support] = address(voter);
      sVoter = address(voter);
    }
    gibSuffrage(govInfo.voteAsset, sVoter);

    persCache.proposalID = _proposalId;
    persCache.asset = govInfo.voteAsset;
    persCache.numVotes = inputValue;
    persCache.gov = _gov;

    outputValueA = inputValue;
  }

  // function canFinalise(
  //   uint256 interactionNonce
  // ) external view override returns (bool) {
  //   return _canFinalise(interactionNonce);
  // }

  function _canFinalise(
    uint256 interactionNonce
  ) internal view returns (bool) {
    Interaction memory tempCache = interaction[interactionNonce];
    bytes32 vHash = getVoteHash(tempCache.gov, tempCache.proposalID);
    GovDetails memory govInfo = govDetails[vHash];
  
    return govInfo.approved && govInfo.startBlock >= block.timestamp && !tempCache.finalised;
  }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    uint256 interactionNonce,
    uint64
  ) external payable override returns (uint256, uint256, bool) {
    bool canFinalise = _canFinalise(interactionNonce);
    require(canFinalise);

    Interaction storage persCache = interaction[interactionNonce];
    address gov = persCache.gov;
    uint propID = persCache.proposalID;
    bytes32 vHash = getVoteHash(gov, propID);
    
    if(govStatus[vHash] == Status.Pending){
      if(block.timestamp <= govDetails[vHash].endBlock){
        _execute(vHash, gov, propID);
        govStatus[vHash] = Status.Executed;
      } else {
        govStatus[vHash] = Status.NotExecuted;
      }
    }
    persCache.finalised = true;
    IERC20(persCache.asset).approve(rollupProcessor, persCache.numVotes);
    IERC20(persCache.asset).transferFrom(address(this), rollupProcessor, persCache.numVotes);
  }

  function _execute(bytes32 vHash, address gov, uint256 propID) internal {
    require(govStatus[vHash] == Status.Pending);
    uint256 len = supportID.length;
    for(uint i = 0; i < len; ++i){
      address _secretVoter = secretVoter[vHash][i];
      if(_secretVoter != address(0)){
        (bool success, ) = _secretVoter.call(abi.encodeWithSignature("vote(address,uint8,uint256)", gov, supportID, propID));
        require(success);
      }
    }
  }
  function getVoteHash(address gov, uint propId) public view returns(bytes32){
    return keccak256(abi.encodePacked(gov,propId));
  }

  function pack(uint8 a, uint56 b) public view returns(uint64) {
    return (uint64(a) << 56) | b;
  }
  function unpack(uint64 c) public view returns(uint8 a, uint256 b){
    a = uint8(c >> 56 & 0xFF);
    b = uint256(c & 0x3FFFFFFFFFFFFF);
  }
}
