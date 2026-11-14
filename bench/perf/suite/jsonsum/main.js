const root = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
const scores = new Map(), tags = new Map();
let records = 0, active = 0, nameBytes = 0;
for (const r of root) {
  records++;
  if (typeof r.user === "string" && typeof r.score === "number") scores.set(r.user, (scores.get(r.user) || 0) + r.score);
  if (Array.isArray(r.tags)) for (const t of r.tags) if (typeof t === "string") tags.set(t, (tags.get(t) || 0) + 1);
  if (r.active === true) active++;
  if (typeof r.name === "string") nameBytes += Buffer.byteLength(r.name);
}
console.log(`records: ${records}`);
console.log(`active: ${active}`);
console.log(`name bytes: ${nameBytes}`);
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
for (const [k, v] of [...scores].sort((a, b) => b[1] - a[1] || cmp(a[0], b[0])).slice(0, 5)) console.log(`${k} ${v}`);
for (const k of [...tags.keys()].sort(cmp)) console.log(`${k} ${tags.get(k)}`);
