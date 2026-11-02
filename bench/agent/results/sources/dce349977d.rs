use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{self, Read, Write};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Status {
    Placed,
    Shipped,
    Cancelled,
}

struct Sku {
    stock: i128,
    price: i128,
}

struct Order {
    status: Status,
    lines: Vec<(String, i128)>,
    total: i128,
}

#[derive(Default)]
struct State {
    skus: BTreeMap<String, Sku>,
    orders: HashMap<String, Order>,
}

const MAX_QTY: i128 = 100_000;
const MAX_PRICE: i128 = 10_000_000;

fn valid_sku(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'-')
}

fn valid_id(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// A number is 1 to 7 ASCII digits (leading zeros allowed), within [min, max].
fn parse_num(s: &str, min: i128, max: i128) -> Option<i128> {
    if s.is_empty() || s.len() > 7 || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let v: i128 = s.parse().ok()?;
    if v < min || v > max {
        None
    } else {
        Some(v)
    }
}

fn money(cents: i128) -> String {
    format!("{}.{:02}", cents / 100, cents % 100)
}

fn line_cost(qty: i128, price: i128) -> i128 {
    let raw = qty * price;
    if qty >= 10 {
        // round_half_up(raw * 90 / 100) for non-negative values
        (raw * 90 + 50) / 100
    } else {
        raw
    }
}

fn handle(st: &mut State, toks: &[&str], out: &mut String) {
    let err = |msg: String, out: &mut String| {
        out.push_str(&msg);
        out.push('\n');
    };
    let n = toks.len();
    match toks[0] {
        "stock" => {
            if n != 3 {
                return err("error: usage".into(), out);
            }
            let (sku, q) = (toks[1], toks[2]);
            if !valid_sku(sku) {
                return err("error: bad sku".into(), out);
            }
            let qty = match parse_num(q, 1, MAX_QTY) {
                Some(v) => v,
                None => return err("error: bad quantity".into(), out),
            };
            let entry = st
                .skus
                .entry(sku.to_string())
                .or_insert(Sku { stock: 0, price: 0 });
            entry.stock += qty;
            out.push_str(&format!("ok {} stock={}\n", sku, entry.stock));
        }
        "price" => {
            if n != 3 {
                return err("error: usage".into(), out);
            }
            let (sku, c) = (toks[1], toks[2]);
            let cents = match parse_num(c, 0, MAX_PRICE) {
                Some(v) => v,
                None => return err("error: bad price".into(), out),
            };
            match st.skus.get_mut(sku) {
                Some(s) if valid_sku(sku) => {
                    s.price = cents;
                    out.push_str("ok\n");
                }
                _ => err(format!("error: unknown sku {}", sku), out),
            }
        }
        "order" => {
            if n < 3 {
                return err("error: usage".into(), out);
            }
            let id = toks[1];
            if !valid_id(id) {
                return err("error: bad order id".into(), out);
            }
            if st.orders.contains_key(id) {
                return err(format!("error: order {} already exists", id), out);
            }
            // Syntax check of every item first.
            let mut items: Vec<(&str, i128)> = Vec::new();
            for t in &toks[2..] {
                let parts: Vec<&str> = t.split(':').collect();
                let ok = parts.len() == 2 && valid_sku(parts[0]);
                let qty = if ok { parse_num(parts[1], 1, MAX_QTY) } else { None };
                match qty {
                    Some(q) => items.push((parts[0], q)),
                    None => return err(format!("error: bad item {}", t), out),
                }
            }
            // Rules, in the order given.
            let mut seen: HashSet<&str> = HashSet::new();
            for &(sku, qty) in &items {
                if !seen.insert(sku) {
                    return err(format!("error: duplicate sku {}", sku), out);
                }
                match st.skus.get(sku) {
                    None => return err(format!("error: unknown sku {}", sku), out),
                    Some(s) if qty > s.stock => {
                        return err(
                            format!(
                                "error: insufficient stock for {} (have {}, need {})",
                                sku, s.stock, qty
                            ),
                            out,
                        )
                    }
                    _ => {}
                }
            }
            // Apply all at once.
            let mut total = 0i128;
            let mut lines = Vec::with_capacity(items.len());
            for &(sku, qty) in &items {
                let s = st.skus.get_mut(sku).unwrap();
                total += line_cost(qty, s.price);
                s.stock -= qty;
                lines.push((sku.to_string(), qty));
            }
            st.orders.insert(
                id.to_string(),
                Order {
                    status: Status::Placed,
                    lines,
                    total,
                },
            );
            out.push_str(&format!("ok {} total={}\n", id, money(total)));
        }
        "cancel" => {
            if n != 2 {
                return err("error: usage".into(), out);
            }
            let id = toks[1];
            let order = match st.orders.get_mut(id) {
                Some(o) => o,
                None => return err(format!("error: unknown order {}", id), out),
            };
            match order.status {
                Status::Placed => {
                    for (sku, qty) in &order.lines {
                        if let Some(s) = st.skus.get_mut(sku) {
                            s.stock += qty;
                        }
                    }
                    order.status = Status::Cancelled;
                    out.push_str("ok\n");
                }
                Status::Shipped => err(format!("error: order {} already shipped", id), out),
                Status::Cancelled => err(format!("error: order {} already cancelled", id), out),
            }
        }
        "ship" => {
            if n != 2 {
                return err("error: usage".into(), out);
            }
            let id = toks[1];
            let order = match st.orders.get_mut(id) {
                Some(o) => o,
                None => return err(format!("error: unknown order {}", id), out),
            };
            match order.status {
                Status::Placed => {
                    order.status = Status::Shipped;
                    out.push_str("ok\n");
                }
                Status::Shipped => err(format!("error: order {} already shipped", id), out),
                Status::Cancelled => err(format!("error: order {} is cancelled", id), out),
            }
        }
        "report" => {
            if n != 1 {
                return err("error: usage".into(), out);
            }
            let mut reserved: HashMap<&str, i128> = HashMap::new();
            let (mut placed, mut shipped, mut cancelled) = (0u64, 0u64, 0u64);
            let mut revenue = 0i128;
            for o in st.orders.values() {
                match o.status {
                    Status::Placed => {
                        placed += 1;
                        for (sku, qty) in &o.lines {
                            *reserved.entry(sku.as_str()).or_insert(0) += qty;
                        }
                    }
                    Status::Shipped => {
                        shipped += 1;
                        revenue += o.total;
                    }
                    Status::Cancelled => cancelled += 1,
                }
            }
            for (sku, s) in &st.skus {
                let r = reserved.get(sku.as_str()).copied().unwrap_or(0);
                out.push_str(&format!(
                    "{} stock={} price={} reserved={}\n",
                    sku,
                    s.stock,
                    money(s.price),
                    r
                ));
            }
            out.push_str(&format!(
                "orders placed={} shipped={} cancelled={}\n",
                placed, shipped, cancelled
            ));
            out.push_str(&format!("revenue={}\n", money(revenue)));
        }
        _ => err("error: unknown command".into(), out),
    }
}

fn main() {
    let mut raw = Vec::new();
    io::stdin().read_to_end(&mut raw).expect("read stdin");
    let input = String::from_utf8_lossy(&raw);

    let mut st = State::default();
    let mut out = String::new();
    for line in input.split('\n') {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.bytes().all(|b| b == b' ') {
            continue;
        }
        let toks: Vec<&str> = line.split(' ').collect();
        handle(&mut st, &toks, &mut out);
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(out.as_bytes()).expect("write stdout");
    lock.flush().expect("flush stdout");
}
