import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

type Ledger:
	idx: Map[String, Int] = Map[String, Int]()
	ids: List[String] = []
	bal: List[Int] = []
	lim: List[Int] = []
	ops: List[Int] = []
	rej: List[Int] = []
	frz: List[Bool] = []
	fees: Int = 0

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn amount(s: String) Int:
	if not digits(s): return -1
	v := s.parse_int().get(-1)
	if v <= 0: return -1
	return v

fn var Ledger.reject(i: Int, msg: String) String:
	self.rej[i] += 1
	return msg

fn var Ledger.handle(line: String) String:
	t := line.fields()
	n := t.length()
	cmd := t[0]
	if cmd == "open":
		if n != 3: return "error: bad command"
		if not digits(t[2]): return "error: invalid limit"
		lv := t[2].parse_int()
		if lv.is_none(): return "error: invalid limit"
		if self.idx.get(t[1]).is_some(): return "error: account exists {t[1]}"
		self.idx[t[1].clone()] = self.ids.length()
		self.ids.append(t[1].clone())
		self.bal.append(0)
		self.lim.append(lv.get(0))
		self.ops.append(0)
		self.rej.append(0)
		self.frz.append(false)
		return "ok"
	if cmd == "freeze" or cmd == "unfreeze":
		if n != 2: return "error: bad command"
		i := self.idx.get(t[1])
		if i.is_none(): return "error: unknown account {t[1]}"
		self.frz[i.get(0)] = cmd == "freeze"
		return "ok"
	if cmd == "report":
		if n != 1: return "error: bad command"
		order := self.ids.sorted()
		var out: List[String] = []
		var total = 0
		for id in order:
			i := self.idx.get(id).get(0)
			total += self.bal[i]
			fz := if self.frz[i]: "yes" else: "no"
			out.append("{id} balance={self.bal[i]} limit={self.lim[i]} ops={self.ops[i]} rejected={self.rej[i]} frozen={fz}")
		out.append("total balance={total} fees={self.fees}")
		return out.join("\n")
	is_t := cmd == "transfer"
	if cmd != "deposit" and cmd != "withdraw" and not is_t: return "error: bad command"
	if is_t:
		if n != 4: return "error: bad command"
	else:
		if n != 3: return "error: bad command"
	fi := self.idx.get(t[1])
	if fi.is_none(): return "error: unknown account {t[1]}"
	a := fi.get(0)
	var b = -1
	if is_t:
		ti := self.idx.get(t[2])
		if ti.is_none(): return "error: unknown account {t[2]}"
		b = ti.get(0)
		if a == b: return self.reject(a, "error: same account")
	amt := amount(t[n - 1])
	if amt < 0: return self.reject(a, "error: invalid amount")
	if self.frz[a]: return self.reject(a, "error: account frozen {t[1]}")
	if b >= 0 and self.frz[b]: return self.reject(b, "error: account frozen {t[2]}")
	var fee = 0
	var nb = self.bal[a]
	if cmd != "deposit":
		nb = self.bal[a] - amt
		if self.bal[a] >= 0 and nb < 0:
			nb -= 5
			fee = 5
		if nb < 0 - self.lim[a]: return self.reject(a, "error: overdraft limit exceeded {t[1]}")
	else:
		nb = self.bal[a] + amt
	self.bal[a] = nb
	self.ops[a] += 1
	self.fees += fee
	var res = "ok {nb}"
	if is_t:
		self.bal[b] += amt
		self.ops[b] += 1
		res = "ok {nb} {self.bal[b]}"
	if fee > 0: res = res + " fee=5"
	return res

fn main() Unit!:
	var l = Ledger()
	for line in lines(stdin()):
		if line.fields().length() == 0: continue
		print(l.handle(line))
