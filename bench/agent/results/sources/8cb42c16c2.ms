import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Ledger:
	bal: Map[String, Int] = Map[String, Int]()
	lim: Map[String, Int] = Map[String, Int]()
	ops: Map[String, Int] = Map[String, Int]()
	rej: Map[String, Int] = Map[String, Int]()
	frz: Map[String, Bool] = Map[String, Bool]()
	fees: Int = 0

// Returns -1 when not all digits (or empty).
fn parse_digits(s: String) Int:
	cs := s.chars()
	if cs.length() == 0: return -1
	var v = 0
	for c in cs:
		if c < "0" or c > "9": return -1
		d := c.parse_int().get(-1)
		if d < 0: return -1
		v = v * 10 + d
	return v

fn Ledger.has(id: String) Bool: self.bal.get(id).is_some()

fn var Ledger.blame(id: String) Unit:
	self.rej[id.clone()] = self.rej.get_or(id, 0) + 1

fn var Ledger.bump(id: String) Unit:
	self.ops[id.clone()] = self.ops.get_or(id, 0) + 1

// Computes the fee/new balance for debit; returns new balance or fails (fee out param via Optional).
fn Ledger.debit_new(id: String, amount: Int) Int:
	b := self.bal.get_or(id, 0)
	var nb = b - amount
	if b >= 0 and nb < 0: nb -= 5
	return nb

fn Ledger.fee_for(id: String, amount: Int) Bool:
	b := self.bal.get_or(id, 0)
	return b >= 0 and b - amount < 0

fn fee_s(fee: Bool) String: if fee: " fee=5" else: ""

fn var Ledger.exec(toks: List[String]) List[String]:
	var out = List[String]()
	n := toks.length()
	cmd := toks.get(0, "")
	if cmd == "open" and n == 3:
		id := toks.get(1, "")
		l := parse_digits(toks.get(2, ""))
		if l < 0:
			out.append("error: invalid limit")
		else if self.has(id):
			out.append("error: account exists {id}")
		else:
			self.bal[id.clone()] = 0
			self.lim[id.clone()] = l
			self.frz[id.clone()] = false
			out.append("ok")
	else if (cmd == "freeze" or cmd == "unfreeze") and n == 2:
		id := toks.get(1, "")
		if not self.has(id):
			out.append("error: unknown account {id}")
		else:
			self.frz[id.clone()] = cmd == "freeze"
			out.append("ok")
	else if (cmd == "deposit" or cmd == "withdraw") and n == 3:
		id := toks.get(1, "")
		if not self.has(id):
			out.append("error: unknown account {id}")
			return out
		a := parse_digits(toks.get(2, ""))
		if a <= 0:
			self.blame(id.clone())
			out.append("error: invalid amount")
			return out
		if self.frz.get_or(id, false):
			self.blame(id.clone())
			out.append("error: account frozen {id}")
			return out
		if cmd == "deposit":
			nb := self.bal.get_or(id, 0) + a
			self.bal[id.clone()] = nb
			self.bump(id.clone())
			out.append("ok {nb}")
		else:
			fee := self.fee_for(id, a)
			nb := self.debit_new(id, a)
			if nb < 0 - self.lim.get_or(id, 0):
				self.blame(id.clone())
				out.append("error: overdraft limit exceeded {id}")
				return out
			if fee: self.fees += 5
			self.bal[id.clone()] = nb
			self.bump(id.clone())
			out.append("ok {nb}{fee_s(fee)}")
	else if cmd == "transfer" and n == 4:
		f := toks.get(1, "")
		t := toks.get(2, "")
		if not self.has(f):
			out.append("error: unknown account {f}")
			return out
		if not self.has(t):
			out.append("error: unknown account {t}")
			return out
		if f == t:
			self.blame(f.clone())
			out.append("error: same account")
			return out
		a := parse_digits(toks.get(3, ""))
		if a <= 0:
			self.blame(f.clone())
			out.append("error: invalid amount")
			return out
		if self.frz.get_or(f, false):
			self.blame(f.clone())
			out.append("error: account frozen {f}")
			return out
		if self.frz.get_or(t, false):
			self.blame(t.clone())
			out.append("error: account frozen {t}")
			return out
		fee := self.fee_for(f, a)
		nb := self.debit_new(f, a)
		if nb < 0 - self.lim.get_or(f, 0):
			self.blame(f.clone())
			out.append("error: overdraft limit exceeded {f}")
			return out
		if fee: self.fees += 5
		nt := self.bal.get_or(t, 0) + a
		self.bal[f.clone()] = nb
		self.bal[t.clone()] = nt
		self.bump(f.clone())
		self.bump(t.clone())
		out.append("ok {nb} {nt}{fee_s(fee)}")
	else if cmd == "report" and n == 1:
		var ids = List[String]()
		var total = 0
		for e in self.bal.entries():
			ids.append(e.key.clone())
			total += e.value
		ids.sort()
		for id in ids:
			fz := if self.frz.get_or(id, false): "yes" else: "no"
			out.append("{id} balance={self.bal.get_or(id, 0)} limit={self.lim.get_or(id, 0)} ops={self.ops.get_or(id, 0)} rejected={self.rej.get_or(id, 0)} frozen={fz}")
		out.append("total balance={total} fees={self.fees}")
	else:
		out.append("error: bad command")
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var led = Ledger()
	for line in lines(stdin()):
		toks := line.fields()
		if toks.length() == 0: continue
		for o in led.exec(toks):
			print(o)
