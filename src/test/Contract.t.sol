// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../lib/ds-test/src/test.sol";
import "../contracts/AztecNotionalLending.sol";
import "./console.sol";
import {CTokenInterface} from "../contracts/interfaces/compound/CTokenInterface.sol";
import {IEIP20NonStandard} from "../contracts/interfaces/IEIP20NonStandard.sol";
import {IUniswapV2Router02} from "../contracts/interfaces/IUniswapV2Router02.sol";
interface Vm {
    function deal(address who, uint256 amount) external;
    function warp(uint x) external;
}

contract ContractTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address public constant ETH = address(0);
    address public constant CETH = address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant CDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    function setUp() public {}
    receive() external payable {}
    function testFindToken() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        int index;
        bool b;
        (index,b) = bridge.findToken(ETH);
        assert(index == 0);
        assert(b == false);
    }


    function lendETH(uint inputAmount) internal returns(NotionalLendingBridge bridge){
        bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        Types.AztecAsset memory inputAsset;
        inputAsset.assetType = Types.AztecAssetType.ETH;
        vm.deal(address(this), inputAmount + 1 ether);
        inputAsset.erc20Address = ETH;
        uint64 auxData = (1 << 48) + (1 << 40);
        bridge.convert{value: inputAmount}(inputAsset,inputAsset,inputAsset, inputAsset, inputAmount, 0, auxData);
    }


    function withdrawETH(uint withdrawAmount, NotionalLendingBridge bridge, bool underlying) internal {
        Types.AztecAsset memory inputAsset;
        Types.AztecAsset memory outputAsset;
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        if (underlying) {
            outputAsset.assetType = Types.AztecAssetType.ETH;
            outputAsset.erc20Address = ETH;
        } else {
            outputAsset.assetType = Types.AztecAssetType.ERC20;
            outputAsset.erc20Address = CETH;
        }
        FCashToken(fcashToken).approve(address(bridge), withdrawAmount);
        uint64 auxData = (1 << 48) + (1 << 40) + 1664064000;
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, withdrawAmount, 0, auxData);
    }

    function lendCDAI(uint inputAmount) internal returns(NotionalLendingBridge bridge, uint inputCDAI){
        bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(DAI),CTokenInterface(CDAI));
        vm.deal(address(this), inputAmount);
        Types.AztecAsset memory inputAsset;
        // swap for CDai
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        ROUTER.swapExactETHForTokens{value: inputAmount}(0, path, address(this), block.timestamp);
        uint CDAIBalance = CTokenInterface(CDAI).balanceOf(address(this));
        inputCDAI = CDAIBalance;
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = CDAI;
        uint inputValue = CDAIBalance;
        uint64 auxData = (2 << 48) + (1 << 40);
        CTokenInterface(CDAI).approve(address(bridge), CDAIBalance);
        bridge.convert(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
    }


    function withdrawCDAI(uint withdrawAmount, NotionalLendingBridge bridge, bool underlying) internal {
        Types.AztecAsset memory inputAsset;
        Types.AztecAsset memory outputAsset;
        address fcashToken = bridge.cashTokenFcashToken(CDAI);
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        outputAsset.assetType = Types.AztecAssetType.ERC20;
        if (underlying) {
            outputAsset.erc20Address = address(DAI);
        } else {
            outputAsset.erc20Address = address(CDAI);
        }
        FCashToken(fcashToken).approve(address(bridge), withdrawAmount);
        uint64 auxData = (2 << 48) + (1 << 40) + 1664064000;
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, withdrawAmount, 0, auxData);
    }
    
    function convertInput(uint x) internal pure returns (uint) {
        x = 1e16 > x ? 1e16 : x;
        x = 1e20 < x ? 1e20 : x;
        return x;
    }

    // test whether when we lend eth, we receive wrapper fcash token back
    function testLendETH(uint x) public{
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
    }

    function testWithdrawETHUnderMaturity(uint x) public {
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        uint prevBalance = address(this).balance;
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CETH)).balanceOf(address(this));
        withdrawETH(withdrawAmount, bridge,true);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        require(totalRedeemedETH * 10000 /0.01 ether > 9900, "should take most of the money back");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testWithdrawETHOverMaturity(uint x) public {
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CETH)).balanceOf(address(this));
        uint prevBalance = address(this).balance;
        vm.warp(1679616000);
        withdrawETH(withdrawAmount, bridge, true);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        require(totalRedeemedETH > x, "should incur interest");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testPartialWithdrawETHUnderMaturity(uint x) public {
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        uint prevBalance = address(this).balance;
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CETH)).balanceOf(address(this));
        withdrawETH(withdrawAmount/2, bridge,true);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        require(totalRedeemedETH * 10000 / (x/2) > 9900, "should take roughly 1/2 of the money back");
        require(totalRedeemedETH * 10000 / x < 5000, "should not take all of the money back");
        require(FCashToken(fcashToken).balanceOf(address(this)) == withdrawAmount - withdrawAmount/2, "half of the fcash should remain");
    }

    function testPartialWithdrawETHOverMaturity(uint x) public {
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CETH)).balanceOf(address(this));
        uint prevBalance = address(this).balance;
        vm.warp(1679616000);
        withdrawETH(withdrawAmount/2, bridge, true);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        require(totalRedeemedETH > x/2, "should incur interest on the half of the withdraw amount");
        require(totalRedeemedETH * 10000 / x < 6000, "should not take all of the money back");
        require(FCashToken(fcashToken).balanceOf(address(this)) == withdrawAmount - withdrawAmount/2, "half of the fcash should remain");
    }

    function testWithdrawETHOverMaturityWithdrawCETH(uint x) public {
        x = convertInput(x);
        NotionalLendingBridge bridge = lendETH(x);
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CETH)).balanceOf(address(this));
        vm.warp(1679616000);
        withdrawETH(withdrawAmount, bridge, false);
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        require(CTokenInterface(CETH).balanceOf(address(this)) > 0, "should receive CETH");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testLendCDAI(uint x) public{
        x = convertInput(x);
        (NotionalLendingBridge bridge, ) = lendCDAI(x);
        address fcashToken = bridge.cashTokenFcashToken(CDAI);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
    }

    function testWithdrawCDAIUnderMaturity(uint x) public {
        x = convertInput(x);
        (NotionalLendingBridge bridge, uint inputAmount) = lendCDAI(x);
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(this));
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CDAI)).balanceOf(address(this));
        withdrawCDAI(withdrawAmount, bridge, false);
        uint redeemedBalance = CTokenInterface(CDAI).balanceOf(address(this)) - prevBalance;
        require(redeemedBalance * 10000 / inputAmount > 9900, "should take most of money back");
        require(IEIP20NonStandard(bridge.cashTokenFcashToken(CDAI)).balanceOf(address(this)) == 0,"fcash should be burned");
    }

    function testWithdrawDAIOverMaturity(uint x) public {
        x = convertInput(x);
        (NotionalLendingBridge bridge, uint inputAmount) = lendCDAI(x);
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(this));
        uint withdrawAmount = IEIP20NonStandard(bridge.cashTokenFcashToken(CDAI)).balanceOf(address(this));
        vm.warp(1679616000);
        withdrawCDAI(withdrawAmount, bridge, false);
        uint redeemedBalance = CTokenInterface(CDAI).balanceOf(address(this)) - prevBalance;
        require(redeemedBalance  > inputAmount, "should incur interest");
        require(IEIP20NonStandard(bridge.cashTokenFcashToken(CDAI)).balanceOf(address(this)) == 0,"fcash should be burned");
    }
}
