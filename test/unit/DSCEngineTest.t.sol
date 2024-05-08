// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
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
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    error DSC__NeedsMoreThanZero();
    error DSC__TokenNotSupported();

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchWithPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSC__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
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

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // 100e18 / 2000/ETH = 0.05e18
        uint256 expectedwethAmount = 0.05 ether;
        uint256 actualEthAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualEthAmount, expectedwethAmount);
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

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMited, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER); // 0 // 20,000.000000000000000000
        uint256 expectedDepositeAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // 10.000000000000000000
        assertEq(AMOUNT_COLLATERAL, expectedDepositeAmount);
        assertEq(0, totalDscMited);
    }

    function testGetHealthFactor() public depositCollateral {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        uint256 healthFactor = dsce.getHealthFactor(USER);
        console.log("Health Factor: ", healthFactor);
        uint256 expectedHealthFactor = 1000e18;
        assertEq(healthFactor, expectedHealthFactor);
    }
}
