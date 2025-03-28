// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;


import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/Script.sol";
import "lib/forge-std/src/console2.sol";
import "lib/forge-std/src/StdUtils.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }   

    function swapExactETHForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface IWeth {
    function deposit() external payable;
}

contract DealTOken is Script, Test {
    using stdJson for string;

    IAerodromeRouter constant ROUTER = IAerodromeRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    // Base mainnet token addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant CDXUSD = 0xC0D3700000987C99b3C9009069E4f8413fD22330;

    // Recipient address - we'll use the deployer address
    address recipient;

    function run() public {
        // Config fetching
        console2.log("CHAIN ID: ", block.chainid);
        
        // Start broadcast to record transactions
        vm.startBroadcast();
        
        // Set recipient to the transaction sender
        recipient = msg.sender;
        console2.log("Recipient address:", recipient);


        // transfer ETH to 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        // payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8).transfer(100 ether);

        IWeth(WETH).deposit{value: 1 ether}();

        // Function: swapExactETHForTokens(uint256, (address,address,bool,address)[], address, uint256)
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({from: WETH, to: USDC, stable: false, factory: address(0x420DD381b31aEf6683db6B902084cB0FFECe40Da)});
        ROUTER.swapExactETHForTokens{value: 1 ether}(
            1e2,
            routes,
            recipient,
            block.timestamp*2
        );
        
        routes[0] = IAerodromeRouter.Route({from: WETH, to: CBBTC, stable: false, factory: address(0x420DD381b31aEf6683db6B902084cB0FFECe40Da)});
        ROUTER.swapExactETHForTokens{value: 1 ether}(
            1e2,
            routes,
            recipient,
            block.timestamp*2
        );

        routes[0] = IAerodromeRouter.Route({from: WETH, to: CDXUSD, stable: false, factory: address(0x420DD381b31aEf6683db6B902084cB0FFECe40Da)});
        ROUTER.swapExactETHForTokens{value: 1 ether}(
            1e2,
            routes,
            recipient,
            block.timestamp*2
        );
    
        vm.stopBroadcast();

        
        // log eth balance
        console2.log("ETH balance: %18e", address(recipient).balance);

        // Log balances
        logBalance("WETH", WETH);
        logBalance("cbBTC ", CBBTC);
        logBalance("cdxUSD ", CDXUSD);
        logBalance("USDC", USDC);
        
    }
    
    function logBalance(string memory tokenName, address tokenAddress) internal view {
        uint256 balance = IERC20(tokenAddress).balanceOf(recipient);
        uint8 decimals = IERC20(tokenAddress).decimals();
        
        if (decimals == 18) {
            console2.log("%s balance: %18e", tokenName, balance);
        } else if (decimals == 8) {
            console2.log("%s balance: %8e", tokenName, balance);
        } else if (decimals == 6) {
            console2.log("%s balance: %6e", tokenName, balance);
        } else {
            console2.log("%s balance: %18e", tokenName, balance);
        }
    }
}
