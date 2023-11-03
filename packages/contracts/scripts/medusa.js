const fs = require('fs');
const path = require('path');

const testResults = '../medusa/test_results'

async function main() {
    const files = await fs.promises.readdir(testResults);

    for (const f of files) {
        const p = path.join(testResults, f);
        const stat = await fs.promises.stat(p);

        if (stat.isFile()) {
            const buf = fs.readFileSync(p);
            const objs = JSON.parse(buf.toString());

            const calls = [];

            for (const o of objs) {
                const abiValues = o.call.dataAbiValues;
                calls.push(`${abiValues.methodName}(${abiValues.inputValues.join(',')});`);
            }

            console.log(calls);
        }
    }
}

main();