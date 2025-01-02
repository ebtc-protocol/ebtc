# Foundry Test suite

## Installation:
Use this guide to install foundry:
https://book.getfoundry.sh/getting-started/installation

## Running Foundry tests
- Simply `cd` into target test package:
  - `cd packages/contracts`
- Run `forge test`

## Running Foundry fork tests for broken property reproducers
To run Foundry fork tests for reproducers:
- Add the reproducer test for the broken property to the `ForkToFoundry` contract
- Change the block number in the call to `vm.createSelectFork` to the block number in the coverage report that gets dynamically replaced in the [`Setup`](https://github.com/ebtc-protocol/ebtc/blob/925073f04bdfe5a6b594898d6491950087eee23b/packages/contracts/contracts/TestContracts/invariants/Setup.sol#L348) contract. 
  - The block number shown in the coverage report for the run will be the block at which Echidna forked mainnet from for your run.
- Rename the `.env.example` file to `.env` and add your rpc url.
- `cd` into the target test package:
  - `cd packages/contracts`
- Run `forge test --mt <broken_property_reproducer_test>`


## Remappings:
Foundry test configuration is using existing hardhat dependencies, such as @openzeppelin etc.
They are declated in `remappings.txt`.

If error like `ParserError source X not found` you might want to purge all existing node modules.

To do that, simply locate all `node_modules` everywhere and do from root of the project:
```shell
rm -rf node_modules
rm -rf packages/contracts/node_modules
rm -rf packages/fuzzer/node_modules
```
Then from root of the project run:
```shell
yarn install
```

And everything should work

