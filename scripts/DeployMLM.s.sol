import "./DeployArbTestNet.s.sol";
import "./localDeployConfig.s.sol";
import "./DeployDataTypes.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
contract DeployMLM is Script, StdCheats, localDeployConfig {

    function run() external returns (DeployedContracts memory) {
        //vm.startBroadcast(vm.envUint("DEPLOYER"));

        if(vm.envOr("LOCAL_DEPLOY_FORK_ARB", false)) {
            //deploy to local node forked from arbitrum
            // Fork Identifier [ARBITRUM]
            string memory RPC = vm.envString("ARBITRUM");
            uint256 FORK_BLOCK = 242592275;
            uint256 arbFork;
            arbFork = vm.createSelectFork(RPC, FORK_BLOCK);


        }
        else if (vm.envOr("testNetDeploy", false)) {
            //deploy to testnet
            string memory RPC = vm.envString("ARB_SEPOLIA");
            
        }
        else if (vm.envOr("mainNetDeploy", false)){
            //deploy to mainnet
            string memory RPC = vm.envString("ARBITRUM");
        }else {
            //deploy to a local node
            (address[] memory mockTokens, Oracle oracle) = _deployERC20Mocks(MainPoolnames, MainPoolSymbols, MainPoolDecimals, MainPoolPrices);
            DeployedContracts memory contracts = _deployLendingPool(address(this), mockTokens, oracle, sStrat, volStrat);
            ConfigParams memory MLPConfig = ConfigParams(baseLTVs, liquidationThresholds, liquidationBonuses, reserveFactors, borrowingEnabled, reserveTypes, isStableStrategy);
            _configureReserves(contracts, mockTokens, MLPConfig, address(this));
            
            address[] memory miniPoolOneMockTokens = _deployERC20MocksAndUpdateOracle(MiniPoolOneNames, MiniPoolOneSymbols, MiniPoolOneDecimals, MiniPoolOnePrices, oracle);
            
            ConfigParams memory miniPoolOneConfig = ConfigParams(MiniPoolOnebaseLTVs, MiniPoolOneliquidationThresholds, MiniPoolOneliquidationBonuses, MiniPoolOnereserveFactors, MiniPoolOneborrowingEnabled, MiniPoolOnereserveTypes, MiniPoolOneisStableStrategy);
            address[] memory miniPoolOneTranche = new address[](1); //WETH
            (miniPoolOneTranche[0], ) =  contracts.protocolDataProvider.getReserveTokensAddresses(mockTokens[0], true);
            ConfigParams memory miniPoolOneTrancheConfig = ConfigParams(trancheBaseLTVs, trancheLiquidationThresholds, trancheLiquidationBonuses, trancheReserveFactors, trancheBorrowingEnabled, trancheReserveTypes, trancheIsStableStrategy);
            MiniPoolConfigParams memory miniPoolOneConfigParams = MiniPoolConfigParams(miniPoolOneTranche, miniPoolOneTrancheConfig, miniPoolOneMockTokens, miniPoolOneConfig);
            
            (address aToken6909_1, address miniPool_1) = _deployMiniPool(contracts, miniPoolOneConfigParams, address(this), 0);
            
            address[] memory miniPoolTwoMockTokens = _deployERC20MocksAndUpdateOracle(MiniPoolTwoNames, MiniPoolTwoSymbols, MiniPoolTwoDecimals, MiniPoolTwoPrices, oracle);

            ConfigParams memory miniPoolTwoConfig = ConfigParams(MiniPoolTwoBaseLTVs, MiniPoolTwoLiquidationThresholds, MiniPoolTwoLiquidationBonuses, MiniPoolTwoReserveFactors, MiniPoolTwoBorrowingEnabled, MiniPoolTwoReserveTypes, MiniPoolTwoisStableStrategy);
            address[] memory miniPoolTwoTranche = new address[](1); //USDC
            (miniPoolTwoTranche[0], ) =  contracts.protocolDataProvider.getReserveTokensAddresses(mockTokens[1], true);
            ConfigParams memory miniPoolTwoTrancheConfig = ConfigParams(trancheBaseLTVs, trancheLiquidationThresholds, trancheLiquidationBonuses, trancheReserveFactors, trancheBorrowingEnabled, trancheReserveTypes, trancheIsStableStrategy);
            MiniPoolConfigParams memory miniPoolTwoConfigParams = MiniPoolConfigParams(miniPoolTwoTranche, miniPoolTwoTrancheConfig, miniPoolTwoMockTokens, miniPoolTwoConfig);
            
            (address aToken6909_2, address miniPool_2) = _deployMiniPool(contracts, miniPoolTwoConfigParams, address(this), 1);

            return contracts;
        }

    }
    
}