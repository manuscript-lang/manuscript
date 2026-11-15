import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Account:
	id: String
	balance: Int = 0
	limit: Int = 0
	ops: Int = 0
	rejected: Int = 0
	frozen: Bool = false

type Ledger:
	accts: List[Account] = []
	index: Map[String, Int] = Map[String, Int]()
	fees: Int = 0

fn is_num(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

fn amount_of(s: String) Int:
	if not is_num(s): return 0
	t := s.trim_start_chars("0")
	if t.length() == 0: return 0
	return t.parse_int().get(0)

fn var Ledger.reject(i: Int) Unit:
	self.accts[i].rejected += 1

fn var Ledger.charge(i: Int, amount: Int) Int?:
	// returns fee or none on limit exceeded
	bal := self.accts[i].balance
	var new = bal - amount
	var fee = 0
	if bal >= 0 and new < 0:
		new -= 5
		fee = 5
	if new < 0 - self.accts[i].limit: return none
	return fee

fn var Ledger.exec(toks: List[String]) String:
	cmd := toks.get(0, "")
	n := toks.length()
	if cmd == "open":
		if n != 3: return "error: bad command"
		if not is_num(toks[2]): return "error: invalid limit"
		if self.index.contains(toks[1]): return "error: account exists {toks[1]}"
		self.index[toks[1].clone()] = self.accts.length()
		self.accts.append(Account(toks[1].clone(), limit: toks[2].trim_start_chars("0").parse_int().get(0)))
		return "ok"
	if cmd == "freeze" or cmd == "unfreeze":
		if n != 2: return "error: bad command"
		i := self.index.get(toks[1])
		if i.is_none(): return "error: unknown account {toks[1]}"
		self.accts[i.get(0)].frozen = cmd == "freeze"
		return "ok"
	if cmd == "report":
		if n != 1: return "error: bad command"
		var ids = List[String]()
		for a in self.accts: ids.append(a.id.clone())
		ids.sort()
		var out = List[String]()
		var total = 0
		for id in ids:
			a := self.accts[self.index.get_or(id, 0)]
			total += a.balance
			fz := if a.frozen: "yes" else: "no"
			out.append("{a.id} balance={a.balance} limit={a.limit} ops={a.ops} rejected={a.rejected} frozen={fz}")
		out.append("total balance={total} fees={self.fees}")
		return out.join("\n")
	if cmd == "deposit" or cmd == "withdraw":
		if n != 3: return "error: bad command"
		oi := self.index.get(toks[1])
		if oi.is_none(): return "error: unknown account {toks[1]}"
		i := oi.get(0)
		amt := amount_of(toks[2])
		if amt <= 0:
			self.reject(i)
			return "error: invalid amount"
		if self.accts[i].frozen:
			self.reject(i)
			return "error: account frozen {toks[1]}"
		var fee = 0
		if cmd == "withdraw":
			f := self.charge(i, amt)
			if f.is_none():
				self.reject(i)
				return "error: overdraft limit exceeded {toks[1]}"
			fee = f.get(0)
			self.accts[i].balance -= amt + fee
			self.fees += fee
		else:
			self.accts[i].balance += amt
		self.accts[i].ops += 1
		suffix := if fee > 0: " fee=5" else: ""
		return "ok {self.accts[i].balance}{suffix}"
	if cmd == "transfer":
		if n != 4: return "error: bad command"
		fo := self.index.get(toks[1])
		if fo.is_none(): return "error: unknown account {toks[1]}"
		to := self.index.get(toks[2])
		if to.is_none(): return "error: unknown account {toks[2]}"
		f := fo.get(0)
		t := to.get(0)
		if f == t:
			self.reject(f)
			return "error: same account"
		amt := amount_of(toks[3])
		if amt <= 0:
			self.reject(f)
			return "error: invalid amount"
		if self.accts[f].frozen:
			self.reject(f)
			return "error: account frozen {toks[1]}"
		if self.accts[t].frozen:
			self.reject(t)
			return "error: account frozen {toks[2]}"
		fee := self.charge(f, amt)
		if fee.is_none():
			self.reject(f)
			return "error: overdraft limit exceeded {toks[1]}"
		fv := fee.get(0)
		self.accts[f].balance -= amt + fv
		self.accts[t].balance += amt
		self.fees += fv
		self.accts[f].ops += 1
		self.accts[t].ops += 1
		suffix := if fv > 0: " fee=5" else: ""
		return "ok {self.accts[f].balance} {self.accts[t].balance}{suffix}"
	return "error: bad command"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var ledger = Ledger()
	for line in lines(stdin()):
		toks := line.fields()
		if toks.length() == 0: continue
		print(ledger.exec(toks))
