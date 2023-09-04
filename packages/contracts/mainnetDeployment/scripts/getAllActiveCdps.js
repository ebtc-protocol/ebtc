const hre = require("hardhat");
const fs = require('fs');

async function main() {
  let latestBlock = await hre.ethers.provider.getBlockNumber()
  console.log('block number:', latestBlock)
  const chainId = await hre.ethers.provider.getNetwork()
  console.log('ChainId:', chainId.chainId)

  const deployerWallet = (await hre.ethers.getSigners())[0]
  const sortedCdpsFactory = await hre.ethers.getContractFactory("SortedCdps", deployerWallet)
  let sortedCdps = new hre.ethers.Contract(
    "0xdf00C96Efec9784022553d550898003E8e65D622",
    sortedCdpsFactory.interface,
    deployerWallet
  );
  const multiCdpGetterFactory = await hre.ethers.getContractFactory("MultiCdpGetter", deployerWallet)
  let multiCdpGetter = new hre.ethers.Contract(
    "0x2Aa97Af26385C5642140abf50cfd88bb5c18E1e3",
    multiCdpGetterFactory.interface,
    deployerWallet
  );

  let size = await sortedCdps.getSize()
  let cdps = await multiCdpGetter.getMultipleSortedCdps(0, size)
  const organizedData = cdps.map((item) => ({
    id: item[0],
    owner: extractAccountFromID(item[0]),
    debt: addDecimalPoint(item[1].toString()),
    coll: addDecimalPoint(item[2].toString()),
    stake: addDecimalPoint(item[3].toString()),
    snapshotEBTCDebt: addDecimalPoint(item[4].toString()),
  }));

  console.log(organizedData)

  // Convert the data to CSV format
  const csvData = organizedData.map(item => Object.values(item).join(','));

  // Add the header row
  const header = Object.keys(organizedData[0]).join(',');
  csvData.unshift(header);

  var current_date = await getCurrentDateInISOFormat()

  // Write the CSV data to a file
  fs.writeFileSync(`output_${latestBlock}_${current_date}.csv`, csvData.join('\n'));

  console.log('CSV file written successfully');
};

// Function to add a decimal point at the 18th position from the end
function addDecimalPoint(str) {
  return str.slice(0, -18) + '.' + str.slice(-18);
}

// Extract account from id
function extractAccountFromID(id) {
  if (typeof id !== 'string' || id.length < 42) {
    throw new Error('Input is not a valid string or does not have at least 42 characters.');
  }

  return id.substring(0, 42);
}

function getCurrentDateInISOFormat() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0'); // Months are 0-indexed
  const day = String(now.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });