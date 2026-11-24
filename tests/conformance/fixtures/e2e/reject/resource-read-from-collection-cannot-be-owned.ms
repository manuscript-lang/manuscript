// conform: tags=scope-cleanup,tier-core
// conform: phase=check
// A value read out of a list or map with `get` stays in the collection. Returning it or
// storing it in another owner would make a second owner: a resource would close twice
// and a plain value needs `.clone()`. Read it in place instead.
import panic from "@std/core.ms"

type Handle:
	id Int

fn move Handle.close() Void!:
	print("closed")

type Holder:
	handle Handle

fn returned(handles List[Handle], i Int) Handle?:
	return handles.get(i)

fn from_map(handles Map[Int, Handle], key Int) Handle?:
	return handles.get(key)

export fn main() Int:
	handles := [Handle(1), Handle(2)]
	var moved = List[Handle]()
	moved.append(handles.get(0))

	holder := Holder(handles.get(1))
	var last = List[Handle]()
	last.append(handles.last() or panic("called Optional.get() on null"))
	return (
		holder.handle.id
		+ moved.length()
		+ (returned(handles, 0) or panic("called Optional.get() on null")).id
		+ (
			from_map(Map[Int, Handle](), 0)
			or panic("called Optional.get() on null")
		).id
	)

// A plain value read with `get` is rejected the same way; `.clone()` gives the new
// owner a copy.
fn copied(names List[String]) List[String]:
	var out = List[String]()
	out.append(names.get(0))
	return out
