
# Setup base local fork.

```
git clone https://github.com/Cod3x-Labs/Cod3x-Lend
git checkout liquidationBotFixes
mv .env.example .env
```

Make sure everything work.
```
yarn
forge t 
```
4 or 5 tests should be failing at this point.

## Setup env

Change `MAINNET` from `false` to `true`.

Add `PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` to the `.env`.

Add `RPC_URL=http://127.0.0.1:8545` to the `.env`.

Add `BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<your_key>` to the `.env`.

`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (the 1st anvil generated key) will be the admin.

Setup Anvil fork
```
source .env
anvil --fork-url $BASE_RPC_URL --fork-block-number 28178226
```

## Setup liquidity

Get some ETH to `wETH`, `cbBTC`, `USDC` and `cdxUSD`.
```
forge script scripts/localFork/0_DealToken.s.sol --chain-id 8453 --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 
```

## Setup protocol

Deploy LP:
```
forge script scripts/1_DeployLendingPool.s.sol --chain-id 8453 --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 
```

Replace the `clAsset` addresses in `inputs/2_DeploymentConfig.json` with the addresses generated from `inputs/1_DeploymentConfig.json` execution.

Deploy MP:
```
forge script scripts/2_DeployMiniPool.s.sol --chain-id 8453 --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 
```


## Prices at block 28178226 (Base)

```
ETH    = 1920$
BTC    = 85800$
USDC   = 1$
cdxUSD = 1$
```