import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Ledger:
	bal: Map[String, Int] = Map[String, Int]()
	lim: Map[String, Int] = Map[String, Int]()
	ops: Map[String, Int] = Map[String, Int]()
	rej: Map[String, Int] = Map[String, Int]()
	frz: Map[String, Int] = Map[String, Int]()
	fees: Int = 0

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not (c >= "0" and c <= "9"): return false
	return true

fn amount(s: String) Int:
	if not digits(s): return -1
	v := s.parse_int().get(-1)
	if v <= 0: return -1
	return v

fn var Ledger.blame(id: String) Unit:
	self.rej[id.clone()] = self.rej.get_or(id, 0) + 1

fn var Ledger.bump(id: String) Unit:
	self.ops[id.clone()] = self.ops.get_or(id, 0) + 1

fn Ledger.has(id: String) Bool: self.bal.get(id).is_some()

fn Ledger.frozen(id: String) Bool: self.frz.get_or(id, 0) == 1

// returns fee charged (0/5) or -1 on limit exceeded
fn Ledger.debit_fee(id: String, amt: Int) Int:
	b := self.bal.get_or(id, 0)
	n := b - amt
	fee := if b >= 0 and n < 0: 5 else: 0
	if n - fee < 0 - self.lim.get_or(id, 0): return -1
	return fee

fn var Ledger.exec(t: List[String]) String:
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "open" and n == 3:
		if not digits(t[2]): return "error: invalid limit"
		if self.has(t[1]): return "error: account exists {t[1]}"
		self.bal[t[1].clone()] = 0
		self.lim[t[1].clone()] = t[2].parse_int().get(0)
		return "ok"
	if (cmd == "freeze" or cmd == "unfreeze") and n == 2:
		if not self.has(t[1]): return "error: unknown account {t[1]}"
		self.frz[t[1].clone()] = if cmd == "freeze": 1 else: 0
		return "ok"
	if (cmd == "deposit" or cmd == "withdraw") and n == 3:
		id := t[1]
		if not self.has(id): return "error: unknown account {id}"
		a := amount(t[2])
		if a < 0:
			self.blame(id)
			return "error: invalid amount"
		if self.frozen(id):
			self.blame(id)
			return "error: account frozen {id}"
		if cmd == "deposit":
			nb := self.bal.get_or(id, 0) + a
			self.bal[id.clone()] = nb
			self.bump(id)
			return "ok {nb}"
		fee := self.debit_fee(id, a)
		if fee < 0:
			self.blame(id)
			return "error: overdraft limit exceeded {id}"
		nb := self.bal.get_or(id, 0) - a - fee
		self.bal[id.clone()] = nb
		self.fees += fee
		self.bump(id)
		return if fee > 0: "ok {nb} fee=5" else: "ok {nb}"
	if cmd == "transfer" and n == 4:
		f := t[1]
		to := t[2]
		if not self.has(f): return "error: unknown account {f}"
		if not self.has(to): return "error: unknown account {to}"
		if f == to:
			self.blame(f)
			return "error: same account"
		a := amount(t[3])
		if a < 0:
			self.blame(f)
			return "error: invalid amount"
		if self.frozen(f):
			self.blame(f)
			return "error: account frozen {f}"
		if self.frozen(to):
			self.blame(to)
			return "error: account frozen {to}"
		fee := self.debit_fee(f, a)
		if fee < 0:
			self.blame(f)
			return "error: overdraft limit exceeded {f}"
		nf := self.bal.get_or(f, 0) - a - fee
		nt := self.bal.get_or(to, 0) + a
		self.bal[f.clone()] = nf
		self.bal[to.clone()] = nt
		self.fees += fee
		self.bump(f)
		self.bump(to)
		return if fee > 0: "ok {nf} {nt} fee=5" else: "ok {nf} {nt}"
	if cmd == "report" and n == 1:
		ids := self.bal.keys().sorted()
		var out = List[String]()
		var total = 0
		for id in ids:
			b := self.bal.get_or(id, 0)
			total += b
			fz := if self.frozen(id): "yes" else: "no"
			out.append("{id} balance={b} limit={self.lim.get_or(id, 0)} ops={self.ops.get_or(id, 0)} rejected={self.rej.get_or(id, 0)} frozen={fz}")
		out.append("total balance={total} fees={self.fees}")
		return out.join("\n")
	return "error: bad command"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var led = Ledger()
	for line in lines(stdin()):
		t := line.fields()
		if t.length() == 0: continue
		print(led.exec(t))
