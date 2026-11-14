const data = require("node:fs").readFileSync(0, "utf8");
let rows = 0, latency = 0;
const classes = [0, 0, 0, 0];
const paths = new Map();
for (const line of data.split("\n")) {
  if (line === "") continue;
  const f = line.split(" ");
  rows++;
  latency += parseInt(f[5], 10) || 0;
  classes[f[4].charCodeAt(0) - 50]++;
  paths.set(f[3], (paths.get(f[3]) || 0) + 1);
}
console.log(`lines: ${rows}`);
console.log(`status: 2xx=${classes[0]} 3xx=${classes[1]} 4xx=${classes[2]} 5xx=${classes[3]}`);
console.log(`latency: ${latency}`);
const ranked = [...paths].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
for (const [k, v] of ranked.slice(0, 5)) console.log(`${k} ${v}`);
