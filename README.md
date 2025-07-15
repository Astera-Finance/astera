# Astera Protocol
[INTERNAL ONLY] For the development of Astera Protocol Features.

*(Please create branches for each of the below features -- do not merge to master)*

## Quick start

### Env setup
```bash
mv .env.example .env
```
Fill your `RPC_PROVIDER` in the `.env`.

### Foundry
```bash
forge install && yarn
forge test
```

### Echidna
```bash
forge install && yarn
echidna tests/echidna/PropertiesMain.sol --contract PropertiesMain --config tests/echidna/config/config1_fast.yaml
```


## Typing conventions

### Variables

-   storage: `_x`
-   memory/stack: `x`
-   function params: `x`
-   contracts/events/structs: `MyContract`
-   errors: in `Errors.sol`
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