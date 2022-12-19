import yargs from "yargs";
import "colors";

import { chaos, order } from "./commands/chaos";
import { warzone } from "./commands/warzone";
import { checkSorting, checkSubgraphCmd, dumpCdpsCmd } from "./commands/checks";

const wrapCmd = <A extends unknown[], R>(cmd: (...args: A) => Promise<R>) => async (...args: A) => {
  try {
    return await cmd(...args);
  } catch (error) {
    console.error(error);
  }
};

yargs
  .scriptName("yarn fuzzer")

  .command(
    "warzone",
    "Create lots of Cdps.",
    {
      cdps: {
        alias: "n",
        default: 1000,
        description: "Number of cdps to create"
      }
    },
    wrapCmd(warzone)
  )

  .command(
    "chaos",
    "Try to break Liquity by randomly interacting with it.",
    {
      users: {
        alias: "u",
        default: 40,
        description: "Number of users to spawn"
      },
      rounds: {
        alias: "n",
        default: 25,
        description: "How many times each user should interact with Liquity"
      },
      subgraph: {
        alias: "g",
        default: false,
        description: "Check after every round that subgraph data matches layer 1"
      }
    },
    wrapCmd(chaos)
  )

  .command(
    "order",
    "End chaos and restore order by liquidating every Cdp except the Funder's.",
    {},
    wrapCmd(order)
  )

  .command("check-sorting", "Check if Cdps are sorted by ICR.", {}, wrapCmd(checkSorting))

  .command(
    "check-subgraph",
    "Check that subgraph data matches layer 1.",
    {},
    wrapCmd(checkSubgraphCmd)
  )

  .command("dump-cdps", "Dump list of Cdps.", {}, wrapCmd(dumpCdpsCmd))

  .strict()
  .demandCommand()
  .wrap(null)
  .parse();
