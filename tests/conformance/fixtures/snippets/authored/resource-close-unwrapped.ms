// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// conform: origin=a resource unwrapped or passed through a call closes at scope end
import Closeable from "@std/core.ms"

type Res:
	name String

fn move Res.close() Void!:
	print(f"close {self.name}")

fn make(move name String) Res!Error:
	return ok(Res(name))

fn keep(r Res) Res:
	return r

fn via_try() Void!Error:
	r := make("try")?
	print(f"body {r.name}")

fn via_get() Void:
	r := make("get").get()
	print(f"body {r.name}")

fn via_optional() Void:
	o Res? := Res("optional")
	r := o
	if r != null:
		print(f"body {r.name}")

fn via_passthrough() Void:
	r := keep(Res("keep"))
	print(f"body {r.name}")

fn main() Void:
	void via_try()
	via_get()
	via_optional()
	via_passthrough()
