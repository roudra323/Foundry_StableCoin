// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    // uint256 public constant
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    error DSC__NeedsMoreThanZero();
    error DSC__TokenNotSupported();

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////
    // Price Test Cases //
    //////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedEthValue = 30000e18;
        uint256 actualEthValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualEthValue, expectedEthValue);
    }

    //////////////////////////////
    // Deposite Collateral Tests//
    //////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        uint256 zeroEthAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(DSC__NeedsMoreThanZero.selector));
        dsce.depositeCollateral(weth, zeroEthAmount);
    }

    function testRevertsIfCollateralIsNotListed() public {
        address notListedToken = makeAddr("notListed");
        vm.expectRevert(abi.encodeWithSelector(DSC__TokenNotSupported.selector));
        dsce.depositeCollateral(notListedToken, 10e18);
    }
}
