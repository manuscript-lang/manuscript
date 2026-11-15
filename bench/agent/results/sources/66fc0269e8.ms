import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Ledger:
	bal: Map[String, Int] = Map[String, Int]()
	lim: Map[String, Int] = Map[String, Int]()
	ops: Map[String, Int] = Map[String, Int]()
	rej: Map[String, Int] = Map[String, Int]()
	frz: Map[String, Int] = Map[String, Int]()
	fees: Int = 0

fn digits(s: String) Int?:
	if s.length() == 0: return none
	var v = 0
	for c in s.scalar_values():
		if c < 48 or c > 57: return none
		v = v * 10 + (c - 48)
	return v

fn amount(s: String) Int?:
	if v := digits(s):
		if v > 0: return v
	return none

fn var Ledger.blame(id: String) Unit:
	self.rej[id.clone()] = self.rej.get_or(id, 0) + 1

fn var Ledger.bump(id: String) Unit:
	self.ops[id.clone()] = self.ops.get_or(id, 0) + 1

fn Ledger.has(id: String) Bool: self.bal.contains(id)

fn Ledger.frozen(id: String) Bool: self.frz.get_or(id, 0) == 1

// returns error text or "" ; computes new balance and fee
fn Ledger.debit(id: String, amt: Int) Int:
	b := self.bal.get_or(id, 0)
	n := b - amt
	if b >= 0 and n < 0: return n - 5
	return n

fn Ledger.fee(id: String, amt: Int) Int:
	b := self.bal.get_or(id, 0)
	if b >= 0 and b - amt < 0: return 5
	return 0

fn var Ledger.move(kind: String, args: List[String]) String:
	if kind == "transfer":
		from := args.get(0, "")
		to := args.get(1, "")
		if not self.has(from): return "error: unknown account {from}"
		if not self.has(to): return "error: unknown account {to}"
		if from == to:
			self.blame(from)
			return "error: same account"
		a := amount(args.get(2, ""))
		if a.is_none():
			self.blame(from)
			return "error: invalid amount"
		amt := a.get(0)
		if self.frozen(from):
			self.blame(from)
			return "error: account frozen {from}"
		if self.frozen(to):
			self.blame(to)
			return "error: account frozen {to}"
		nf := self.debit(from, amt)
		if nf < 0 - self.lim.get_or(from, 0):
			self.blame(from)
			return "error: overdraft limit exceeded {from}"
		fee := self.fee(from, amt)
		self.fees += fee
		self.bal[from.clone()] = nf
		nt := self.bal.get_or(to, 0) + amt
		self.bal[to.clone()] = nt
		self.bump(from)
		self.bump(to)
		suffix := if fee > 0: " fee=5" else: ""
		return "ok {nf} {nt}{suffix}"
	id := args.get(0, "")
	if not self.has(id): return "error: unknown account {id}"
	a := amount(args.get(1, ""))
	if a.is_none():
		self.blame(id)
		return "error: invalid amount"
	amt := a.get(0)
	if self.frozen(id):
		self.blame(id)
		return "error: account frozen {id}"
	if kind == "deposit":
		nb := self.bal.get_or(id, 0) + amt
		self.bal[id.clone()] = nb
		self.bump(id)
		return "ok {nb}"
	nb := self.debit(id, amt)
	if nb < 0 - self.lim.get_or(id, 0):
		self.blame(id)
		return "error: overdraft limit exceeded {id}"
	fee := self.fee(id, amt)
	self.fees += fee
	self.bal[id.clone()] = nb
	self.bump(id)
	suffix := if fee > 0: " fee=5" else: ""
	return "ok {nb}{suffix}"

fn var Ledger.exec(t: List[String]) String:
	if t.length() == 0: return ""
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "open" and n == 3:
		l := digits(t.get(2, ""))
		if l.is_none(): return "error: invalid limit"
		id := t.get(1, "")
		if self.has(id): return "error: account exists {id}"
		self.bal[id.clone()] = 0
		self.lim[id.clone()] = l.get(0)
		return "ok"
	if (cmd == "freeze" or cmd == "unfreeze") and n == 2:
		id := t.get(1, "")
		if not self.has(id): return "error: unknown account {id}"
		self.frz[id.clone()] = if cmd == "freeze": 1 else: 0
		return "ok"
	if (cmd == "deposit" or cmd == "withdraw") and n == 3:
		return self.move(cmd, [t.get(1, ""), t.get(2, "")])
	if cmd == "transfer" and n == 4:
		return self.move(cmd, [t.get(1, ""), t.get(2, ""), t.get(3, "")])
	if cmd == "report" and n == 1:
		var ids = List[String]()
		var total = 0
		for e in self.bal.entries():
			ids.append(e.key.clone())
			total += e.value
		ids.sort()
		var out = ""
		for id in ids:
			f := if self.frozen(id): "yes" else: "no"
			out += "{id} balance={self.bal.get_or(id, 0)} limit={self.lim.get_or(id, 0)} ops={self.ops.get_or(id, 0)} rejected={self.rej.get_or(id, 0)} frozen={f}\n"
		out += "total balance={total} fees={self.fees}"
		return out
	return "error: bad command"

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var led = Ledger()
	for line in lines(stdin()):
		t := line.fields()
		if t.length() == 0: continue
		print(led.exec(t))
