# Granary V2 Protocol
[INTERNAL ONLY] For the development of Granary V2 Protocol Features.

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