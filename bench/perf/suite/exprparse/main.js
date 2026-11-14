const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff;

let x = 3;

function gen(depth, out) {
  x = lcg(x);
  if (depth === 0 || x % 5 === 0) { out.push(String(Math.trunc(x / 7) % 100)); return; }
  x = lcg(x);
  const op = ["+", "-", "*", "%"][Math.trunc(x / 3) % 4];
  out.push("(");
  gen(depth - 1, out);
  out.push(" " + op + " ");
  gen(depth - 1, out);
  out.push(")");
}

function tokenize(text) {
  const toks = [];
  let i = 0;
  while (i < text.length) {
    const c = text.charCodeAt(i);
    if (c >= 48 && c <= 57) {
      let v = 0;
      while (i < text.length && text.charCodeAt(i) >= 48 && text.charCodeAt(i) <= 57) { v = v * 10 + text.charCodeAt(i) - 48; i++; }
      toks.push({ num: true, v });
    } else if (c === 32) i++;
    else { toks.push({ num: false, v: c }); i++; }
  }
  return toks;
}

class Parser {
  constructor(toks) { this.toks = toks; this.pos = 0; }
  expr() {
    const t = this.toks[this.pos++];
    if (t.num) return { op: 0, v: t.v, left: null, right: null };
    const left = this.expr();
    const o = this.toks[this.pos++];
    const op = o.num ? 0 : o.v;
    const right = this.expr();
    this.pos++;
    return { op, v: 0, left, right };
  }
}

function evaluate(e) {
  if (e.left === null) return e.v;
  const a = evaluate(e.left), b = evaluate(e.right);
  switch (e.op) {
    case 43: return (a + b) % 1000003;
    case 45: return (a - b) % 1000003;
    case 42: return (a * b) % 1000003;
  }
  return b === 0 ? a : a % b;
}

let total = 0, tokens = 0, chars = 0;
for (let i = 0; i < 60000; i++) {
  const parts = [];
  gen(9, parts);
  const text = parts.join("");
  chars += text.length;
  const toks = tokenize(text);
  tokens += toks.length;
  total = (total + evaluate(new Parser(toks).expr())) % 1000003;
}
console.log(`chars ${chars} tokens ${tokens} total ${total}`);
