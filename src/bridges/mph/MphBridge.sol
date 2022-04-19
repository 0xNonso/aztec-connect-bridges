// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {DInterest} from "./interfaces/DInterest.sol";
import {IVesting} from "./interfaces/IVesting.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";

// import 'hardhat/console.sol';

contract MphBridge is IERC721Receiver, IDefiBridge {
    using SafeMath for uint256;

    address public immutable rollupProcessor;

    /// @notice 88mph vesting
    address public immutable mphVesting;

    /// @notice 88mph token address
    address public immutable mphToken;

    /// @notice gets latest nonce. For testing purpose
    uint256 public latestNonce;

    struct Interaction{
        uint64 depositID;
        address firbAddress;
        uint64 maturation;
        address underlying;
        bool finalised;
        uint256 amount;
    }

    mapping(uint256 => Interaction) interaction;

    constructor(address _rollupProcessor, address _mphVesting, address _mphToken) public payable{
        rollupProcessor = _rollupProcessor;
        mphVesting = _mphVesting;
        mphToken = _mphToken;
    }

    receive() external payable {}


    /// Mints FIRB on 88mph
    /// @param inputAssetA    token to deposit
    /// @param outputAssetA   FIRB to mint
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64 _maturation
    )
        external
        payable
        override
        returns (
        uint256,
        uint256,
        bool isAsync
        )
    {
        require(msg.sender == rollupProcessor, "MPH-Bridge: INVALID_CALLER");
        isAsync = true;

        address outputAsset = outputAssetA.erc20Address;
        address inputAsset = inputAssetA.erc20Address;

        IERC20(inputAsset).approve(outputAsset, inputValue);

        (uint64 depositId, ) = DInterest(outputAsset).deposit(inputValue, _maturation);
        DInterest.Deposit memory deposit = DInterest(outputAsset).getDeposit(depositId);

        uint256 nonce = getInteractionNonce(outputAsset, depositId);

        interaction[nonce].depositID = depositId;
        interaction[nonce].firbAddress = outputAsset;
        interaction[nonce].maturation = deposit.maturationTimestamp;
        interaction[nonce].amount = deposit.virtualTokenTotalSupply;
        interaction[nonce].underlying = inputAsset;

        latestNonce = nonce;

    }

    // function canFinalise(
    //     uint256 interactionNonce
    // ) external view returns (bool) {
    //     return _canFinalise(interactionNonce);
    // }
    function _canFinalise(
        uint256 interactionNonce
    ) internal view returns (bool) {
        Interaction memory tempCache = interaction[interactionNonce];
        return block.timestamp > tempCache.maturation && !tempCache.finalised;
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256 interactionNonce,
        uint64
    ) external payable override returns (uint256 withdrawnAmount, uint256 mphWithdrawn, bool interactionComplete) {
        require(_canFinalise(interactionNonce));

        Interaction storage persCache = interaction[interactionNonce];
        address firb = persCache.firbAddress;
        uint64 depId = persCache.depositID;
        persCache.finalised = true;

        withdrawnAmount =  DInterest(firb).withdraw(depId, persCache.amount, false);
        uint64 vestId = IVesting(mphVesting).depositIDToVestID(firb, depId);
        mphWithdrawn = IVesting(mphVesting).withdraw(vestId);
        interactionComplete = true;

        IERC20(mphToken).approve(rollupProcessor, mphWithdrawn);
        IERC20(persCache.underlying).approve(rollupProcessor, withdrawnAmount);

    }

    function getInteractionNonce(address _firb, uint64 depositID) public view returns (uint256){
        return uint256(keccak256(abi.encodePacked(_firb,depositID)));
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}