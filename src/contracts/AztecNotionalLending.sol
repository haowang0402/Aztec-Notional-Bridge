// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {BalanceActionWithTrades, DepositActionType, BalanceAction, TradeActionType, MarketParameters, AssetRateParameters} from "./interfaces/NotionalTypes.sol";
import {IDefiBridge} from "./interfaces/IDeFIBridge.sol";
import { Types }  from "./interfaces/Types.sol";
import {NotionalProxy} from "./interfaces/notional/NotionalProxy.sol";
import {NotionalViews} from "./interfaces/notional/NotionalViews.sol";
import {CTokenInterface} from "./interfaces/compound/CTokenInterface.sol";
import {IEIP20NonStandard} from "./interfaces/IEIP20NonStandard.sol";
import {FCashToken} from "./AztecFCash.sol";
import "../test/console.sol";
struct TradeData {
    uint16 currencyId;
    uint8 marketIndex;
    uint40 maturity;
}

contract NotionalLendingBridge is IDefiBridge {
    address public immutable rollupProcessor;
    NotionalProxy public immutable notionalProxy;
    IEIP20NonStandard[] public underlyingTokens;
    CTokenInterface[] public cTokens;
    int256 private constant ASSET_RATE_DECIMAL_DIFFERENCE = 1e10;
    mapping(address => address) public cashTokenFcashToken;
    mapping(address => address) public fcashTokenCashToken;
    constructor(address _rollupProcessor){
        rollupProcessor = _rollupProcessor;
        notionalProxy = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    }

    function insertToken(IEIP20NonStandard underlying, CTokenInterface cToken) external {
        underlyingTokens.push(underlying);
        cTokens.push(cToken);
    }
    function findToken (address token) public view returns (int, bool) {
        int index = -1;
        bool isCtoken = false;
        for (uint i = 0; i < cTokens.length; i++) {
            if (token == address(underlyingTokens[i])) {
                index = int(i);
                break;
            }
            else if(token == address(cTokens[i])){
                index = int(i);
                isCtoken = true;
                break;
            } 
        }
        return (index, isCtoken);
    }
    function convertFromUnderlying(AssetRateParameters memory ar, int256 underlyingBalance)
    internal
    pure
    returns (int256){
    // Calculation here represents:
    // rateDecimals * balance * underlyingPrecision / rate * internalPrecision
    int256 assetBalance = underlyingBalance * ASSET_RATE_DECIMAL_DIFFERENCE * ar.underlyingDecimals / ar.rate;
    return assetBalance;
}
    function canFinalise(uint256 interactionNonce) external view override returns (bool) {
        return false;
    }
    receive() external payable {
    }
    function encodeLendTrade(
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minLendRate // Set this to zero to allow any lend rate
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.Lend) << 248) |
                    (marketIndex << 240) |
                    (fCashAmount << 152) |
                    (minLendRate << 120)
                )
            );
    }

    function finalise(
        Types.AztecAsset calldata inputAssetA,
        Types.AztecAsset calldata inputAssetB,
        Types.AztecAsset calldata outputAssetA,
        Types.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    ) external payable override returns (uint256, uint256) {
        require(false);
    }
    function setUnderlyingToFCashToken(address cToken) public returns(address fcash) {
        require(
            cashTokenFcashToken[cToken] == address(0),
            "NotionalLendingBridge: FCASH_TOKEN_SET"
        );
        IEIP20NonStandard cTokenERC20 = IEIP20NonStandard(cToken);
        fcash = address(new FCashToken(cTokenERC20.name(), cTokenERC20.symbol(),8));
        cashTokenFcashToken[cToken] = fcash;
        fcashTokenCashToken[fcash] = cToken;
    }

    function _computeUnderlyingAmt(IEIP20NonStandard underlyingAddr, CTokenInterface cToken, uint inputAmt,bool isCToken) internal returns(int88 cashAmt) {
        cToken.accrueInterest();
        uint underlyingDecimal = address(underlyingAddr) == address(0) ? 18 : underlyingAddr.decimals();
        if (isCToken) {
            uint exchangeRateCurrent = cToken.exchangeRateCurrent();
            uint mantissa = 10 + underlyingDecimal;
            cashAmt = int88(int(inputAmt * exchangeRateCurrent/(10 ** mantissa)));
        }  else{
            cashAmt = int88(int(inputAmt / (10 ** (underlyingDecimal-8))));
        }
    }

    function _enter(IEIP20NonStandard underlyingAddress, CTokenInterface cToken, uint inputAmount, bool isCToken, uint64 auxData) internal returns(uint88) {
        if (isCToken){
            cToken.transferFrom(msg.sender, address(this), inputAmount);
            cToken.approve(address(notionalProxy), inputAmount);
        } else {
            if (address(underlyingAddress) != address(0x0)){
                underlyingAddress.transferFrom(msg.sender, address(this), inputAmount);
                underlyingAddress.approve(address(notionalProxy), inputAmount);
            } else{
                require(msg.value >= inputAmount, "PROVIDE ETH");
            }
        }
        BalanceActionWithTrades memory action;
        action.actionType = isCToken ? DepositActionType.DepositAsset : DepositActionType.DepositUnderlying;
        action.depositActionAmount = inputAmount;
        action.withdrawEntireCashBalance = false;
        action.redeemToUnderlying = false;
        action.withdrawAmountInternalPrecision = 0;
        int88 cashAmt = _computeUnderlyingAmt(underlyingAddress, cToken, inputAmount, isCToken);
        TradeData memory tradeData;
        tradeData.currencyId = uint16(auxData >> 48 & 0xFFFF);
        tradeData.marketIndex = uint8(auxData >> 40 & 0xFF);
        action.currencyId = tradeData.currencyId;
        int256 fCashAmt = NotionalViews(notionalProxy).getfCashAmountGivenCashAmount( 
            action.currencyId, 
            -cashAmt, 
            uint256(tradeData.marketIndex),
            block.timestamp);
        fCashAmt = fCashAmt * 99875/100000;
        bytes32 trade = bytes32(uint256(tradeData.marketIndex) << 240 |  uint256(fCashAmt) << 152);
        action.trades = new bytes32[](1);
        action.trades[0] = trade;
        BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
        actions[0] = action;
        if (address(underlyingAddress) == address(0x0) && !isCToken ){
            notionalProxy.batchBalanceAndTradeAction{value: inputAmount}(address(this), actions);
        } else{
            notionalProxy.batchBalanceAndTradeAction(address(this), actions);
        }
        FCashToken(cashTokenFcashToken[address(cToken)]).mint(rollupProcessor, uint256(fCashAmt));
        return uint88(uint256(fCashAmt));        
    }

    function _exit(IEIP20NonStandard underlyingAddress, CTokenInterface cToken, uint inputValue, bool isCToken, uint64 auxData ) internal {
        // first find whether outputAsset is an underlying token or ctoken
        TradeData memory tradeData;
        int cOutputAmount;
        uint prevBalance;
        tradeData.currencyId = uint16(auxData >> 48 & 0xFFFF);
        tradeData.marketIndex = uint8(auxData >> 40 & 0xFF);
        tradeData.maturity = uint40(auxData);
        FCashToken(cashTokenFcashToken[address(cToken)]).transferFrom(msg.sender, address(this), inputValue);
        FCashToken(cashTokenFcashToken[address(cToken)]).burn(inputValue);
        if (isCToken) {
            prevBalance = cToken.balanceOf(address(this));
        } else {
            if (address(underlyingAddress) == address(0)) {
                prevBalance = address(this).balance;
            } else{
                prevBalance = underlyingAddress.balanceOf(address(this));
            }
        }
        if (block.timestamp < tradeData.maturity){
            // under maturity
            (cOutputAmount, ) = NotionalViews(notionalProxy).getCashAmountGivenfCashAmount(tradeData.currencyId, -int88(int256(inputValue)), tradeData.marketIndex,block.timestamp);
            BalanceActionWithTrades memory action;
            action.withdrawAmountInternalPrecision = uint(cOutputAmount);
            action.redeemToUnderlying = !isCToken;
            action.currencyId  = tradeData.currencyId;
            BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
            actions[0] = action;
            bytes32 trade = bytes32((1 << 248) | uint256(tradeData.marketIndex) << 240 |  uint256(inputValue) << 152 | 0 << 120);
            action.trades = new bytes32[](1);
            action.trades[0] = trade;
            actions[0] = action;
            notionalProxy.batchBalanceAndTradeAction(address(this), actions);
            //transfer tokens back to rollup processor
        } else {
            AssetRateParameters memory ar = NotionalViews(notionalProxy).getSettlementRate(tradeData.currencyId, tradeData.maturity);
            cOutputAmount = convertFromUnderlying(ar, int256(inputValue));
            BalanceAction memory action;
            action.withdrawAmountInternalPrecision = uint(cOutputAmount);
            action.redeemToUnderlying = !isCToken;
            action.currencyId  = tradeData.currencyId;
            BalanceAction[] memory actions = new BalanceAction[](1);
            actions[0] = action;
            notionalProxy.batchBalanceAction(address(this), actions);
        }
        if (isCToken){
            cToken.transfer(rollupProcessor , cToken.balanceOf(address(this)) - prevBalance);
        } else {
            if (address(underlyingAddress) == address(0)) {
                address(rollupProcessor).call{value: address(this).balance - prevBalance}("");
            }
            else {
                underlyingAddress.transfer(rollupProcessor, underlyingAddress.balanceOf(address(this)) - prevBalance );
            }
        }
    }


    function convert(Types.AztecAsset calldata inputAsset,Types.AztecAsset calldata, Types.AztecAsset calldata outputAsset,
        Types.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64 auxData
        )
        external
        payable
        override
        returns (
            uint256 outputValue,
            uint256,
            bool isAsync
        )
        {   
            isAsync = false;
            bool isCToken = false;
            int index = -1;
            (index, isCToken) = findToken(inputAsset.erc20Address);
            require(msg.sender == rollupProcessor, "INVALID_CALLER");
            if (index != -1) {
                address fCashAddress = cashTokenFcashToken[address(cTokens[uint(index)])];
                if (fCashAddress == address(0)) {
                    fCashAddress = setUnderlyingToFCashToken(address(cTokens[uint(index)]));
                }
                outputValue = _enter(underlyingTokens[uint(index)], cTokens[uint(index)], inputValue, isCToken, auxData);
            } else {
                if (fcashTokenCashToken[inputAsset.erc20Address] != address(0)){
                    (index, isCToken) = findToken(outputAsset.erc20Address);
                    _exit(underlyingTokens[uint(index)], cTokens[uint(index)], inputValue, isCToken,auxData);
                } else {
                    revert("INVALID INPUT");
                }
            }
        }
}