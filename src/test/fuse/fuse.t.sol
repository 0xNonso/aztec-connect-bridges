// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.6 <0.8.10;

import {Vm} from "../Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FuseBridge} from "./../../bridges/fuse/FuseBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";


import "../../../lib/ds-test/src/test.sol";


contract FuseBridgeTest is DSTest {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    FuseBridge bridge;
    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant fDai = IERC20(0x989273ec41274C4227bCB878C2c26fdd3afbE70d);

    address Comptroller = 0x814b02C1ebc9164972D888495927fe1697F0Fb4c;

    AztecTypes.AztecAsset private empty;
    AztecTypes.AztecAsset private daiAsset = AztecTypes.AztecAsset({
        id: 1,
        erc20Address: address(dai),
        assetType: AztecTypes.AztecAssetType.ERC20
    });
    AztecTypes.AztecAsset private fDaiAsset = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: address(fDai),
        assetType: AztecTypes.AztecAssetType.ERC20
    });



    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();
        bridge = new FuseBridge(address(rollupProcessor));
        _setTokenBalance(address(dai), address(rollupProcessor), 1000e18);
    }


    function testFuseBridge() public {
       bridge.approveFusePoolMarket(Comptroller, address(dai));
       uint256 depositAmount = 150e18;
        (
            uint256 outputValueA,
            ,bool isAsync
        ) = rollupProcessor.convert(
                address(bridge),
                daiAsset,
                empty,
                fDaiAsset,
                empty,
                depositAmount,
                0,
                1
        );
        emit log_named_uint("Output Value (fDai-Balance)", outputValueA);
        assertTrue(outputValueA > 0);
        assertTrue(isAsync == false);

        (
            uint256 outputValueB,
            ,
        ) = rollupProcessor.convert(
                address(bridge),
                fDaiAsset,
                empty,
                daiAsset,
                empty,
                outputValueA,
                1,
                0
        );
        emit log_named_uint("Output Value (Dai-Balance)", outputValueB);
        assertTrue(outputValueB > 0);

        // uint256 rollupDai = dai.balanceOf(address(rollupProcessor));

        // assertEq(
        //     depositAmount,
        //     rollupDai,
        //     "Balances must match"
        // );

    }
    function testFailFuseBridge() public {
        uint256 depositAmount = 150e18;
        (
            uint256 outputValueA,
            ,bool isAsync
        ) = rollupProcessor.convert(
                address(bridge),
                daiAsset,
                empty,
                fDaiAsset,
                empty,
                depositAmount,
                0,
                1
        );
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



}
