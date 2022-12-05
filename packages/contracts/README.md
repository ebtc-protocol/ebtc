# Foundry Test suite

## Installation:
Use this guide to install foundry:
https://book.getfoundry.sh/getting-started/installation

## Running foundry tests
- Simply `cd` into target test package:
  - `cd packages/contracts`
- Run `forge test`

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