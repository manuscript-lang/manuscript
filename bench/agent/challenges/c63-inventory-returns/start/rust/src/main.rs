use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{BufRead, Write};

struct Order {
    items: Vec<(String, u64)>,
    status: &'static str,
    total: u64,
}

#[derive(Default)]
struct State {
    stock: BTreeMap<String, u64>,
    price: HashMap<String, u64>,
    orders: HashMap<String, Order>,
}

fn money(c: u64) -> String {
    format!("{}.{:02}", c / 100, c % 100)
}

fn valid(s: &str, ok: impl Fn(u8) -> bool) -> bool {
    !s.is_empty() && s.bytes().all(ok)
}

fn valid_sku(s: &str) -> bool {
    valid(s, |c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'-')
}

fn valid_oid(s: &str) -> bool {
    valid(s, |c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
}

fn number(s: &str) -> Option<u64> {
    if s.len() > 7 || !valid(s, |c| c.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

fn qty(s: &str) -> Option<u64> {
    number(s).filter(|n| (1..=100000).contains(n))
}

fn exec(line: &str, st: &mut State) -> Vec<String> {
    let t: Vec<&str> = line.split(' ').collect();
    let c = t[0];
    let want = match c {
        "stock" | "price" => 3,
        "cancel" | "ship" => 2,
        "report" => 1,
        "order" => 0,
        _ => return vec!["error: unknown command".into()],
    };
    if (c == "order" && t.len() < 3) || (c != "order" && t.len() != want) {
        return vec!["error: usage".into()];
    }
    match c {
        "stock" => {
            if !valid_sku(t[1]) {
                return vec!["error: bad sku".into()];
            }
            let q = match qty(t[2]) {
                Some(q) => q,
                None => return vec!["error: bad quantity".into()],
            };
            let e = st.stock.entry(t[1].to_string()).or_insert(0);
            *e += q;
            let now = *e;
            st.price.entry(t[1].to_string()).or_insert(0);
            vec![format!("ok {} stock={}", t[1], now)]
        }
        "price" => {
            let p = match number(t[2]) {
                Some(p) if p <= 10000000 => p,
                _ => return vec!["error: bad price".into()],
            };
            if !st.stock.contains_key(t[1]) {
                return vec![format!("error: unknown sku {}", t[1])];
            }
            st.price.insert(t[1].to_string(), p);
            vec!["ok".into()]
        }
        "order" => {
            let id = t[1];
            if !valid_oid(id) {
                return vec!["error: bad order id".into()];
            }
            if st.orders.contains_key(id) {
                return vec![format!("error: order {} already exists", id)];
            }
            let mut items = Vec::new();
            for tok in &t[2..] {
                let p: Vec<&str> = tok.split(':').collect();
                match (p.len() == 2 && valid_sku(p[0]), if p.len() == 2 { qty(p[1]) } else { None }) {
                    (true, Some(q)) => items.push((p[0].to_string(), q)),
                    _ => return vec![format!("error: bad item {}", tok)],
                }
            }
            let mut seen = HashSet::new();
            for (sku, q) in &items {
                if seen.contains(sku) {
                    return vec![format!("error: duplicate sku {}", sku)];
                }
                match st.stock.get(sku) {
                    None => return vec![format!("error: unknown sku {}", sku)],
                    Some(&have) if *q > have => {
                        return vec![format!("error: insufficient stock for {} (have {}, need {})", sku, have, q)]
                    }
                    _ => {}
                }
                seen.insert(sku.clone());
            }
            let mut total = 0;
            for (sku, q) in &items {
                *st.stock.get_mut(sku).unwrap() -= q;
                let p = st.price[sku];
                total += if *q >= 10 { (q * p * 90 + 50) / 100 } else { q * p };
            }
            st.orders.insert(id.to_string(), Order { items, status: "placed", total });
            vec![format!("ok {} total={}", id, money(total))]
        }
        "cancel" | "ship" => {
            let o = match st.orders.get_mut(t[1]) {
                Some(o) => o,
                None => return vec![format!("error: unknown order {}", t[1])],
            };
            if c == "cancel" {
                if o.status != "placed" {
                    return vec![format!("error: order {} already {}", t[1], o.status)];
                }
                o.status = "cancelled";
                for (sku, q) in &o.items {
                    *st.stock.get_mut(sku).unwrap() += q;
                }
                return vec!["ok".into()];
            }
            match o.status {
                "shipped" => vec![format!("error: order {} already shipped", t[1])],
                "cancelled" => vec![format!("error: order {} is cancelled", t[1])],
                _ => {
                    o.status = "shipped";
                    vec!["ok".into()]
                }
            }
        }
        _ => {
            let mut reserved: HashMap<&str, u64> = HashMap::new();
            let (mut placed, mut shipped, mut cancelled, mut revenue) = (0, 0, 0, 0);
            for o in st.orders.values() {
                match o.status {
                    "placed" => {
                        placed += 1;
                        for (sku, q) in &o.items {
                            *reserved.entry(sku).or_insert(0) += q;
                        }
                    }
                    "shipped" => {
                        shipped += 1;
                        revenue += o.total;
                    }
                    _ => cancelled += 1,
                }
            }
            let mut out: Vec<String> = st
                .stock
                .iter()
                .map(|(sku, n)| {
                    format!("{} stock={} price={} reserved={}", sku, n, money(st.price[sku]), reserved.get(sku.as_str()).copied().unwrap_or(0))
                })
                .collect();
            out.push(format!("orders placed={} shipped={} cancelled={}", placed, shipped, cancelled));
            out.push(format!("revenue={}", money(revenue)));
            out
        }
    }
}

fn main() {
    let stdin = std::io::stdin();
    let mut st = State::default();
    let mut out = String::new();
    for line in stdin.lock().lines() {
        let l = line.unwrap();
        if l.trim_matches(' ').is_empty() {
            continue;
        }
        for o in exec(&l, &mut st) {
            out.push_str(&o);
            out.push('\n');
        }
    }
    std::io::stdout().write_all(out.as_bytes()).unwrap();
}
