const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff;

let x = 21;
const words = [];
for (let i = 0; i < 300000; i++) {
  x = lcg(x);
  words.push(`  Item-${x % 100000}_${Math.trunc(x / 3) % 977} `);
}
let upperLen = 0, replaced = 0, found = 0, padded = 0;
for (const w of words) {
  const t = w.trim();
  upperLen += t.toUpperCase().length;
  replaced += t.replaceAll("_", "--").replaceAll("Item", "I").length;
  if (t.includes("77")) found++;
  const i = t.indexOf("-");
  if (i >= 0) found += i;
  padded += t.padStart(20, ".").length + t.toLowerCase().padEnd(24, "*").length;
}
const joined = words.map((w) => w.trim());
joined.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
let sortedSample = 0;
for (let i = 0; i < joined.length; i += 1000) sortedSample += joined[i].length + joined[i].charCodeAt(5);
let text = "";
for (const w of joined) { if (text.length > 200000) break; text += w + ","; }
console.log(`upper ${upperLen} replaced ${replaced} found ${found} padded ${padded} sorted ${sortedSample} parts ${text.split(",").length}`);
