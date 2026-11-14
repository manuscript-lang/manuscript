use std::cmp::Reverse;
use std::collections::{BinaryHeap, VecDeque};

struct Edge { to: usize, w: i64 }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

fn build(n: usize, m: usize) -> Vec<Vec<Edge>> {
    let mut adj: Vec<Vec<Edge>> = (0..n).map(|_| Vec::new()).collect();
    let mut x = 7;
    for _ in 0..m {
        x = lcg(x);
        let a = (x % n as i64) as usize;
        x = lcg(x);
        let b = (x % n as i64) as usize;
        x = lcg(x);
        let w = 1 + x % 100;
        adj[a].push(Edge { to: b, w });
        adj[b].push(Edge { to: a, w });
    }
    adj
}

fn bfs(adj: &[Vec<Edge>], start: usize) -> i64 {
    let mut level = vec![-1i64; adj.len()];
    let mut queue = VecDeque::new();
    level[start] = 0;
    queue.push_back(start);
    let (mut reached, mut depth_sum) = (0i64, 0i64);
    while let Some(u) = queue.pop_front() {
        reached += 1;
        depth_sum += level[u];
        for e in &adj[u] {
            if level[e.to] < 0 {
                level[e.to] = level[u] + 1;
                queue.push_back(e.to);
            }
        }
    }
    reached * 1000 + depth_sum % 1000
}

fn dijkstra(adj: &[Vec<Edge>], start: usize) -> i64 {
    let mut dist = vec![1_000_000_000i64; adj.len()];
    let mut pq = BinaryHeap::new();
    dist[start] = 0;
    pq.push(Reverse((0i64, start)));
    while let Some(Reverse((d, u))) = pq.pop() {
        if d > dist[u] { continue; }
        for e in &adj[u] {
            let nd = d + e.w;
            if nd < dist[e.to] {
                dist[e.to] = nd;
                pq.push(Reverse((nd, e.to)));
            }
        }
    }
    let (mut total, mut far) = (0i64, 0i64);
    for &d in &dist {
        if d < 1_000_000_000 {
            total += d;
            if d > far { far = d; }
        }
    }
    total % 1000003 * 1000 + far
}

fn find(parent: &[usize], x: usize) -> usize {
    let mut r = x;
    while parent[r] != r { r = parent[r]; }
    r
}

fn components(n: usize, m: usize) -> usize {
    let mut parent: Vec<usize> = (0..n).collect();
    let mut x = 99;
    let mut count = n;
    for _ in 0..m {
        x = lcg(x);
        let a = find(&parent, (x % n as i64) as usize);
        x = lcg(x);
        let b = find(&parent, (x % n as i64) as usize);
        if a != b { parent[a] = b; count -= 1; }
    }
    count
}

fn main() {
    let n = 200000;
    let adj = build(n, 800000);
    println!("bfs {}", bfs(&adj, 0));
    println!("dijkstra {}", dijkstra(&adj, 0));
    println!("components {}", components(n, 150000));
}
