const { testnetDeploy } = require('./testnetDeployment.js')
const configParams = require("./deploymentParams.localFork.js")

async function main() {
  await testnetDeploy(configParams)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
