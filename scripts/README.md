# 📜 **Table of Contents**
1. [🔍 Overview](#overview)
2. [💡 How to Use Scripts](#how-to-use-scripts)
3. [🛠️ Configuration Files](#configuration-files)
   - [🧪 0_MockedTokens](#0_mockedtokens)
   - [🏗️ 1_DeploymentConfig (Main Pool)](#1_deploymentconfig)
   - [🏗️ 2_DeploymentConfig (Mini Pool)](#2_deploymentconfig)
   - [📈 3_StratsToAdd](#3_stratstoadd)
   - [💰 4_AssetsToAdd](#4_assetstoadd)
   - [🔧 5_Reconfigure](#5_reconfigure)
   - [🏦 6_ChangePeripherials](#6_changeperipherials)
   - [🔧 7_TransferOwnerships](#7_transferownerships)
   - [🧪 8_TestConfig](#8_testconfig)
4. [📤 Output Files](#output-files)
   - [🧪 0_MockedTokens Output](#0_mockedtokens)
   - [🏦 1_LendingPoolContracts](#1_lendingpoolcontracts)
   - [🏦 2_MiniPoolContracts](#2_minipoolcontracts)
   - [📊 3_DeployedStrategies](#3_deployedstrategies)

### Overview
Scripts allow to deploy Cod3x-Lend infrastructure and properly configure it.
The deployment process involves configuration files `./inputs/<Nr>_<InputJsonName>.json` and corresponding scripts `(./<Nr>_<ScriptName>.s.sol)`. Typically, the scripts should be executed in numerical order. They generate output json files with deployed contract addresses that can be used by next script without the need to configure manually. Each script file requires at least one configuration file to be available and properly configured (example configurations with all descriptions are available [here](#configuration-files)). The scripts may require also more json files as an inputs. Usually they are generated from previous scripts and available in `./outputs` folder.

![alt text](./imgs/Configuration.png)

### How to use scripts
1. **Fill .env (determine what kind of scripts you want to run LOCAL_FORK/TESTNET/MAINNET)**
2. **Write data into configuration file scripts/inputs/<nr>_<configName>.json**
3. **Run the script:**
   - **Fork**:
     - compatible script numbers <Nr> to run (1 - 8)
     - local fork runs also the previous script in order to get all necessary contracts so in this variant the order doesn't matter - it is possible to run script with last number without running scripts with prior numbers
     - configuration with corresponding number shall be filled
     - run `forge script scripts/localFork/<nr>_<scriptName>.s.sol`
   - **Testnet**: 
      - compatible script numbers `<Nr>` to run (0 - 8)
      - there is need to have executed script 0_DeployMocks.s.sol in order to have ERC20 token mocks
      - there is need to have already executed script with previous `<Nr>`
      - import env variables via `source .env`
      - run `forge script scripts/<nr>_<scriptName>.s.sol --chain-id <chainId> --rpc-url $<RPC_URL> -vvvv --broadcast` for deployment
      - run `forge script scripts/<nr>_<scriptName>.s.sol --chain-id $<RPC_URL> --rpc-url $<RPC_URL> --etherscan-api-key $ETHERSCAN_KEY --broadcast -vvvv --sender <sender address>` if sender is required
      - run `forge script scripts/<nr>_<scriptName>.s.sol --chain-id <chainId> --rpc-url $<RPC_URL> --broadcast -vvvv --private-key $PRIVATE_KEY` if sender is required
   - **Mainnet**:
      - compatible script numbers <Nr> to run (0 - 8)
   - **Mainnet/Testnet tests**
     - `forge script scripts/<nr>_<scriptName>.s.sol --chain-id <chainId> --rpc-url $<RPC_URL> --broadcast -vvvv --private-keys $USER1_PRIVATE_KEY --private-keys $USER2_PRIVATE_KEY --private-keys $DIST_PRIVATE_KEY --sender <EoaAddress>`
   - **Verification**
     - Etherscan - `forge script scripts/<nr>_<scriptName>.s.sol --chain-id <chainId> --rpc-url $SEPOLIA_RPC_URL --resume --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY`
     - Blockscout - `forge script scripts/<nr>_<scriptName>.s.sol --chain-id <chainId> --rpc-url $<RPC_URL> --resume --verify --verifier blockscout --verifier-url $<VerifierUrl> --private-key $PRIVATE_KEY`
     - Standard Input Json - `forge verify-contract --show-standard-json-input <contract address> <contract name> > std.json`
   - Examples:
      - `forge script scripts/2_DeployMiniPool.s.sol --chain-id 84532 --rpc-url $BASE_SEPOLIA_RPC_URL --resume --verify --verifier etherscan --etherscan-api-key $BASE_ETHERSCAN_API_KEY --private-key $PRIVATE_KEY`

### Configuration files
**Important !!** All params listed inside json's keys MUST be in alphabetical order !
##### **0_MockedTokens**
  - Shall be used only for testnet deployments or for new tokens in mainnet 
  - Shall contain all not deplyed tokens we want to use in next scripts with token symbols the same that will be used in reserve configuration
  - Example:
    ```json
    {
        "mockedToken": [
            {
                "decimals": 18,
                "prices": 2.5e8,
                "symbol": "WETH"
            },
            {
                "decimals": 6,
                "prices": 1e8,
                "symbol": "USDC"
            },
            {
                "decimals": 8,
                "prices": 64e8,
                "symbol": "WBTC"
            },
            {
                "decimals": 18,
                "prices": 1e8,
                "symbol": "USDT"
            }
        ]
    }
    ```
##### **1_DeploymentConfig**
  - Shall be used for deployment of the main lending pool
  - Example:
    ```json
    {
        "wethGateway": "0xe43208266aEad29736433aA0b6F035a2Ffc3BB9F",
        "general": {
            "aTokenNamePrefix": "Cod3x Lend ",
            "aTokenSymbolPrefix": "cl",
            "debtTokenNamePrefix": "Cod3x Lend variable debt bearing ",
            "debtTokenSymbolPrefix": "clDebt",
            "marketReferenceCurrencyAggregator": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
            "networkBaseTokenAggregator": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
            "treasury": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
            "usdBootstrapAmount": 2000000000000000000 // USD amount in wei that needs to be deposited during deployment to avoid inflation attack
        },
        // List of reserves and their configurations
        "poolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "PI", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 0, // Id of strategy choosen from all available strategies deployed or listed in configuration
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 0,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            }
        ],
        // List of volatile interest strategies and their configurations
        "volatileStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.45e27,
                "variableRateSlope1": 0.07e27,
                "variableRateSlope2": 3e27
            }
        ],
        // List of stable interest strategies and their configurations
        "stableStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.8e27,
                "variableRateSlope1": 0.04e27,
                "variableRateSlope2": 0.75e27
            }
        ],
        // List of pi interest strategies and their configurations
        "piStrategies": [
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            }
        ],
        // All necessary configuration to deploy oracle for specified assets
        "oracleConfig": {
            "assets": [
                "0x4200000000000000000000000000000000000006"
            ],
            "baseCurrency": "0x0000000000000000000000000000000000000000",
            "baseCurrencyUnit": 1e18,
            "fallbackOracle": "0x0000000000000000000000000000000000000000",
            "sources": [
                "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"
            ],
            "timeouts": [
                100000,
                100000
            ]
        }
    }
    ```
##### **2_DeploymentConfig**
  - Shall be used for deployment of the mini pool
  - Example:
    ```json
    {
        "general": {
            "aTokenNamePrefix": "Cod3x Lend ",
            "aTokenSymbolPrefix": "cl",
            "debtTokenNamePrefix": "Cod3x Lend variable debt bearing ",
            "debtTokenSymbolPrefix": "clDebt",
            "marketReferenceCurrencyAggregator": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
            "networkBaseTokenAggregator": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
            "treasury": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
            "usdBootstrapAmount": 1000000000000000000 // USD amount in wei that needs to be deposited during deployment to avoid inflation attack
        },
        // List of reserves and their configurations
        "poolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "VOLATILE", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 0, // Id of strategy choosen from all available strategies deployed or listed in configuration
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 150,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            },
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "STABLE",
                "interestStratId": 0,
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 150,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        //Bool value that determines whether to use already existing strats
        "usePreviousStrats": false,
        // List of volatile interest strategies and their configurations
        "volatileStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.45e27,
                "variableRateSlope1": 0.07e27,
                "variableRateSlope2": 3e27
            }
        ],
        // List of stable interest strategies and their configurations
        "stableStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.75e27,
                "variableRateSlope1": 0.01e27,
                "variableRateSlope2": 0.1e27
            }
        ],
        // List of pi interest strategies and their configurations
        "piStrategies": [
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            },
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        // All necessary configuration to deploy oracle for specified assets
        "oracleConfig": {
            "assets": [
                "0x4200000000000000000000000000000000000006",
                "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            ],
            "baseCurrency": "0x0000000000000000000000000000000000000000",
            "baseCurrencyUnit": 1e18,
            "fallbackOracle": "0x0000000000000000000000000000000000000000",
            "sources": [
                "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
                "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3"
            ],
            "timeouts": [
                100000,
                100000
            ]
        }
    }
    ```
##### **3_StratsToAdd**
  - Shall be used to deploy interest strategies 
  - Example:
    ```json
    {
        "poolAddressesProviderConfig": {
            "marketId": "UV TestNet Market", // Not used in this script
            "poolId": 0, // id of the miniPool
            "poolOwner": "0xf298Db641560E5B733C43181937207482Ff79bc9" // mini pool owner address (Not used in this script)
        },
        // List of volatile interest strategies and their configurations for main lending pool
        "volatileStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.45e27,
                "variableRateSlope1": 0.07e27,
                "variableRateSlope2": 3e27
            }
        ],
        // List of stable interest strategies and their configurations for main lending pool
        "stableStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.75e27,
                "variableRateSlope1": 0.01e27,
                "variableRateSlope2": 0.1e27
            }
        ],
        // List of pi interest strategies and their configurations for main lending pool
        "piStrategies": [
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "WBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        // List of volatile interest strategies and their configurations for mini pool
        "miniPoolVolatileStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.45e27,
                "variableRateSlope1": 0.07e27,
                "variableRateSlope2": 3e27
            }
        ],
        // List of stable interest strategies and their configurations for mini pool
        "miniPoolStableStrategies": [
            {
                "baseVariableBorrowRate": 0e27,
                "optimalUtilizationRate": 0.45e27,
                "variableRateSlope1": 0.07e27,
                "variableRateSlope2": 3e27
            }
        ],
        // List of pi interest strategies and their configurations for mini pool
        "miniPoolPiStrategies": [
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "WBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "assetReserveType": true,
                "ki": 13e19,
                "kp": 1e27,
                "maxITimeAmp": 1728000,
                "minControllerError": -400e24,
                "optimalUtilizationRate": 45e25,
                "symbol": "USDT",
                "tokenAddress": "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2"
            }
        ]
    }
    
    ```
##### **4_AssetsToAdd**
  - Shall be used to add new assets into reserves
  - Example:
    ```json

    {
        "general": {
            "aTokenNamePrefix": "Cod3x Lend ",
            "aTokenSymbolPrefix": "cl",
            "debtTokenNamePrefix": "Cod3x Lend variable debt bearing ",
            "debtTokenSymbolPrefix": "clDebt",
            "marketReferenceCurrencyAggregator": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
            "networkBaseTokenAggregator": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
            "treasury": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
            "usdBootstrapAmount": 2000000000000000000
        },
        "poolAddressesProviderConfig": {
            "marketId": "UV TestNet Market", // Not used in this script
            "poolId": 0,
            "poolOwner": "0xf298Db641560E5B733C43181937207482Ff79bc9" // Not used in this script
        },
        // List of reserves and their configurations for main lennding pool
        "lendingPoolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "VOLATILE", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 0, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 0,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "WBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "PI",
                "interestStratId": 2,
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 0,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        // List of reserves and their configurations for mini pool
        "miniPoolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "VOLATILE",
                "interestStratId": 0, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 150,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "aWBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "STABLE",
                "interestStratId": 0, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7500,
                "miniPoolOwnerFee": 150,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "aUSDT",
                "tokenAddress": "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2"
            }
        ],
        // All necessary configuration to deploy oracle for specified assets
        "oracleConfig": {
            "assets": [
                "0x4200000000000000000000000000000000000006",
                "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
                "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",
                "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2"
            ],
            "baseCurrency": "0x0000000000000000000000000000000000000000",
            "baseCurrencyUnit": 1e18,
            "fallbackOracle": "0x0000000000000000000000000000000000000000",
            "sources": [
                "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
                "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
                "0xd0C7101eACbB49F3deCcCc166d238410D6D46d57",
                "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7"
            ],
            "timeouts": [
                100000
            ]
        }
    }
    ```
##### **5_Reconfigure**
  - Shall be used to reconfigure reserves parameters
  - Example:
    ```json
    {
        "poolAddressesProviderConfig": {
            "marketId": "UV TestNet Market", // Not used in this script
            "poolId": 0,
            "poolOwner": "0xf298Db641560E5B733C43181937207482Ff79bc9" // Not used in this script
        },
        // List of reserves and their configurations for main lending pool
        "lendingPoolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "VOLATILE", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 1, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10400,
                "liquidationThreshold": 7400,
                "miniPoolOwnerFee": 233,
                "params": "0x10",
                "rates": 0.04e27,
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "WBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "STABLE", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 1, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7400,
                "miniPoolOwnerFee": 233,
                "params": "0x10",
                
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        // List of reserves and their configurations for mini pool
        "miniPoolReserversConfig": [
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "VOLATILE", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 1, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7700,
                "miniPoolOwnerFee": 233,
                "params": "0x10",
                "rates": 0.02e27,
                "reserveFactor": 1500,
                "reserveType": true,
                "symbol": "aWBTC",
                "tokenAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c"
            },
            {
                "baseLtv": 7000,
                "borrowingEnabled": true,
                "interestStrat": "PI", // Type of the strategy: VOLATILE / STABLE / PI
                "interestStratId": 3, // Id of strategy choosen from all available strategies deployed or listed in configuration. In this case all strats are listed in ./outputs/DeployedStrategies.json
                "liquidationBonus": 10500,
                "liquidationThreshold": 7100,
                "miniPoolOwnerFee": 233,
                "params": "0x10",
                
                "reserveFactor": 1600,
                "reserveType": true,
                "symbol": "aUSDT",
                "tokenAddress": "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2"
            }
        ]
    }
    
    ```
##### **6_ChangePeripherials**
  - Shall be used to set treasury, vault and rewarder
  - Shall be used to turn on rehypothecation
  - All keys shall have equal number of list elements. For those elements that don't need to configure, the "configure" param shall be set to false
  - Example:
    ```json
    {
        "miniPoolId": 0, //Id of mini pool to configure
        "cod3xLendDataProvider": {
            "deploy": false,
            "marketReferenceCurrencyAggregator": "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
            "networkBaseTokenAggregator": "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70"
        }, //flag used for deployment new cod3x data provider
        // List of configuration for treasury change
        "treasury": [
            {
                "configure": false, // determine whether treasury needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new treasury asset
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            },
            {
                "configure": true, // determine whether treasury needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new treasury asset
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            }
        ],
        "miniPoolCod3xTreasury": [
            {
                "configure": true, // determine whether treasury needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
                "owner": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA" // pool owner
            }
        ],
        "vault": [
            {
                "configure": false, // determine whether vault needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new vault asset
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            },
            {
                "configure": true, // determine whether vault needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new vault asset
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            }
        ],
        "rewarder": [
            {
                "configure": false, // determine whether rewarder needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new rewarder asset. NOTE: Write address(0) to have new deployment !
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            },
            {
                "configure": true, // determine whether rewarder needs to be changed for this asset
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // new rewarder asset. NOTE: Write address(0) to have new deployment !
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006"
            }
        ],
        "rewarder6909": [
            {
                "configure": false,
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // NOTE: Write address(0) to have new deployment !
                "reserveType": true,
                "symbol": "aUSDC",
                "tokenAddress": "0xF491AF584A573d3accd5B61Ab9677D769CB1c806"
            },
            {
                "configure": true,
                "newAddress": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA", // NOTE: Write address(0) to have new deployment !
                "reserveType": true,
                "symbol": "aWETH",
                "tokenAddress": "0x5D06644F64cEf0299d8dFF67f08E1eC5e883C1a4"
            }
        ],
        "rehypothecation": [
            {
                "claimingThreshold": 1e8,
                "configure": false, // determine whether rehypothecation needs to be changed for this asset
                "drift": 200,
                "farmingPct": 2000,
                "profitHandler": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
                "reserveType": true,
                "symbol": "USDC",
                "tokenAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
                "vault": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA" // if vault is already set for the asset this param doesn't matter
            },
            {
                "claimingThreshold": 1e8,
                "configure": true, // determine whether rehypothecation needs to be changed for this asset
                "drift": 200,
                "farmingPct": 2000,
                "profitHandler": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
                "reserveType": true,
                "symbol": "WETH",
                "tokenAddress": "0x4200000000000000000000000000000000000006",
                "vault": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA" // if vault is already set for the asset this param doesn't matter
            }
        ]
    }
    ```
##### **7_TransferOwnerships**
   - Shall be run at the end of configuration in order to transfer all contracts ownerships 
   - Before run it is possible to configure whether to transfer only mini pool ownership or all main pool roles
   - Example:
   ```json
   {
        "transferMiniPoolRole": true, // used to determine which ownership transfer shall happen
       "roles": {
           "addressesProviderOwner": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
           "emergencyAdmin": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
           "dataProviderOwner": "0x3151CfCA393FE5Eec690feD2a2446DA5a073d01B",
           "oracleOwner": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
           "piInterestStrategiesOwner": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
           "poolAdmin": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA",
           "rewarderOwner": "0x3151CfCA393FE5Eec690feD2a22222A5a073dAAA"
       },
        "miniPoolRole": {
            "miniPoolId": 0,
            "newPoolOwner": "0xf298Db641560E5B733C43181937207482Ff79bc9",
            "poolOwnerTreasury": "0xf298Db641560E5B733C43181937207482Ff79bc9"
        }
   }
   ```
##### **8_TestConfig**
  - Can be in script for fork tests (8_TestBasicActions_Fork.s) or staginf tests (8_TestBasicActions_Staging.s)
  - Shall be used to test basic actions for deployed contracts
  - Example:
    ```json
    {
        // test params
        "collateralAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "borrowAssetAddress": "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c",
        "depositAmount": 5000000000, // amount used for depositing (with deposit asset decimals)
        "borrowAmount": 50000000000000000, // amount used for borrowing (with borrow asset decimals)
        "bootstrapMainPool": true, // if the flag is enabled then script deposit assets to all configured reserves in specific lending pool 
        "bootstrapMiniPool": true, // if the flag is enabled then script deposit assets to all configured reserves in specific mini pool determined by poolId
        "usdAmountToDeposit": 50000000000000000000, // amount used for bootstrapping
        "poolAddressesProviderConfig": {
            "marketId": "UV TestNet Market",
            "poolId": 0, // id of the mini pool that will be used in a tests
            "poolOwner": "0xf298Db641560E5B733C43181937207482Ff79bc9"
        }
    }
    ```
### Output files
##### **0_MockedTokens**
  - List of mocked tokens deployed (used for testnet or new tokens)
  - Example:
  ```json
    {
    "mockedTokens": [
        "0x9C6f0f8e1fbBBae2bF463B17ee7f073D11FefbDD",
        "0x09C32EB866c0B54Db3F66d82837464464D39f659",
        "0xAd63737Ad3d1684B0f4BE7c0dd388D5d822ce638",
        "0xAC0bE3C599fdb3eE90635cfdBe60A74f81957Bf3"
    ]
    }
  ```
##### **1_LendingPoolContracts**
  - List of main lending pool infrastructure contracts addresses
  - Used by 2_DeployMiniPool.s, 3_AddStrats.s, 4_AddAssets.s, 5_Reconfigure.s
  - Example:
  ```json
    {
        "aTokenImpl": "0xFdDf7715602291C815ff4406E9E1A09678b5AA9a",
        "aTokens": [
            "0x89eD3c85B5C1EAe681552747a341E0C4Ca32A622",
            "0x72135819B751FF166472dd2f3022D7950bcd1A32"
        ],
        "cod3xLendDataProvider": "0x9f0F725568eBf6EDF1995816546B961A86Db5Dd9",
        "debtTokens": [
            "0x771Cfa5a7615FA3584Df29fc2df5c9B9b25977D0",
            "0x83a850e2b49360798E77209fAd8F349B799744e6"
        ],
        "lendingPool": "0x8eb2bB8934c6dd46Ac9d310914eeDF8fe2444Cf0",
        "lendingPoolAddressesProvider": "0x50A8caB71f058fA5fAFc3738d6156bc0818BF1F2",
        "lendingPoolConfigurator": "0xe390c0c899B3E1d66162099ba69c7228FAd5E32b",
        "oracle": "0xA6A20B9Ac4E981Ce50860DE3e10Babbb31efD5bc",
        "piStrategies": [
            "0x073573440a2875E479cbE12F4F8CcA86277c6de2"
        ],
        "stableStrategies": [
            "0x0e23B3dE27Eba4447f10E73e62344cEa92Dfb29d"
        ],
        "variableDebtTokenImpl": "0x80AA00918E246c76A3508eD282dEa9fB9d5B85Fc",
        "volatileStrategies": [
            "0xB07c69E2789D15Fc51182a8776037b772186b035"
        ],
        "wethGateway": "0x7399A8b3aCb222DD203153dBB1C8247112C933AD",
        "wrappedTokens": [
            "0x5D06644F64cEf0299d8dFF67f08E1eC5e883C1a4",
            "0xF491AF584A573d3accd5B61Ab9677D769CB1c806"
        ]
    }
  ```
##### **2_MiniPoolContracts**
  - List of mini pool infrastructure contracts addresses
  - Used by 3_AddStrats.s, 4_AddAssets.s, 5_Reconfigure.s
  - Example:
  ```json
    {
        "aTokenErc6909Impl": "0x110866e2dDb354052f8e82c9b5e6f70657f697b3",
        "aTokenErc6909Proxy": [
            "0xdF000a2F2531a31FD42FDdAF450b55262030D1B3",
            "0xb02bD4A5592A150b17Ff3Ac07f6a2A7b2D39D9e6",
            "0x5B79D13bB27A37d082469E9520f3193934d574e2"
        ],
        "flowLimiter": "0xa62646006A0f6cBf2bc0d8F714109c5CA9c212BE",
        "miniPoolAddressesProvider": "0x0fD39f9EA3c31988f252C4A9d7a7E6974C16CFf2",
        "miniPoolConfigurator": "0x6122b0306E7169B8CDbEF3df3264C4C86f60BE77",
        "miniPoolImpl": "0xF848b8086a70Ed315027ECB0e62c6893dd952642",
        "miniPoolPiStrategies": [],
        "miniPoolProxy": [
            "0x714624aE78095Db0E6c574FCdfa1F1f6c2c656f4",
            "0xB6f97fA7F4DAdb780b5927Df892962099A32827c",
            "0x25ac4B5c5fd57Ae3629469133743fD611caE2468"
        ],
        "miniPoolStableStrategies": [
            "0x380D4cfaDcF186e82c1d340e2F9428621444d452"
        ],
        "miniPoolVolatileStrategies": [
            "0x5e1698f3281E42101A93098A5201240502ea7cF1"
        ]
    }
  ```
##### **3_DeployedStrategies**
  - List of all strategies deployed so far 
  - Used by 4_AddAssets.s, 5_Reconfigure.s ***in correct order !***
  - Addresses in the array corresponds with the symbols in the array
  - Example:
  ```json
    {
        "miniPoolPiStrategies": [
            "0x486056653845AE60d9cEAd581B27A6433fbee660",
            "0x86e4B254Cf1FEdF27EA73eDd51e96e7c5cD24604",
            "0xb452eeB187df21592DaDb67E8B0590584415d28D",
            "0x37aD96F513FF0b60f4240734625f40501487D6D0"
        ],
        "miniPoolPiStrategiesSymbols": [
            "WETH",
            "USDC",
            "WBTC",
            "USDT"
        ],
        "miniPoolStableStrategies": [
            "0xe8D27ce05F3700906162Df7881002f4706d12b0d",
            "0x5658eEAF14a785C523Cc838406Fe32e7DaEdf6cb"
        ],
        "miniPoolVolatileStrategies": [
            "0xDBE218eaDD164E9380F5819F6cf40095Df16Ee94",
            "0x7647F3C5f235c7B71a3771F064aC0d608E368707"
        ],
        "piStrategies": [
            "0xdb026094f6b5b3A6aEEEBea25c60E5cfE9eB8E49",
            "0xdF55c0A5e4171b8e9238E01Ebc9725ebd25E1d09",
            "0xF0049934cdCf0d5011aE6c9B6dA4c4F0D082330b"
        ],
        "piStrategiesSymbols": [
            "WETH",
            "WBTC",
            "USDC"
        ],
        "stableStrategies": [
            "0xb798354d5731A9EA700a7B3bC3f7bfE30c562003",
            "0xF86CD7286898138FEAc919097DcD4458Da4a488b"
        ],
        "volatileStrategies": [
            "0x5343da84067fD87179C92a8A86D79662CF3cC505",
            "0xC0d324d5af75BBDf062f2f0DE026a48163875C87"
        ]
    }
  ```
  ##### **4_AddedAssets**
  - List of all yield bearing tokens in all pool after addition
  - Example:
  ```json
    {
        "aTokenImpl": "0xFdDf7715602291C815ff4406E9E1A09678b5AA9a",
        "aTokens": [
            "0x89eD3c85B5C1EAe681552747a341E0C4Ca32A622",
            "0x72135819B751FF166472dd2f3022D7950bcd1A32",
            "0xfF5D2E6d289C7c9a2cf38B2d9EEBE1A20Fa69381"
        ],
        "debtTokens": [
            "0x771Cfa5a7615FA3584Df29fc2df5c9B9b25977D0",
            "0x83a850e2b49360798E77209fAd8F349B799744e6",
            "0x273F86fb4c50A2b9063fac5dc8c47e4CDbFF7843"
        ],
        "variableDebtTokenImpl": "0x80AA00918E246c76A3508eD282dEa9fB9d5B85Fc",
        "wrappedTokens": [
            "0x5D06644F64cEf0299d8dFF67f08E1eC5e883C1a4",
            "0xF491AF584A573d3accd5B61Ab9677D769CB1c806",
            "0x27914Eb047D7D3d322D3158BB75800FFd09B4489"
        ]
    }
  ```
  ##### **6_DeployedPeripherials**
  - List of deployed peripherials
  - Example:
  ```json
    {
    "cod3xLendDataProvider": "0x9dcf274D58d4Fc29CB093bE979d509555d1F157D",
    "rewarder": "0x3460a33582FC850d707ceA83f29f49D7b6290979",
    "rewarder6909": "0xCA3c1FC0d5EdbAC5d8AB7742D4ff6F7053E04280"
    }
  ```

 ##### **contracts.csv**
  - run prepareContractList.py to get all contracts list in csv format