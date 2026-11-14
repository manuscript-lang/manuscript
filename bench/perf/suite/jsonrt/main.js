const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff;

function makeText(n) {
  const parts = ["["];
  let x = 1;
  for (let i = 0; i < n; i++) {
    x = lcg(x);
    if (i > 0) parts.push(",");
    parts.push(`{"id":${i},"name":"item-${x % 1000}","score":${Math.trunc(x / 7) % 10000},"tags":["t${x % 7}","t${x % 11}"],"nested":{"a":${x % 5},"b":[${x % 3},${x % 13}]}}`);
  }
  parts.push("]");
  return parts.join("");
}

function walk(v) {
  if (v === null || typeof v === "boolean") return 1;
  if (typeof v === "number") return v;
  if (typeof v === "string") return v.length;
  if (Array.isArray(v)) return v.reduce((t, item) => t + walk(item), 0);
  let t = 0;
  for (const k of Object.keys(v)) t += k.length + walk(v[k]);
  return t;
}

const text = makeText(120000);
let total = 0, outLen = 0;
for (let pass = 0; pass < 3; pass++) {
  const doc = JSON.parse(text);
  total += walk(doc);
  outLen += JSON.stringify(doc).length;
}
console.log(`text ${text.length} walk ${total} out ${outLen}`);
