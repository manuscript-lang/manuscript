const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff; // exact mod 2^31 (a plain product exceeds 2^53)

class Node {
  constructor(key) { this.key = key; this.left = null; this.right = null; }
  insert(key) {
    let n = this;
    for (;;) {
      if (key === n.key) return;
      const side = key < n.key ? "left" : "right";
      if (n[side] === null) { n[side] = new Node(key); return; }
      n = n[side];
    }
  }
  count() { return 1 + (this.left ? this.left.count() : 0) + (this.right ? this.right.count() : 0); }
  height() { return 1 + Math.max(this.left ? this.left.height() : 0, this.right ? this.right.height() : 0); }
  sum() { return this.key + (this.left ? this.left.sum() : 0) + (this.right ? this.right.sum() : 0); }
}

const make = (d) => (d === 0 ? null : { left: make(d - 1), right: make(d - 1) });
const count = (t) => (t === null ? 1 : 1 + count(t.left) + count(t.right));

const root = new Node(1000000000);
let x = 11;
for (let i = 0; i < 400000; i++) { x = lcg(x); root.insert(x % 2000000000); }
console.log(`bst ${root.count()} ${root.height()} ${root.sum() % 1000003}`);

let nodes = 0;
for (let r = 0; r < 40; r++) nodes += count(make(16));
console.log(`trees ${nodes}`);

let head = null;
for (let i = 0; i < 1000000; i++) head = { value: i, next: head };
let total = 0;
for (let c = head; c !== null; c = c.next) total += c.value;
console.log(`list ${total}`);
