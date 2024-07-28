# Cod3x Lend Protocol
[INTERNAL ONLY] For the development of Cod3x Lend Protocol Features.

*(Please create branches for each of the below features -- do not merge to master)*

## Setup
**To begin testing:**
```
1. run 'npm i' in project root
2. remove '.example' suffix from .env.example and hardhat.config.ts.example
3. run 'yarn compile' or 'npm run compile'
4. run 'yarn test' or 'npm run test'
5. to see test coverage, run 'yarn coverage' or 'npm run coverage'

Note: Node LTS is recommended (18.12.1)
```
## Features

### Committed
- [ ] Modified Rewarder
- [ ] Isolated Pools
- [ ] B2B Lending
- [ ] Improve Algorithmic Governability

### Explore
- [ ] Liquidation Value Capture
- [ ] Isolated LTV
- [ ] Time-Based Risk Parameters
- [ ] Rewarder User Profiles
- [ ] Dynamic Interest Rate Models

### Time Permitting
- [ ] Automated Buybacks

### Test
 Run "forge test -vvvv --via-ir" to test with forge

## Typing conventions

### Variables

-   storage: `_x`
-   memory/stack: `x`
-   function params: `x`
-   contracts/events/structs: `MyContract`
-   errors: `MyContract__ERROR_DESCRIPTION`
-   public/external functions: `myFunction()`
-   internal/private functions: `_myFunction()`
-   comments: "This is a comment to describe the variable `amount`."

### Nat Specs

```js
/**
 * @dev Internal function called whenever a position's state needs to be modified.
 * @param _amount Amount of poolToken to deposit/withdraw.
 * @param _relicId The NFT ID of the position being updated.
 * @param _kind Indicates whether tokens are being added to, or removed from, a pool.
 * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
 * @return poolId_ Pool ID of the given position.
 * @return received_ Amount of reward token dispensed to `_harvestTo` on harvest.
 */
```

### Formating

Please use `forge fmt` before commiting.