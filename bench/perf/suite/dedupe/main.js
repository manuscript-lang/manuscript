const data = require("node:fs").readFileSync(0, "utf8");
const lines = new Map(), names = new Map();
let total = 0;
for (const line of data.split("\n")) {
  if (line === "") continue;
  total++;
  lines.set(line, (lines.get(line) || 0) + 1);
  const name = line.slice(0, line.indexOf(" "));
  names.set(name, (names.get(name) || 0) + 1);
}
let most = "", count = 0;
for (const [k, v] of lines) if (v > count || (v === count && k < most)) { most = k; count = v; }
console.log(`lines: ${total}`);
console.log(`distinct lines: ${lines.size}`);
console.log(`distinct names: ${names.size}`);
console.log(`most repeated: ${most} x${count}`);
