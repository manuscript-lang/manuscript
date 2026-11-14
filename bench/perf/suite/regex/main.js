const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff;

function makeText(lines) {
  const parts = [];
  let x = 9;
  for (let i = 0; i < lines; i++) {
    x = lcg(x);
    parts.push(`user${x % 5000}@host${Math.trunc(x / 3) % 90}.com 10.${x % 256}.${Math.trunc(x / 5) % 256}.${Math.trunc(x / 7) % 256} GET /api/v${x % 4}/items/${Math.trunc(x / 11) % 100000} ${200 + (x % 3) * 100} took ${x % 900}ms\n`);
  }
  return parts.join("");
}

const text = makeText(120000);
const emailCount = (text.match(/[a-z]+[0-9]*@[a-z]+[0-9]*\.com/g) || []).length;
let octets = 0;
for (const m of text.matchAll(/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/g)) octets += parseInt(m[4], 10);
let took = 0;
for (const m of text.matchAll(/took ([0-9]+)ms/g)) took += parseInt(m[1], 10);
const masked = text.replace(/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/g, "x.x.x.x");
const versions = (text.match(/\/api\/v[0-9]\//g) || []).length;
const pieces = text.split(/ +/).length;
console.log(`emails ${emailCount} octets ${octets} took ${took} masked ${masked.length} versions ${versions} pieces ${pieces}`);
