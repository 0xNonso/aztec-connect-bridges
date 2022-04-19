// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.6 <0.8.10;

import "../../../lib/ds-test/src/test.sol";

import {Vm} from "../Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

import {MphBridge} from "./../../bridges/mph/MphBridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
interface Test {
    function latestNonce() external view returns(uint256);
}

contract MphTest is DSTest {
    Vm private vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address private compDaiFirbAddr = 0x11B1c87983F881B3686F8b1171628357FAA30038;
    address private daiToken = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private mphToken = 0x8888801aF4d980682e47f1A9036e589479e835C5;
    address private vesting = 0xA907C7c3D13248F08A3fb52BeB6D1C079507Eb4B;

    DefiBridgeProxy private defiBridgeProxy;
    RollupProcessor private rollupProcessor;

    MphBridge private bridge;

    AztecTypes.AztecAsset private empty;

    AztecTypes.AztecAsset private dai = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: daiToken,
        assetType: AztecTypes.AztecAssetType.ERC20
    });
    
    AztecTypes.AztecAsset private compDaiFirbAsset = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: compDaiFirbAddr,
        assetType: AztecTypes.AztecAssetType.ERC20
    });

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();
        bridge = new MphBridge(address(rollupProcessor), vesting, mphToken);

        _setTokenBalance(dai.erc20Address, address(rollupProcessor), 700e18);
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 2; // May vary depending on token

        vm.store( 
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }

    function testMPHBrdge() public {
        uint256 depositAmount = 200e18;
        uint256 maturation = block.timestamp + 2 days;

        (, ,bool isAsync) = rollupProcessor.convert(
            address(bridge),
            dai,
            empty,
            compDaiFirbAsset,
            empty,
            depositAmount,
            0,
            maturation
        );
        // uint256 bridgeBalance = IERC20(compDaiFirbAddr).balanceOf(address(bridge));
        // emit log_named_uint("Bidge Balance", bridgeBalance);
        assertTrue(isAsync == true);
        // assertTrue(bridgeBalance > 0) ;
        // rollupProcessor.processAsyncDeFiInteraction(
        //     nonce
        // );
    }

    function testFinaliseMPHBrdge() public {
        uint256 depositAmount = 200e18;
        uint256 maturation = block.timestamp + 30 days;
        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
            address(bridge),
            dai,
            empty,
            compDaiFirbAsset,
            empty,
            depositAmount,
            0,
            maturation
        );

        vm.warp(maturation + 31 days);

        uint256 nonce = Test(address(bridge)).latestNonce();
        (uint256 withdrawnAmount, uint256 mphWithdrawn, bool interactionComplete) = bridge.finalise(
            empty,
            empty, 
            empty, 
            empty, 
            nonce, 
            0
        );
        emit log_named_uint("Withdrawn Amount", withdrawnAmount);
        emit log_named_uint("Withdrawn MPH", mphWithdrawn);

        assertTrue(isAsync == true);
        assertTrue(withdrawnAmount > 0);
        assertTrue(mphWithdrawn > 0);
        assertTrue(interactionComplete == true);


    }
    function testFailFinaliseEarlyMPHBrdge() public {
        uint256 depositAmount = 200e18;
        uint256 maturation = block.timestamp + 2 days;

        rollupProcessor.convert(
            address(bridge),
            dai,
            empty,
            compDaiFirbAsset,
            empty,
            depositAmount,
            0,
            maturation
        );

        uint256 nonce = Test(address(bridge)).latestNonce();

        bridge.finalise(
            empty,
            empty, 
            empty, 
            empty, 
            nonce, 
            0
        );
    }

}