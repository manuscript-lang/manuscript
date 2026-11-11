// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
import (
	stdin, stdout from "@std/io/io.ms",
	lines from "@std/io/streams.ms",
)

type Acct:
	limit: Int
	balance: Int
	ops: Int
	rejected: Int
	frozen: Bool

type Ledger:
	ids: List[String]
	accts: Map[String, Acct]
	fees: Int

// Splits a line into tokens separated by runs of spaces or tabs.
fn tokens(line: String) List[String]:
	var out = List[String]()
	for piece in line.split("\t"):
		for t in piece.split(" "):
			if not t.is_empty(): out.append(t.clone())
	return out

// Non-empty string of ASCII digits.
fn is_digits(s: String) Bool:
	if s.is_empty(): return false

	for c in s.scalar_values():
		if c < 48 or c > 57: return false
	return true

fn value_of(s: String) Int:
	var v = 0
	for c in s.scalar_values():
		v = v * 10 + (c - 48)
	return v

fn valid_amount(s: String) Bool:
	return is_digits(s) and value_of(s) > 0

fn is_frozen(led: Ledger, id: String) Bool:
	if a := led.accts.get(id): return a.frozen
	return false

fn bal(led: Ledger, id: String) Int:
	if a := led.accts.get(id): return a.balance
	return 0

fn bump_ops(var led: Ledger, id: String) Unit:
	if var a = led.accts.get(id):
		a.ops += 1

// Records a rejection against `who` and returns the error message.
fn reject(var led: Ledger, who: String, msg: String) String:
	if var a = led.accts.get(who):
		a.rejected += 1
	return msg

// Applies a debit (withdraw / transfer FROM side). Returns -1 on overdraft
// failure (nothing changes), otherwise the fee charged (0 or 5).
fn take(var led: Ledger, id: String, amount: Int) Int:
	var fee = 0
	var done = false

	if var a = led.accts.get(id):
		var new_bal = a.balance - amount

		if a.balance >= 0 and new_bal < 0:
			fee = 5
			new_bal -= 5

		if new_bal >= 0 - a.limit:
			a.balance = new_bal
			done = true

	if not done: return -1

	led.fees += fee
	return fee

fn cmd_open(var led: Ledger, toks: List[String]) String:
	id := toks[1]
	lim := toks[2]
	if not is_digits(lim): return "error: invalid limit"
	if led.accts.contains(id): return "error: account exists {id}"

	led.ids.append(id.clone())
	led.accts.add(
		id.clone(),
		Acct(
			limit: value_of(lim),
			balance: 0,
			ops: 0,
			rejected: 0,
			frozen: false,
		),
	)
	return "ok"

fn cmd_freeze(var led: Ledger, id: String, flag: Bool) String:
	if not led.accts.contains(id): return "error: unknown account {id}"

	if var a = led.accts.get(id):
		a.frozen = flag
	return "ok"

fn cmd_deposit(var led: Ledger, toks: List[String]) String:
	id := toks[1]
	if not led.accts.contains(id): return "error: unknown account {id}"
	if not valid_amount(toks[2]): return reject(var led, id, "error: invalid amount")
	if is_frozen(led, id): return reject(var led, id, "error: account frozen {id}")

	amt := value_of(toks[2])

	if var a = led.accts.get(id):
		a.balance += amt
		a.ops += 1

	return "ok {bal(led, id)}"

fn cmd_withdraw(var led: Ledger, toks: List[String]) String:
	id := toks[1]
	if not led.accts.contains(id): return "error: unknown account {id}"
	if not valid_amount(toks[2]): return reject(var led, id, "error: invalid amount")
	if is_frozen(led, id): return reject(var led, id, "error: account frozen {id}")

	fee := take(var led, id, value_of(toks[2]))
	if fee < 0: return reject(var led, id, "error: overdraft limit exceeded {id}")

	bump_ops(var led, id)
	if fee > 0: return "ok {bal(led, id)} fee={fee}"

	return "ok {bal(led, id)}"

fn cmd_transfer(var led: Ledger, toks: List[String]) String:
	from := toks[1]
	to := toks[2]
	if not led.accts.contains(from): return "error: unknown account {from}"
	if not led.accts.contains(to): return "error: unknown account {to}"
	if from == to: return reject(var led, from, "error: same account")
	if not valid_amount(toks[3]): return reject(var led, from, "error: invalid amount")
	if is_frozen(led, from): return reject(
		var led,
		from,
		"error: account frozen {from}",
	)
	if is_frozen(led, to): return reject(var led, to, "error: account frozen {to}")

	amt := value_of(toks[3])
	fee := take(var led, from, amt)
	if fee < 0: return reject(var led, from, "error: overdraft limit exceeded {from}")

	if var b = led.accts.get(to):
		b.balance += amt
	bump_ops(var led, from)
	bump_ops(var led, to)
	if fee > 0: return "ok {bal(led, from)} {bal(led, to)} fee={fee}"

	return "ok {bal(led, from)} {bal(led, to)}"

fn cmd_report(led: Ledger) String:
	var out = List[String]()
	var total = 0

	for id in led.ids.sorted():
		if a := led.accts.get(id):
			total += a.balance

			fz := if a.frozen: "yes" else: "no"
			out.append(
				"{id} balance={a.balance} limit={a.limit} ops={a.ops} rejected={a.rejected} frozen={fz}"
			)

	out.append("total balance={total} fees={led.fees}")
	return out.join("\n")

// Returns the output text for one command line (without trailing newline).
fn handle(var led: Ledger, toks: List[String]) String:
	cmd := toks[0]
	n := toks.length()

	if cmd == "open":
		if n != 3: return "error: bad command"
		return cmd_open(var led, toks)

	if cmd == "freeze":
		if n != 2: return "error: bad command"
		return cmd_freeze(var led, toks[1], true)

	if cmd == "unfreeze":
		if n != 2: return "error: bad command"
		return cmd_freeze(var led, toks[1], false)

	if cmd == "deposit":
		if n != 3: return "error: bad command"
		return cmd_deposit(var led, toks)

	if cmd == "withdraw":
		if n != 3: return "error: bad command"
		return cmd_withdraw(var led, toks)

	if cmd == "transfer":
		if n != 4: return "error: bad command"
		return cmd_transfer(var led, toks)

	if cmd == "report":
		if n != 1: return "error: bad command"
		return cmd_report(led)

	return "error: bad command"

fn run() Unit!:
	var led = Ledger(ids: List[String](), accts: Map[String, Acct](), fees: 0)

	for line in stdin() | lines:
		toks := tokens(line)
		if toks.is_empty(): continue

		text := handle(var led, toks)
		stdout().write("{text}\n").get()

export fn main() Int:
	run().get()
	return 0
