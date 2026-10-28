//! Exact caller counts. Small queries stay lazy; expensive batches share
//! ancestor bits over a condensed DAG, retaining only one word per component.

use super::reach_count;
use crate::facts::Facts;
use std::collections::HashMap;

pub(super) fn counts<'a>(
    queries: &[&'a str],
    callers: &HashMap<&str, Vec<&str>>,
    head: &Facts,
) -> HashMap<&'a str, usize> {
    // No incoming edge means no callers, without indexing an isolated graph.
    let mut result: HashMap<_, _> = queries
        .iter()
        .filter(|&&q| !callers.contains_key(q))
        .map(|&q| (q, 0))
        .collect();
    let queries: Vec<_> = queries
        .iter()
        .copied()
        .filter(|q| callers.contains_key(q))
        .collect();
    let n = head.entities.len();
    let blocks = n.div_ceil(64);
    if queries.len() <= blocks.max(1) {
        result.extend(queries.iter().map(|&key| (key, reach_count(key, callers))));
        return result;
    }
    let ids: HashMap<_, _> = head
        .entities
        .keys()
        .enumerate()
        .map(|(i, k)| (k.as_str(), i))
        .collect();
    let mut forward = vec![Vec::new(); n];
    let mut reverse = vec![Vec::new(); n];
    for (key, fact) in &head.entities {
        let from = ids[key.as_str()];
        for target in &fact.calls {
            if let Some(&to) = ids.get(target.as_str()) {
                forward[from].push(to);
                reverse[to].push(from);
            }
        }
    }
    let budget = n + forward.iter().map(Vec::len).sum::<usize>();
    let mut work = 0;
    let mut seen = vec![0usize; n];
    let mut stack = Vec::new();
    for (index, &query) in queries.iter().enumerate() {
        if work > budget && queries.len() - index > blocks {
            let remaining = &queries[index..];
            let targets: Vec<_> = remaining.iter().map(|q| ids[q]).collect();
            let counts = batch(&forward, &reverse, &targets);
            result.extend(remaining.iter().copied().zip(counts));
            break;
        }
        let generation = index + 1;
        let start = ids[query];
        seen[start] = generation;
        stack.push(start);
        let mut count = 0;
        while let Some(node) = stack.pop() {
            count += 1;
            work += 1 + reverse[node].len();
            for &caller in &reverse[node] {
                if seen[caller] != generation {
                    seen[caller] = generation;
                    stack.push(caller);
                }
            }
        }
        result.insert(query, count - 1);
    }
    result
}

