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
		if c < "0" or c > "9": return false
	return true

fn parse_amount(s: String) Int:
	if not digits(s): return 0
	return s.parse_int().get(0)

fn var Ledger.blame(id: String) Unit:
	self.rej[id.clone()] = self.rej.get_or(id, 0) + 1

fn var Ledger.bump(id: String) Unit:
	self.ops[id.clone()] = self.ops.get_or(id, 0) + 1

fn var Ledger.move(kind: String, a: String, b: String, amt_s: String) String:
	two := kind == "transfer"
	if not self.bal.contains(a): return "error: unknown account {a}"
	if two and not self.bal.contains(b): return "error: unknown account {b}"
	if two and a == b:
		self.blame(a)
		return "error: same account"
	amount := parse_amount(amt_s)
	if amount <= 0:
		self.blame(a)
		return "error: invalid amount"
	if self.frz.get_or(a, 0) == 1:
		self.blame(a)
		return "error: account frozen {a}"
	if two and self.frz.get_or(b, 0) == 1:
		self.blame(b)
		return "error: account frozen {b}"
	balance := self.bal.get_or(a, 0)
	if kind == "deposit":
		nb := balance + amount
		self.bal[a.clone()] = nb
		self.bump(a)
		return "ok {nb}"
	var nb = balance - amount
	var fee = 0
	if balance >= 0 and nb < 0:
		nb -= 5
		fee = 5
	if nb < 0 - self.lim.get_or(a, 0):
		self.blame(a)
		return "error: overdraft limit exceeded {a}"
	self.bal[a.clone()] = nb
	self.fees += fee
	self.bump(a)
	suffix := if fee > 0: " fee=5" else: ""
	if not two: return "ok {nb}{suffix}"
	nt := self.bal.get_or(b, 0) + amount
	self.bal[b.clone()] = nt
	self.bump(b)
	return "ok {nb} {nt}{suffix}"

fn var Ledger.run(t: List[String]) List[String]:
	var out = List[String]()
	cmd := t.get(0, "")
	n := t.length()
	if cmd == "open" and n == 3:
		if not digits(t.get(2, "")):
			out.append("error: invalid limit")
		else if self.bal.contains(t.get(1, "")):
			out.append("error: account exists {t.get(1, "")}")
		else:
			id := t.get(1, "")
			self.bal[id.clone()] = 0
			self.lim[id.clone()] = t.get(2, "").parse_int().get(0)
			out.append("ok")
	else if (cmd == "freeze" or cmd == "unfreeze") and n == 2:
		id := t.get(1, "")
		if not self.bal.contains(id):
			out.append("error: unknown account {id}")
		else:
			self.frz[id.clone()] = if cmd == "freeze": 1 else: 0
			out.append("ok")
	else if (cmd == "deposit" or cmd == "withdraw") and n == 3:
		out.append(self.move(cmd, t.get(1, ""), "", t.get(2, "")))
	else if cmd == "transfer" and n == 4:
		out.append(self.move(cmd, t.get(1, ""), t.get(2, ""), t.get(3, "")))
	else if cmd == "report" and n == 1:
		var ids = self.bal.keys().sorted()
		var total = 0
		for id in ids:
			b := self.bal.get_or(id, 0)
			total += b
			fr := if self.frz.get_or(id, 0) == 1: "yes" else: "no"
			out.append("{id} balance={b} limit={self.lim.get_or(id, 0)} ops={self.ops.get_or(id, 0)} rejected={self.rej.get_or(id, 0)} frozen={fr}")
		out.append("total balance={total} fees={self.fees}")
	else:
		out.append("error: bad command")
	return out

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var led = Ledger()
	for line in lines(stdin()):
		t := line.fields()
		if t.length() == 0: continue
		for o in led.run(t):
			print(o)
