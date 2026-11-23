// conform: tags=interfaces,scope-cleanup,tier-core
// conform: phase=run
// A `move` parameter of a function type or interface operation is handed over at run
// time: a lambda, a named function, an implementation and a `move fn` receiver each own
// the resource they receive, close it when they only read it, and keep it when they
// move it on. Nothing is copied.
import Closeable, print from "@std/core.ms"

type Door:
	id: Int

fn move Door.close() Void!:
	print(f"close {self.id}")

interface Taker:
	var fn take(move door: Door) Int

type Counter:
	seen: Int

// Only reads the door: it owns it, so it closes it at its end.
fn var Counter.take(move door: Door) Int:
	self.seen += door.id
	return self.seen

interface Finisher:
	move fn close() Void!
	move fn finish() Int

// Takes the door out of the interface value and closes it at its end, once.
fn move Door.finish() Int:
	return self.id

fn finish(move f: Finisher) Int:
	return f.finish()

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

	stored := apply(
		fn move d:
			kept.append(d)
			return kept.length()
		,
		Door(2)
	)

	print(f"lambda keeps {stored}")
	print(f"reader {apply(read, Door(3))}")
	print(f"named keeps {apply(keep, Door(4))}")

	maybe: Door? := Door(5)
	if maybe != null: print(f"map {maybe.id * 10}")

	var t: Taker = Counter(0)
	print(f"interface {give(t, Door(6))}")
	print(f"finished {finish(Door(7))}")
	print(f"kept {kept.length()}")
