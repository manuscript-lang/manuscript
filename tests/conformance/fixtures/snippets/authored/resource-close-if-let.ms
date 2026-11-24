// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// conform: origin=an if let payload resource closes when its branch ends
import (
	Closeable from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

fn say(s String) Void:
	stdout().write(s + "\n").get()

type Res:
	name String

fn move Res.close() Void!:
	say(f"close {self.name}")

fn maybe(name String, present Bool) Res?:
	return if present: Res(name.clone()) else: null

fn make(name String) Res!Error:
	return ok(Res(name.clone()))

fn keep(r Res) Res:
	return r

fn early_return() Int:
	r := maybe("early", true)

	if r != null:
		if r.name.length() > 1: return 1

		say("not here")

	return 0

fn local_optional() Void:
	o := maybe("local", true)
	r := o
	if r != null:
		say(f"body {r.name}")
	say("after local")

fn absent() Void:
	r := maybe("absent", false)

	if r != null:
		say(f"body {r.name}")
	else:
		say("else branch")

fn moved_on() Res:
	r := maybe("moved", true)
	if r != null: return keep(r)

	return Res("fallback")

fn with_else_err() Void:
	if r := make("ok-result"):
		say(f"body {r.name}")

fn var_payload() Void:
	if var r = maybe("var", true):
		r = Res("var-reassigned")
		say(f"body {r.name}")

fn main() Void:
	early_return()
	local_optional()
	absent()

	m := moved_on()
	say(f"moved_on got {m.name}")
	with_else_err()
	var_payload()
	say("end")
