const data = require("node:fs").readFileSync(0, "utf8");
const recs = [];
for (const line of data.split("\n")) {
  if (line === "") continue;
  const i = line.indexOf(" ");
  recs.push([line.slice(0, i), parseInt(line.slice(i + 1), 10) || 0]);
}
recs.sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
let check = 0;
recs.forEach((r, i) => { check = (check * 31 + r[1] + i) % 1000000007; });
console.log(`records: ${recs.length}`);
console.log(`checksum: ${check}`);
for (const i of [0, 1, 2, recs.length - 1]) console.log(`${recs[i][0]} ${recs[i][1]}`);
