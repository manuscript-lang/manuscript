const lcg = (x) => (Math.imul(x, 1103515245) + 12345) & 0x7fffffff; // exact mod 2^31 (a plain product exceeds 2^53)

function build(n, m) {
  const adj = Array.from({ length: n }, () => []);
  let x = 7;
  for (let i = 0; i < m; i++) {
    x = lcg(x); const a = x % n;
    x = lcg(x); const b = x % n;
    x = lcg(x); const w = 1 + (x % 100);
    adj[a].push({ to: b, w });
    adj[b].push({ to: a, w });
  }
  return adj;
}

function bfs(adj, start) {
  const level = new Array(adj.length).fill(-1);
  const queue = [start];
  level[start] = 0;
  let reached = 0, depthSum = 0;
  for (let head = 0; head < queue.length; head++) {
    const u = queue[head];
    reached++;
    depthSum += level[u];
    for (const e of adj[u]) {
      if (level[e.to] < 0) { level[e.to] = level[u] + 1; queue.push(e.to); }
    }
  }
  return reached * 1000 + (depthSum % 1000);
}

// Binary min-heap ordered by (dist, node).
class Heap {
  constructor() { this.a = []; }
  less(x, y) { return x.dist < y.dist || (x.dist === y.dist && x.node < y.node); }
  push(v) {
    const a = this.a; a.push(v);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!this.less(a[i], a[p])) break;
      [a[i], a[p]] = [a[p], a[i]]; i = p;
    }
  }
  pop() {
    const a = this.a;
    if (a.length === 0) return undefined;
    const top = a[0], last = a.pop();
    if (a.length > 0) {
      a[0] = last;
      let i = 0;
      for (;;) {
        let s = i; const l = 2 * i + 1, r = l + 1;
        if (l < a.length && this.less(a[l], a[s])) s = l;
        if (r < a.length && this.less(a[r], a[s])) s = r;
        if (s === i) break;
        [a[i], a[s]] = [a[s], a[i]]; i = s;
      }
    }
    return top;
  }
}

function dijkstra(adj, start) {
  const dist = new Array(adj.length).fill(1000000000);
  const pq = new Heap();
  dist[start] = 0;
  pq.push({ dist: 0, node: start });
  for (let it = pq.pop(); it; it = pq.pop()) {
    if (it.dist > dist[it.node]) continue;
    for (const e of adj[it.node]) {
      const nd = it.dist + e.w;
      if (nd < dist[e.to]) { dist[e.to] = nd; pq.push({ dist: nd, node: e.to }); }
    }
  }
  let total = 0, far = 0;
  for (const d of dist) if (d < 1000000000) { total += d; if (d > far) far = d; }
  return (total % 1000003) * 1000 + far;
}

function find(parent, x) { let r = x; while (parent[r] !== r) r = parent[r]; return r; }

function components(n, m) {
  const parent = Array.from({ length: n }, (_, i) => i);
  let x = 99, count = n;
  for (let i = 0; i < m; i++) {
    x = lcg(x); const a = find(parent, x % n);
    x = lcg(x); const b = find(parent, x % n);
    if (a !== b) { parent[a] = b; count--; }
  }
  return count;
}

const n = 200000;
const adj = build(n, 800000);
console.log(`bfs ${bfs(adj, 0)}`);
console.log(`dijkstra ${dijkstra(adj, 0)}`);
console.log(`components ${components(n, 150000)}`);
