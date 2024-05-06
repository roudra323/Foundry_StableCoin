// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {console} from "forge-std/console.sol";

/*
 * @title DSCEngine
 * @author roudra323
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////
    //   Errors    //
    /////////////////
    error DSC__NeedsMoreThanZero();
    error DSC__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSC__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    /////////////////////////
    //   State Variables  //
    ////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // token to price feed mapping
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // user to token to amount mapping
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // user to amount of DSC minted mapping
    address[] private s_collateralTokens; // array of collateral tokens
    DecentralizedStableCoin private immutable i_dsc; // DSC token address

    ////////////////
    //   Events  //
    ////////////////

    event CollateralDipoisted(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////
    //  Modifiers  //
    /////////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSC__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSC__TokenNotSupported();
        }
        _;
    }

    /////////////////
    //  Functions  //
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSC__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    function depositeCollateralAndMintDSCsc() external {}

    /*
     * @notice follows CEI pattern (Checks , Effects , Interactions)
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositeCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDipoisted(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
        * @notice follows CEI pattern (Checks , Effects , Interactions)
        * @param amountDscToMint The amount of DSC to mint
        * @notice they must have more collateral value than the minimum threshold
    */

    function mintDsc(uint256 amountDscToMint) external nonReentrant moreThanZero(amountDscToMint) {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidateDsc() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////////
    // Private & Internal view Functions //
    ///////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMited, uint256 collateralValueInUsd)
    {
        totalDscMited = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUSD(user);
    }

    /*
        * Needs how close to liquidation a user is
        * If a user goes below 1, then they can get liquidated
        *
    */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; // Confused
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // Confused
    }

    // 1. Check health factor ( do they have enough collateral ?)
    // 2. If not, revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    ///////////////////////////////////////
    // Public & External view Functions ///
    ///////////////////////////////////////

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getUsdValue(token, amount);
        }

        return totalCollateralValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // Confused
    }
}
