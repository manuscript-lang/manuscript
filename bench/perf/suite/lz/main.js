const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff;

function makeInput(n) {
  const vocab = [];
  let x = 17;
  for (let w = 0; w < 200; w++) {
    const word = [];
    x = lcg(x);
    const count = 3 + (Math.trunc(x / 11) % 8);
    for (let k = 0; k < count; k++) { x = lcg(x); word.push(97 + (Math.trunc(x / 13) % 26)); }
    vocab.push(word);
  }
  const out = [];
  while (out.length < n) {
    x = lcg(x);
    for (const c of vocab[Math.trunc(x / 17) % 200]) out.push(c);
    out.push(32);
  }
  return out;
}

function compress(data) {
  const head = new Array(65536).fill(-1);
  const out = [];
  const n = data.length;
  for (let i = 0; i < n; ) {
    let best = 0, dist = 0;
    if (i + 3 <= n) {
      // data[i] * 506832829 stays below 2^53, so plain number arithmetic is exact
      const h = (data[i] * 506832829 + data[i + 1] * 65599 + data[i + 2]) % 65536;
      const cand = head[h];
      head[h] = i;
      if (cand >= 0 && i - cand < 32768) {
        let len = 0;
        while (i + len < n && len < 255 && data[cand + len] === data[i + len]) len++;
        if (len >= 3) { best = len; dist = i - cand; }
      }
    }
    if (best >= 3) { out.push(256 + best, dist); i += best; }
    else { out.push(data[i]); i++; }
  }
  return out;
}

function decompress(tokens) {
  const out = [];
  for (let i = 0; i < tokens.length; ) {
    const t = tokens[i];
    if (t < 256) { out.push(t); i++; }
    else {
      const len = t - 256, start = out.length - tokens[i + 1];
      for (let k = 0; k < len; k++) out.push(out[start + k]);
      i += 2;
    }
  }
  return out;
}

const data = makeInput(4000000);
let checksum = 0;
for (let pass = 0; pass < 3; pass++) {
  const packed = compress(data);
  const unpacked = decompress(packed);
  if (unpacked.length !== data.length || unpacked.some((v, i) => v !== data[i])) console.log("MISMATCH");
  checksum += packed.length;
}
console.log(`input ${data.length} tokens ${checksum}`);
