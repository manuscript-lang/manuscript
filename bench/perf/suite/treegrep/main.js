const fs = require("node:fs");
const path = require("node:path");
let files = 0, matches = 0;
function scan(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { scan(p); continue; }
    files++;
    for (const line of fs.readFileSync(p, "utf8").split("\n")) {
      if (line.includes(" POST /api/v2/item/17") && line.includes(" 500 ")) matches++;
    }
  }
}
scan(process.argv[2]);
console.log(`files: ${files}`);
console.log(`matches: ${matches}`);
