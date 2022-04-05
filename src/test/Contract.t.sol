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
    // test whether when we lend eth, we receive wrapper fcash token back
    function testLendETH() public{
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        Types.AztecAsset memory inputAsset;
        inputAsset.assetType = Types.AztecAssetType.ETH;
        vm.deal(address(this), 10 ether);
        inputAsset.erc20Address = ETH;
        uint inputValue = 0.01 ether;
        uint64 auxData = (1 << 48) + (1 << 40);
        bridge.convert{value: 0.01 ether}(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
    }

    function testWithdrawETHUnderMaturity() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        Types.AztecAsset memory inputAsset;
        inputAsset.assetType = Types.AztecAssetType.ETH;
        vm.deal(address(this), 10 ether);
        inputAsset.erc20Address = address(0x0);
        uint inputValue = 0.01 ether;
        uint64 auxData = (1 << 48) + (1 << 40);
        bridge.convert{value: 0.01 ether}(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        inputValue = balance;
        Types.AztecAsset memory outputAsset;
        outputAsset.assetType = Types.AztecAssetType.ETH;
        outputAsset.erc20Address = ETH;
        FCashToken(fcashToken).approve(address(bridge), balance);
        auxData = (1 << 48) + (1 << 40) + 1664064000;
        uint prevBalance = address(this).balance;
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, inputValue, 0, auxData);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        require(totalRedeemedETH * 10000 /0.01 ether > 9900, "should take most of the money back");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testWithdrawETHOverMaturity() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        Types.AztecAsset memory inputAsset;
        inputAsset.assetType = Types.AztecAssetType.ETH;
        vm.deal(address(this), 10 ether);
        inputAsset.erc20Address = ETH;
        uint inputValue = 0.01 ether;
        uint64 auxData = (1 << 48) + (1 << 40);
        bridge.convert{value: 0.01 ether}(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        inputValue = balance;
        Types.AztecAsset memory outputAsset;
        outputAsset.assetType = Types.AztecAssetType.ETH;
        outputAsset.erc20Address = ETH;
        FCashToken(fcashToken).approve(address(bridge), balance);
        auxData = auxData + 1664064000;
        vm.warp(1679616000);
        uint prevBalance = address(this).balance;
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, inputValue, 0, auxData);
        uint totalRedeemedETH = address(this).balance - prevBalance;
        require(totalRedeemedETH > inputValue, "should incur interest");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }


    function testWithdrawETHOverMaturityWithdrawCETH() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(ETH),CTokenInterface(CETH));
        Types.AztecAsset memory inputAsset;
        inputAsset.assetType = Types.AztecAssetType.ETH;
        vm.deal(address(this), 10 ether);
        inputAsset.erc20Address = ETH;
        uint inputValue = 0.01 ether;
        uint64 auxData = (1 << 48) + (1 << 40);
        bridge.convert{value: 0.01 ether}(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CETH);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        inputValue = balance;
        Types.AztecAsset memory outputAsset;
        outputAsset.assetType = Types.AztecAssetType.ERC20;
        outputAsset.erc20Address = CETH;
        FCashToken(fcashToken).approve(address(bridge), balance);
        auxData = auxData + 1664064000;
        vm.warp(1679616000);
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, inputValue, 0, auxData);
        require(CTokenInterface(CETH).balanceOf(address(this)) > 0, "should receive CETH");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testLendCDAI() public{
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(DAI),CTokenInterface(CDAI));
        vm.deal(address(this), 10 ether);
        Types.AztecAsset memory inputAsset;
        // swap for CDai
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        ROUTER.swapExactETHForTokens{value: 0.01 ether}(0, path, address(this), block.timestamp);
        uint CDAIBalance = CTokenInterface(CDAI).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = CDAI;
        uint inputValue = CDAIBalance;
        uint64 auxData = (2 << 48) + (1 << 40);
        CTokenInterface(CDAI).approve(address(bridge), CDAIBalance);
        bridge.convert(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CDAI);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
    }

    function testWithdrawCDAIUnderMaturity() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(DAI),CTokenInterface(CDAI));
        vm.deal(address(this), 10 ether);
        Types.AztecAsset memory inputAsset;
        // swap for CDai
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        ROUTER.swapExactETHForTokens{value: 0.01 ether}(0, path, address(this), block.timestamp);
        uint CDAIBalance = CTokenInterface(CDAI).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = CDAI;
        uint inputValue = CDAIBalance;
        uint64 auxData = (2 << 48) + (1 << 40);
        CTokenInterface(CDAI).approve(address(bridge), CDAIBalance);
        bridge.convert(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CDAI);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        inputValue = balance;
        Types.AztecAsset memory outputAsset;
        outputAsset.assetType = Types.AztecAssetType.ERC20;
        outputAsset.erc20Address = address(CDAI);
        FCashToken(fcashToken).approve(address(bridge), balance);
        auxData = (2 << 48) + (1 << 40) + 1664064000;
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(this));
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, inputValue, 0, auxData);
        uint redeemedCDAI = CTokenInterface(CDAI).balanceOf(address(this)) - prevBalance;
        // might lose some of the money because of the slippage.
        require(redeemedCDAI *10000/CDAIBalance > 9900, "should take most of the money back");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }

    function testWithdrawDAIOverMaturity() public {
        NotionalLendingBridge bridge = new NotionalLendingBridge(address(this));
        bridge.insertToken(IEIP20NonStandard(DAI),CTokenInterface(CDAI));
        vm.deal(address(this), 10 ether);
        Types.AztecAsset memory inputAsset;
        // swap for CDai
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        ROUTER.swapExactETHForTokens{value: 0.01 ether}(0, path, address(this), block.timestamp);
        uint CDAIBalance = CTokenInterface(CDAI).balanceOf(address(this));
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = CDAI;
        uint inputValue = CDAIBalance;
        uint64 auxData = (2 << 48) + (1 << 40);
        CTokenInterface(CDAI).approve(address(bridge), CDAIBalance);
        bridge.convert(inputAsset,inputAsset,inputAsset, inputAsset, inputValue, 0, auxData);
        address fcashToken = bridge.cashTokenFcashToken(CDAI);
        uint balance = FCashToken(fcashToken).balanceOf(address(this));
        require(balance > 0, "receive fcash for lending");
        inputAsset.assetType = Types.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        inputValue = balance;
        Types.AztecAsset memory outputAsset;
        outputAsset.assetType = Types.AztecAssetType.ERC20;
        outputAsset.erc20Address = CDAI;
        FCashToken(fcashToken).approve(address(bridge), balance);
        auxData = auxData + 1664064000;
        vm.warp(1679616000);
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(this));
        bridge.convert(inputAsset,inputAsset,outputAsset,outputAsset, inputValue, 0, auxData);
        uint redeemedCDAI = CTokenInterface(CDAI).balanceOf(address(this)) - prevBalance;
        require(redeemedCDAI > CDAIBalance, "should incur interest");
        require(FCashToken(fcashToken).balanceOf(address(this)) == 0, "fcash should be burned");
    }
}