fn batch(forward: &[Vec<usize>], reverse: &[Vec<usize>], targets: &[usize]) -> Vec<usize> {
    let n = forward.len();
    // Iterative DFS finishing order, so long chains do not consume call stack.
    let mut seen = vec![false; n];
    let mut order = Vec::with_capacity(n);
    let mut stack = Vec::new();
    for root in 0..n {
        if seen[root] {
            continue;
        }
        seen[root] = true;
        stack.push((root, 0));
        while let Some((node, edge)) = stack.last_mut() {
            if let Some(&next) = forward[*node].get(*edge) {
                *edge += 1;
                if !seen[next] {
                    seen[next] = true;
                    stack.push((next, 0));
                }
            } else {
                order.push(*node);
                stack.pop();
            }
        }
    }
    // Kosaraju's reverse pass assigns components in caller→callee order.
    let mut component = vec![usize::MAX; n];
    let mut count = 0;
    let mut pending = Vec::new();
    for &root in order.iter().rev() {
        if component[root] != usize::MAX {
            continue;
        }
        component[root] = count;
        pending.push(root);
        while let Some(node) = pending.pop() {
            for &next in &reverse[node] {
                if component[next] == usize::MAX {
                    component[next] = count;
                    pending.push(next);
                }
            }
        }
        count += 1;
    }
    let mut dag = vec![Vec::new(); count];
    for (node, edges) in forward.iter().enumerate() {
        for &next in edges {
            if component[node] != component[next] {
                dag[component[node]].push(component[next]);
            }
        }
    }
    for edges in &mut dag {
        edges.sort_unstable();
        edges.dedup();
    }
    let mut masks = vec![0u64; count];
    let mut result = vec![0; targets.len()];
    for first in (0..n).step_by(64) {
        masks.fill(0);
        for node in first..(first + 64).min(n) {
            masks[component[node]] |= 1 << (node - first);
        }
        for (from, edges) in dag.iter().enumerate() {
            for &to in edges {
                masks[to] |= masks[from];
            }
        }
        for (total, &target) in result.iter_mut().zip(targets) {
            *total += masks[component[target]].count_ones() as usize;
        }
    }
    // Each vertex seeds its own SCC; count all other distinct callers only.
    for total in &mut result {
        *total -= 1;
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adaptive_counts_match_lazy_reference_for_all_query_sizes() {
        use crate::facts::Fact;
        for shape in ["chain", "cycle", "pairs", "isolated", "diamond"] {
            let mut head = Facts::default();
            for i in 0..257 {
                let calls: Vec<usize> = match shape {
                    "chain" if i < 256 => vec![i + 1],
                    "cycle" => vec![(i + 1) % 257],
                    "pairs" if i % 2 == 0 && i < 256 => vec![i + 1],
                    "diamond" if i < 254 => vec![i + 1, i + 2, i + 1],
                    _ => vec![],
                };
                let key = format!("f{i:03}");
                let mut calls: Vec<_> = calls.into_iter().map(|i| format!("f{i:03}")).collect();
                calls.push("external".into());
                head.entities.insert(
                    key.clone(),
                    Fact {
                        key,
                        calls,
                        ..Fact::default()
                    },
                );
            }
            let mut callers = HashMap::<&str, Vec<&str>>::new();
            for (key, fact) in &head.entities {
                for target in &fact.calls {
                    callers.entry(target).or_default().push(key);
                }
            }
            for k in [0, 1, 4, 5, 64, 65, 129, 257] {
                let queries: Vec<_> = head.entities.keys().take(k).map(String::as_str).collect();
                let expected: HashMap<_, _> = queries
                    .iter()
                    .map(|&q| (q, reach_count(q, &callers)))
                    .collect();
                assert_eq!(counts(&queries, &callers, &head), expected, "{shape} K={k}");
            }
        }
    }

    #[test]
    fn batch_matches_bfs_with_cycles_diamonds_and_disconnected_nodes() {
        let mut seed = 8123u64;
        for n in [1, 2, 63, 64, 65, 129, 257] {
            for shape in 0..12 {
                let mut forward = vec![Vec::new(); n];
                let mut reverse = vec![Vec::new(); n];
                for (from, edges) in forward.iter_mut().enumerate() {
                    for (to, incoming) in reverse.iter_mut().enumerate() {
                        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
                        let linked = match shape {
                            0 => to == from + 1,
                            1 => to == (from + 1) % n,
                            2 => from % 2 == 0 && to == from + 1,
                            3 => false,
                            _ => seed >> 32 < u32::MAX as u64 / 20,
                        };
                        if linked {
                            edges.push(to);
                            incoming.push(from);
                        }
                    }
                }
                let targets: Vec<_> = (0..n).collect();
                let actual = batch(&forward, &reverse, &targets);
                for root in targets {
                    let mut seen = vec![false; n];
                    let mut stack = vec![root];
                    seen[root] = true;
                    while let Some(node) = stack.pop() {
                        for &next in &reverse[node] {
                            if !seen[next] {
                                seen[next] = true;
                                stack.push(next);
                            }
                        }
                    }
                    assert_eq!(
                        actual[root],
                        seen.into_iter().filter(|x| *x).count() - 1,
                        "n={n},shape={shape},root={root}"
                    );
                }
            }
        }
    }
}
