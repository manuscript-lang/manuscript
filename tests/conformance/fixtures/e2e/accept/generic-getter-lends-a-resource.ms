// conform: tags=testing,generics,scope-cleanup,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"


type Res:
	name String

fn move Res.close() Void!:
	return ok(void)

type Cell[T]:
	v T

fn Cell[T].get() T:
	return self.v

fn size(cell Cell[Res]) Int:
	return cell.get().name.length()

test "a generic getter lends a resource: the receiver stays the owner":
	cell := Cell(v: Res(name: "abc"))
	first := cell.get()
	expect_equal(first.name, "abc")?
	expect_equal(cell.get().name.length(), 3)?
	expect_equal(size(cell), 3)?

test "a getter over a resource can be called as a statement":
	cell := Cell(v: Res(name: "x"))
	cell.get()
	expect_equal(cell.v.name, "x")?
