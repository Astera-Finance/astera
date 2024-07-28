# Echidna

Echidna is a program designed for fuzzing/property-based testing of Ethereum smart contracts. Please refer to the doc for [installation](https://github.com/crytic/echidna#installation).

```sh
yarn
echidna tests/echidna/GranaryPropertiesMain.sol --contract GranaryPropertiesMain --config tests/echidna/config/config1_fast.yaml
```

You can fine in `/echidna` 3 config files to run the fuzzer:

- 1< min | `config1_fast.yaml`
- 5< min | `config2_slow.yaml`
- 50 min | `config3_inDepth.yaml`

![inheritance graph](./images/inheritance_graph.png)

# TODO

- Improve the bootstraping with users setup with coherante positions.
- Implemente all "To implement" invariants.
- Fix all todos in the echidna/codebase.
- Properly document each invariants.

# Invariant testing

## Implemented

### General

100. ✅ To be liquidated on a given collateral asset, the target user must own the associated `aTokenColl`.
101. ✅ To be liquidated on a given token, the target user must own the associated `vTokenDebt`.
102. ✅ `liquidationCall()` must only be callable when the target health factor is < 1.
103. ✅ `liquidationCall()` must decrease the target `vTokenDebt` balance by `amount`.
104. ✅ `liquidationCall()` must increase the liquidator `aTokenColl` (or `collAsset`) balance.
105. ✅ `liquidationCall()` must decrease the liquidator debt asset balance if `randReceiveAToken` is true or `collAsset` is not equal to `debtAsset`.

### LendingPool

201. ✅ `deposit()` must increase the user aToken balance by `amount`.
202. ✅ `deposit()` must decrease the user asset balance by `amount`.
203. ✅ `withdraw()` must decrease the user aToken balance by `amount`.
204. ✅ `withdraw()` must increase the user asset balance by `amount`.
205. ✅ A user must not be able to `borrow()` if they don't own aTokens.
206. ✅ `borrow()` must only be possible if the user health factor is greater than 1.
207. ✅ `borrow()` must not result in a health factor of less than 1.
208. ✅ `borrow()` must increase the user debtToken balance by `amount`.
209. ✅ `borrow()` must decrease `borrowAllowance()` by `amount` if `user != onBehalf`.
210. ✅ `repay()` must decrease the onBehalfOf debtToken balance by `amount`.
211. ✅ `repay()` must decrease the user asset balance by `amount`.
212. ✅ `healthFactorAfter` must be greater than `healthFactorBefore`.
213. ✅ `setUseReserveAsCollateral` must not reduce the health factor below 1.
214. ✅ Users must not be able to steal funds from flashloans.
215. ✅ The total value borrowed must always be less than the value of the collaterals.
216. ✅ each user postions must remain solvent.
217. ✅ The `liquidityIndex` should monotonically increase when there's total debt.
218. ✅ The `variableBorrowIndex` should monotonically increase when there's total debt.
219. ✅ A user with debt should have at least an aToken balance `setUsingAsCollateral`.
220. ❌ If all debt is repaid, all `aToken` holder should be able to claim their collateral.
221. ❌ If all users withdraw their liquidity, there must not be aTokens supply left.

### ATokens

300. ✅ Zero amount transfers should not break accounting.
301. ✅ Once a user has a debt, they must not be able to transfer aTokens if this results in a health factor less than 1.
302. ✅ Transfers for more than available balance should not be allowed.
303. ✅ Transfers should update accounting correctly.
304. ✅ Self transfers should not break accounting.
305. ✅ Zero amount transfers must not break accounting.
306. ✅ Once a user has a debt, they must not be able to transfer aTokens if this results in a health factor less than 1.
307. ✅ Transfers for more than available balance must not be allowed.
308. ✅ `transferFrom()` must only transfer if the sender has enough allowance from the `from` address.
309. ✅ Transfers must update accounting correctly.
310. ✅ Self transfers must not break accounting.
311. ✅ `transferFrom()` must decrease allowance.
312. ✅ `approve()` must never revert.
313. ✅ Allowance must be modified correctly via `approve()`.
314. ✅ `increaseAllowance()` must never revert.
315. ✅ Allowance must be modified correctly via `increaseAllowance()`.
316. ✅ `decreaseAllowance()` must revert when the user tries to decrease more than currently allowed.
317. ✅ Allowance must be modified correctly via `decreaseAllowance()`.
318. 🚧 User nonce must increase by one.
319. 🚧 Mutation in the signature must make `permit()` revert.
320. 🚧 Mutation in parameters must make `permit()` revert.
321. 🚧 User allowance must be equal to `amount` when the sender calls `permit()`.
322. ✅ Force feeding assets in LendingPool, ATokens, or debtTokens must not change the final result.
323. ✅ Force feeding aToken in LendingPool, ATokens, or debtTokens must not change the final result.
324. ❌ A user must not hold more than total supply.
325. ❌ Sum of users' balance must not exceed total supply.

### DebtTokens

400. ✅ `approveDelegation()` must never revert.
401. ✅ Allowance must be modified correctly via `approve()`.

## To implement

- **LendingPool**

  - Integrity of Supply Cap - aToken supply shall never exceed the cap.
  - `ReserveConfigurationMap` integrity:
    - If borrow ⇒ reserve is active, not frozen and enabeled
    - If deposit ⇒ reserve is active and not frozen

## Admin entry points

✚ : GranaryV2 add

### LendingPoolAddressesProvider

- `setMarketId(string memory marketId)`
- `setAddressAsProxy(bytes32 id, address implementationAddress)`
- `setAddress(bytes32 id, address newAddress)`

### LendingPoolAddressesProviderRegistry

- `registerAddressesProvider(address provider, uint256 id)`
- `unregisterAddressesProvider(address provider)`

### LendingPoolConfigurator

- `batchInitReserve(InitReserveInput[] calldata input)`
- `updateAToken(UpdateATokenInput calldata input)`
- `updateVariableDebtToken(UpdateDebtTokenInput calldata input)`
- `enableBorrowingOnReserve(address asset, bool reserveType)`
- `disableBorrowingOnReserve(address asset, bool reserveType)`
- `configureReserveAsCollateral(address asset, bool reserveType, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus)`
- `activateReserve(address asset, bool reserveType)`
- `deactivateReserve(address asset, bool reserveType)`
- `freezeReserve(address asset, bool reserveType)`
- `unfreezeReserve(address asset, bool reserveType)`
- `setReserveFactor(address asset, bool reserveType, uint256 reserveFactor)`
- `setDepositCap(address asset, bool reserveType, uint256 depositCap)`
- `setReserveVolatilityTier(address asset, bool reserveType, uint256 tier)`
- `setLowVolatilityLtv(address asset, bool reserveType, uint256 ltv)`
- `setMediumVolatilityLtv(address asset, bool reserveType, uint256 ltv)`
- `setHighVolatilityLtv(address asset, bool reserveType, uint256 ltv)`
- `setReserveInterestRateStrategyAddress(address asset, bool reserveType, address rateStrategyAddress)`
- `setPoolPause(bool val)`
- ✚ `setFarmingPct(address aTokenAddress, uint256 farmingPct)`
- ✚ `setClaimingThreshold(address aTokenAddress, uint256 claimingThreshold)`
- ✚ `setFarmingPctDrift(address aTokenAddress, uint256 _farmingPctDrift)`
- ✚ `setProfitHandler(address aTokenAddress, address _profitHandler)`
- ✚ `setVault(address aTokenAddress, address _vault)`
- ✚ `rebalance(address aTokenAddress)`

## User entry points

### LendingPool

- `deposit(address asset, bool reserveType, uint256 amount, address onBehalfOf)`
- `withdraw(address asset, bool reserveType, uint256 amount, address onBehalfOf)`
- `borrow(address asset, bool reserveType, uint256 amount, address onBehalfOf)`
- `repay(address asset, bool reserveType, uint256 amount, address onBehalfOf)`
- `setUserUseReserveAsCollateral(address asset, bool reserveType, bool useAsCollateral)`
- `liquidationCall(address collateralAsset, bool collateralAssetType, address debtAsset, bool debtAssetType, address user, uint256 debtToCover, bool receiveAToken)`
- `flashLoan(FlashLoanParams memory flashLoanParams, uint256[] calldata amounts, uint256[] calldata modes, bytes calldata params)`

### AToken

- `transfer(address recipient, uint256 amount)`
- `transferFrom(address sender, address recipient, uint256 amount)`
- `approve(address spender, uint256 amount)`
- `increaseAllowance(address spender, uint256 addedValue)`
- `decreaseAllowance(address spender, uint256 subtractedValue)`
- `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`

### VariableDebtToken

- `approveDelegation(address delegatee, uint256 amount)`
