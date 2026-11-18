// conform: tags=interfaces,scope-cleanup,tier-core
// conform: phase=run
// A `move` parameter of a function type or interface operation is handed over at run time:
// a lambda, a named function and an implementation each own the resource they receive, close
// it when they only read it, and keep it when they move it on. Nothing is copied.
import Closeable, print from "@std/core.ms"

type Door:
	id: Int

fn var Door.close() Void!:
	print(f"close {self.id}")

interface Taker:
	var fn take(move door: Door) Int

type Counter:
	seen: Int

// Only reads the door: it owns it, so it closes it at its end.
fn var Counter.take(move door: Door) Int:
	self.seen = self.seen + door.id
	return self.seen

fn apply(f: fn(move Door) Int, move door: Door) Int:
	return f(door)

fn give(var t: Taker, move door: Door) Int:
	return t.take(door)

fn read(door: Door) Int:
	return door.id

fn keep(move door: Door) Int:
	var doors = [door]
	return doors.length()

fn main() Void:
	var kept: List[Door] = []
	print(f"lambda reads {apply(fn move d: d.id, Door(1))}")
	stored := apply(fn move d:
		kept.append(d)
		return kept.length()
	, Door(2))
	print(f"lambda keeps {stored}")
	print(f"reader {apply(read, Door(3))}")
	print(f"named keeps {apply(keep, Door(4))}")
	maybe: Door? := Door(5)
	print(f"map {maybe.map(fn d: d.id * 10).get_or(0)}")
	var t: Taker = Counter(0)
	print(f"interface {give(var t, Door(6))}")
	print(f"kept {kept.length()}")
