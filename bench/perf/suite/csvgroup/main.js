// RFC 4180 records over bytes; a field with quotes is unescaped into its own string.
const b = require("node:fs").readFileSync(0);
const rows = [];
let row = [], field = [], inQuotes = false;
const flush = () => { row.push(Buffer.from(field).toString("utf8")); field = []; };
for (let i = 0; i < b.length; i++) {
  const c = b[i];
  if (inQuotes) {
    if (c === 34) {
      if (i + 1 < b.length && b[i + 1] === 34) { field.push(34); i++; } else inQuotes = false;
    } else field.push(c);
  } else if (c === 34 && field.length === 0) inQuotes = true;
  else if (c === 44) flush();
  else if (c === 10) { flush(); rows.push(row); row = []; }
  else field.push(c);
}
const regions = new Map();
const products = new Map();
let quoted = 0;
for (const r of rows.slice(1)) {
  const cents = (parseInt(r[3], 10) || 0) * (parseInt(r[4], 10) || 0);
  const e = regions.get(r[1]) || [0, 0];
  e[0]++; e[1] += cents;
  regions.set(r[1], e);
  products.set(r[2], (products.get(r[2]) || 0) + cents);
  if (r[5].includes(",")) quoted++;
}
console.log(`rows: ${rows.length - 1}`);
console.log(`quoted: ${quoted}`);
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
for (const k of [...regions.keys()].sort(cmp)) console.log(`${k} ${regions.get(k)[0]} ${regions.get(k)[1]}`);
for (const [k, v] of [...products].sort((a, b) => b[1] - a[1] || cmp(a[0], b[0])).slice(0, 5)) console.log(`${k} ${v}`);
