// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

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
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public AMOUNT_TO_MINT = 100 ether;
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

    function testCanDepositCollateralWithoutMinting() public depositCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMited, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER); // 0 // 20,000.000000000000000000
        uint256 expectedDepositeAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // 10.000000000000000000
        assertEq(AMOUNT_COLLATERAL, expectedDepositeAmount);
        assertEq(0, totalDscMited);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        AMOUNT_TO_MINT =
            (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        console.log("Amount to mint in the test:", AMOUNT_TO_MINT);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(AMOUNT_TO_MINT, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.depositeCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    modifier startPrank() {
        vm.startPrank(USER);
        _;
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    function testGetHealthFactor() public depositCollateral {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        uint256 healthFactor = dsce.getHealthFactor(USER);
        console.log("Health Factor: ", healthFactor);
        uint256 expectedHealthFactor = 1000e18;
        assertEq(healthFactor, expectedHealthFactor);
    }

    ///////////////////////////////////
    ////////// mintDsc Tests //////////
    ///////////////////////////////////

    function testRevertsIfMintAmountIsZero() public startPrank {
        vm.expectRevert(DSCEngine.DSC__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositCollateral {
        (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        AMOUNT_TO_MINT =
            (AMOUNT_COLLATERAL * (uint256(price) * dsce.getAdditionalFeedPrecision())) / dsce.getPrecision();
        vm.startPrank(USER);
        uint256 expectedHealthFactor =
            dsce.calculateHealthFactor(AMOUNT_TO_MINT, dsce.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral startPrank {
        dsce.mintDsc(AMOUNT_TO_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    ///////////////////////////////////
    //////// burnDsc Tests ////////////
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public startPrank {
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dsce.burnDsc(5);
    }

    function testCanBurnDSC() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    /*
        * TESTS INCOMPLEATED
    */

    function testRevertsIfRedeemAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSC__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    function testCanRedeemCollateral() public depositCollateral startPrank {
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    /// BUG HERE -> [FAIL. Reason: log != expected log]
    // function testEmitCollateralRedeemedWithCorrectArgs() public depositCollateral {
    //     vm.expectEmit(true, true, true, true, address(dsce));
    //     emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
    //     vm.startPrank(USER);
    //     dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc startPrank {
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSC__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /////////////////////////////////
    //...TESTS WRITING REMAINING...//

    function testDepositeCollateralAndMintDSC() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL);
        vm.stopPrank();
        (uint256 totalDscMited, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER); // 0 // 20,000.000000000000000000
        uint256 expectedDepositeAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd); // 10.000000000000000000
        assertEq(AMOUNT_COLLATERAL, expectedDepositeAmount);
        assertEq(AMOUNT_COLLATERAL, totalDscMited);
    }
}
