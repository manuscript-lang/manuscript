const data = require("node:fs").readFileSync(0, "utf8").toLowerCase();
const counts = new Map();
let total = 0;
for (const w of data.split(/[ .\n]+/)) {
  if (w === "") continue;
  total++;
  counts.set(w, (counts.get(w) || 0) + 1);
}
console.log(`words: ${total}`);
console.log(`distinct: ${counts.size}`);
const ranked = [...counts].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
for (const [k, v] of ranked.slice(0, 10)) console.log(`${k} ${v}`);
