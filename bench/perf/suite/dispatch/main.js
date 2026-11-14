class Sq { constructor(s) { this.s = s; } area() { return this.s * this.s; } grow(by) { return (this.s + by) * (this.s + by); } }
class Rect { constructor(w, h) { this.w = w; this.h = h; } area() { return this.w * this.h; } grow(by) { return (this.w + by) * (this.h + by); } }
class Tri {
  constructor(b, h) { this.b = b; this.h = h; }
  area() { return Math.trunc((this.b * this.h) / 2); }
  grow(by) { return Math.trunc(((this.b + by) * (this.h + by)) / 2); }
}

function shapes(n) {
  const xs = [];
  for (let i = 0; i < n; i++) {
    const k = i % 3;
    if (k === 0) xs.push(new Sq((i % 10) + 1));
    else if (k === 1) xs.push(new Rect((i % 7) + 1, (i % 5) + 1));
    else xs.push(new Tri((i % 9) + 1, (i % 4) + 1));
  }
  let total = 0;
  for (let pass = 0; pass < 20; pass++) for (const s of xs) total += s.area() + s.grow(pass);
  return total;
}

function closures(n) {
  const offset = 3;
  const steps = [(x) => x + offset, (x) => x * 2, (x) => x - 1, (x) => x % 1000003];
  let acc = 1;
  for (let i = 0; i < n; i++) for (const f of steps) acc = f(acc + i);
  return acc;
}

class Stack {
  constructor() { this.items = []; }
  push(v) { this.items.push(v); }
  pop() { return this.items.pop(); }
}

const foldWith = (xs, init, step) => { let acc = init; for (const x of xs) acc = step(acc, x); return acc; };

function generics(n) {
  const s = new Stack();
  let t = 0;
  for (let i = 0; i < n; i++) {
    s.push(i % 1000);
    if (i % 3 === 2) { const v = s.pop(); if (v !== undefined) t += v; }
  }
  return t + foldWith(s.items, 0, (a, x) => a + x * 2);
}

console.log(`shapes ${shapes(1000000)}`);
console.log(`closures ${closures(15000000)}`);
console.log(`generics ${generics(20000000)}`);
