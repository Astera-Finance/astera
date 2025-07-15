To see coverage on the side bar:
1. Install CoverageGutters add-on in VS code
2. Move one lcovx.info to project root dir and rename it to `lcov.info`
3. Click `watch` button in bottom strip

**lcov1.info:**
- AToken.t.sol
- ATokenErc6909.t.sol
- ATokenNonRebasing.t.sol
- AsteraLendDataProvider.t.sol
- DefaultReserveInterestRateStrategy.t.sol
- LendingPoolAddressesProvider.t.sol
- LendingPoolConfigurator.t.sol

**lcov2.info:**
- pidTests
- Flashloan.t.sol
- Liquidation.t.sol
- MiniPoolFlashloan.t.sol
- MiniPoolRepayWithdrawTransfer.t.sol

**lcov3.info:**
- MiniPoolAddressProvider.t.sol
- MiniPoolATokenAbstraction.t.sol
- MiniPoolConfigurator.t.sol
- MiniPoolLiquidation.t.sol
- MiniPoolRewarder.t.sol
- MultipleMiniPools.t.sol

**lcov4.info:**
- helpers
- MathRayInt.t.sol
- Oracle.t.sol
- Pausable-Functions.t.sol
- Rehypothecation.t.sol
- UpgradesAndReconfigurations.t.sol
- VariableDebtToken.t.sol


**Coverage TODO:**

- BorrowLogic - DONE
- DepositLogic - DONE
- FlashLoanLogic:
  - [ ] Flashloan with mode different than NONE
- GenericLogic:
  - [x] balanceDecreaseAllowed
- LiquidationLogic:
  - [ ] liquidation in following situations:
    - [ ] vars.userVariableDebt < vars.actualDebtToLiquidate
    - [ ] automatically disable reserve as collateral if all user's collateral liquidated
    - [ ] liquidation with flag receiveAToken and vars.
- ReserveLogic - DONE
- ValidationLogic:
   - [x] cover Errors.VL_NO_DEBT_OF_SELECTED_TYPE
- WithdrawLogic - DONE

- AToken.t.sol:
  - [x] transferOnLiquidation (same as aave)

- ATokenErc6909.t.sol:
  - [x] transfer/transferFrom underlying token (covered indirectly)
  - [x] handlingAction _afterTokenTransfer (with set incentives controller) (for minting and transfers)

- ATokenNonRebasing.t.sol:
  - [ ] Increase/decrease allowance

- AsteraLendDataProvider.t.sol
  - [ ] Dev In progress

- DefaultReserveInterestRateStrategy.t.sol - DONE

- LendingPoolAddressesProvider.t.sol - DONE

LendingPoolConfigurator.t.sol:
- [x] updateAToken
- [x] updateDebtToken
- [x] configure with liquidation threshold equal 0
- [x] enable/disable flashloan

BasePiReserveRateStrategy.t.sol:
- [ ] setOptimalUtilizationRate, setMinControllerError, setPidValues

Flashloan.t.sol:
- [ ] Flashloan with mode different than NONE

MiniPoolBorrowLogic: DONE
MiniPoolDepositLogic: DONE
MiniPoolFlashLoanLogic: DONE
MiniPoolGenericLogic:
- [x] balanceDecreaseAllowed -> Errors.VL_TRANSFER_NOT_ALLOWED - covered
MiniPoolLiquidationLogic:
- [ ] liquidation in following situations:
  - [ ] vars.userVariableDebt < vars.actualDebtToLiquidate
  - [ ] automatically disable reserve as collateral if all user's collateral liquidated
  - [ ] liquidation with flag receiveAToken and vars.liquidatorPreviousATokenBalance == 0
MiniPoolReserveLogic - DONE
MiniPoolValidationLogic:
 - [ ] cover Errors.VL_NO_DEBT_OF_SELECTED_TYPE
MiniPoolWithdrawLogic - DONE

MiniPool:
- [ ] _repayLendingPool -> call this.withdraw(...)

MiniPoolConfigurator:
- [x] configure with liquidation threshold equal 0
- [x] enable/disable flashloan
- [x] setReserveInterestRateStrategyAddress 
- [x] updateFlashloanPremiumTotal
- [x] setRewarderForReserve (in Rewarder tests)
- [x] setPoolAdmin

MiniPoolAddressProvider: DONE

FlowLimiter: DONE

Rewarder:
- [x] claimRewardsForPool
- [x] forwardRewardsForPool
- [x] setClaimer
- [x] claimRewardsOnBehalf
- [x] claimRewardsToSelf
- [x] claimAllRewards
- [x] _claimRewards
- [x] setDistributionEnd/getDistributionEnd

Rewarder6909:
- [x] transferRewards
- [x] set/get Claimer
- [x] claimRewardsOnBehalf
- [x] claimRewardsToSelf
- [x] claimAllRewards
- [x] set/getDistributionEnd
- [x] getUserUnclaimedRewardsFromStorage
- [x] getAllUserRewardsBalance
- [x] _distributeRewards

Oracle:
- [ ] get price from fallback oracle

cumulateToLiquidityIndex move to FlashloanLogic