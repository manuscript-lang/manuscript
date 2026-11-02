use std::collections::BTreeMap;
use std::io::{self, Read, Write};

const OVERDRAFT_FEE: i64 = 5;

struct Acct {
    balance: i64,
    limit: i64,
    ops: u64,
    rejected: u64,
    frozen: bool,
}

#[derive(Default)]
struct Ledger {
    accts: BTreeMap<String, Acct>,
    fees: i64,
}

/// Failure: the full error line, plus the account id to blame (if any).
type Failure = (String, Option<String>);
type Res = Result<String, Failure>;

fn fail(msg: String, blame: Option<&str>) -> Res {
    Err((msg, blame.map(|s| s.to_string())))
}

fn valid_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

fn parse_limit(s: &str) -> Option<i64> {
    if !valid_digits(s) {
        return None;
    }
    s.parse::<i64>().ok()
}

fn parse_amount(s: &str) -> Option<i64> {
    let v = parse_limit(s)?;
    if v > 0 {
        Some(v)
    } else {
        None
    }
}

/// Returns (new balance, whether a fee was charged) for debiting `amount`.
fn debit(balance: i64, amount: i64) -> (i64, bool) {
    let mut new = balance - amount;
    let fee = balance >= 0 && new < 0;
    if fee {
        new -= OVERDRAFT_FEE;
    }
    (new, fee)
}

impl Ledger {
    /// Checks that `id` exists and is not frozen (steps 1 and 4 for a single account).
    fn check_exists(&self, id: &str) -> Result<(), Failure> {
        if self.accts.contains_key(id) {
            Ok(())
        } else {
            Err((format!("error: unknown account {}", id), None))
        }
    }

    fn check_not_frozen(&self, id: &str) -> Result<(), Failure> {
        match self.accts.get(id) {
            Some(a) if a.frozen => Err((format!("error: account frozen {}", id), Some(id.to_string()))),
            _ => Ok(()),
        }
    }

    fn open(&mut self, id: &str, limit: &str) -> Res {
        let limit = parse_limit(limit).ok_or_else(|| ("error: invalid limit".to_string(), None))?;
        if self.accts.contains_key(id) {
            return Err((format!("error: account exists {}", id), None));
        }
        self.accts.insert(
            id.to_string(),
            Acct {
                balance: 0,
                limit,
                ops: 0,
                rejected: 0,
                frozen: false,
            },
        );
        Ok("ok".to_string())
    }

    fn set_frozen(&mut self, id: &str, frozen: bool) -> Res {
        match self.accts.get_mut(id) {
            Some(a) => {
                a.frozen = frozen;
                Ok("ok".to_string())
            }
            None => Err((format!("error: unknown account {}", id), None)),
        }
    }

    fn deposit(&mut self, id: &str, amount: &str) -> Res {
        self.check_exists(id)?;
        let amount = parse_amount(amount).ok_or_else(|| {
            ("error: invalid amount".to_string(), Some(id.to_string()))
        })?;
        self.check_not_frozen(id)?;
        let a = self.accts.get_mut(id).unwrap();
        a.balance += amount;
        a.ops += 1;
        Ok(format!("ok {}", a.balance))
    }

    fn withdraw(&mut self, id: &str, amount: &str) -> Res {
        self.check_exists(id)?;
        let amount = parse_amount(amount).ok_or_else(|| {
            ("error: invalid amount".to_string(), Some(id.to_string()))
        })?;
        self.check_not_frozen(id)?;
        let a = self.accts.get(id).unwrap();
        let (new, fee) = debit(a.balance, amount);
        if new < -a.limit {
            return fail(format!("error: overdraft limit exceeded {}", id), Some(id));
        }
        let a = self.accts.get_mut(id).unwrap();
        a.balance = new;
        a.ops += 1;
        if fee {
            self.fees += OVERDRAFT_FEE;
            Ok(format!("ok {} fee={}", new, OVERDRAFT_FEE))
        } else {
            Ok(format!("ok {}", new))
        }
    }

    fn transfer(&mut self, from: &str, to: &str, amount: &str) -> Res {
        self.check_exists(from)?;
        self.check_exists(to)?;
        if from == to {
            return fail("error: same account".to_string(), Some(from));
        }
        let amount = parse_amount(amount).ok_or_else(|| {
            ("error: invalid amount".to_string(), Some(from.to_string()))
        })?;
        self.check_not_frozen(from)?;
        self.check_not_frozen(to)?;
        let f = self.accts.get(from).unwrap();
        let (new_from, fee) = debit(f.balance, amount);
        if new_from < -f.limit {
            return fail(format!("error: overdraft limit exceeded {}", from), Some(from));
        }
        {
            let f = self.accts.get_mut(from).unwrap();
            f.balance = new_from;
            f.ops += 1;
        }
        let t = self.accts.get_mut(to).unwrap();
        t.balance += amount;
        t.ops += 1;
        let new_to = t.balance;
        if fee {
            self.fees += OVERDRAFT_FEE;
            Ok(format!("ok {} {} fee={}", new_from, new_to, OVERDRAFT_FEE))
        } else {
            Ok(format!("ok {} {}", new_from, new_to))
        }
    }

    fn report(&self, out: &mut String) {
        let mut total: i64 = 0;
        for (id, a) in &self.accts {
            total += a.balance;
            out.push_str(&format!(
                "{} balance={} limit={} ops={} rejected={} frozen={}\n",
                id,
                a.balance,
                a.limit,
                a.ops,
                a.rejected,
                if a.frozen { "yes" } else { "no" }
            ));
        }
        out.push_str(&format!("total balance={} fees={}\n", total, self.fees));
    }

    fn blame(&mut self, id: &str) {
        if let Some(a) = self.accts.get_mut(id) {
            a.rejected += 1;
        }
    }

    fn execute(&mut self, toks: &[&str], out: &mut String) {
        let res: Res = match (toks[0], toks.len()) {
            ("report", 1) => {
                self.report(out);
                return;
            }
            ("open", 3) => self.open(toks[1], toks[2]),
            ("freeze", 2) => self.set_frozen(toks[1], true),
            ("unfreeze", 2) => self.set_frozen(toks[1], false),
            ("deposit", 3) => self.deposit(toks[1], toks[2]),
            ("withdraw", 3) => self.withdraw(toks[1], toks[2]),
            ("transfer", 4) => self.transfer(toks[1], toks[2], toks[3]),
            _ => Err(("error: bad command".to_string(), None)),
        };
        match res {
            Ok(line) => {
                out.push_str(&line);
                out.push('\n');
            }
            Err((msg, blamed)) => {
                if let Some(id) = blamed {
                    self.blame(&id);
                }
                out.push_str(&msg);
                out.push('\n');
            }
        }
    }
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).expect("read stdin");
    let text = String::from_utf8_lossy(&input);

    let mut ledger = Ledger::default();
    let mut out = String::new();
    for line in text.lines() {
        let toks: Vec<&str> = line
            .split(|c| c == ' ' || c == '\t' || c == '\r')
            .filter(|s| !s.is_empty())
            .collect();
        if toks.is_empty() {
            continue;
        }
        ledger.execute(&toks, &mut out);
    }

    let stdout = io::stdout();
    let mut lock = stdout.lock();
    lock.write_all(out.as_bytes()).expect("write stdout");
    lock.flush().expect("flush stdout");
}
