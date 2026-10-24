// V8 baseline: same corpora, same measurement protocol as src/main.ms.
const fs = require("fs");
const names = process.argv.slice(2);
const budgetNs = 1e9;
function run(fn) {
  fn(); // warm-up
  const t = [];
  let total = 0;
  while (total < budgetNs || t.length < 5) {
    const s = process.hrtime.bigint();
    fn();
    const d = Number(process.hrtime.bigint() - s);
    t.push(d);
    total += d;
  }
  t.sort((a, b) => a - b);
  return t[t.length >> 1];
}
for (const n of names) {
  const text = fs.readFileSync(`${__dirname}/data/${n}.json`, "utf8");
  const v = JSON.parse(text);
  const bytes = Buffer.byteLength(text);
  const p = run(() => JSON.parse(text));
  const s = run(() => JSON.stringify(v));
  console.log(`${n}\tparse\t${p}\t${bytes}`);
  console.log(`${n}\tstringify\t${s}\t${bytes}`);
}
