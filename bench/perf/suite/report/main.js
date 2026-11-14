const data = require("node:fs").readFileSync(0, "utf8");
const out = [];
let total = 0;
for (const line of data.split("\n")) {
  if (line === "") continue;
  const i = line.indexOf(" ");
  const name = line.slice(0, i);
  const score = parseInt(line.slice(i + 1), 10) || 0;
  total += score;
  out.push(`${name.padEnd(12)} ${String(score).padStart(8)} ${Math.trunc((score * 3) / 7)}\n`);
}
out.push(`total ${total}\n`);
process.stdout.write(out.join(""));
