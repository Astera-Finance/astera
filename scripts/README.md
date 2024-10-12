### How to use scripts:
#### 1. Fill .env (determine what kind of scripts you want to run LOCAL_FORK/TESTNET/MAINNET)
#### 2. Write data into configuration file scripts/inputs/<nr>_<configName>.json
#### 3. Run the script:
   - Fork:
     - to run, only configuration with corresponding number shall be filled
     - run `forge script scripts/<nr>_<scriptName>.s.sol`
   - Testnet: 
     - to run, there is need to have already executed script with previous <nr>
     - import env variables via `source .env`
     - run `forge script --chain sepolia scripts/<nr>_<scriptName>.s.sol --rpc-url $ARB_SEPOLIA -vvvv --broadcast`
   - Mainnet: