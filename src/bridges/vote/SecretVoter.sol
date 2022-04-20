// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface GovernanceBravo {
    function castVote(uint proposalId, uint8 support) external;
}

contract SecretVoter {
    address owner;

    constructor() payable {
        owner = msg.sender;
    }

    /// where to vote
    /// which proposal
    /// what to voteß
    function vote(address where, uint8 what, uint256 which) external {
        require(msg.sender == owner, "UNAUTHORIZED");
        GovernanceBravo(where).castVote(which, what);
    }
    
}