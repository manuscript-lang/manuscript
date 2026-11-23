// conform: tags=tier-stdlib
// conform: phase=run
// A resource field moves out of a record the callee owns: the new owner closes it, and
// the record closes the other fields (last declared first), on every path. A
// destructured temporary closes the parts it does not bind.
import stdout from "@std/io/io.ms"

type Door:
	name: String

fn move Door.close() Void!:
	stdout().write(f"close {self.name}\n").get()

type Room:
	first: Door
	second: Door

fn both(r: Room) List[Door]:
	var xs: List[Door] = []
	xs.append(r.second)
	return xs

fn branch(r: Room, flag: Bool) List[Door]:
	var xs: List[Door] = []
	if flag:
		xs.append(r.first)
	return xs

fn temporary() Void:
	{first: kept} := Room(Door("t1"), Door("t2"))
	void kept.name

fn main() Void:
	_a := both(Room(Door("a1"), Door("a2")))
	_b := branch(Room(Door("b1"), Door("b2")), true)
	_c := branch(Room(Door("c1"), Door("c2")), false)
	temporary()
