const data = require("node:fs").readFileSync(0, "utf8");
let hits = 0;
for (const l of data.split("\n")) if (l.includes(" POST /api/v2/item/17") && l.includes(" 500 ")) hits++;
console.log(`hits: ${hits}`);
