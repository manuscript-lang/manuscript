// conform: tags=match,scope-cleanup,tier-core
// conform: phase=run
// An arm that moves a resource payload out of a loop item owns it: the item is not closed again at the end of the
// round, so the stored writer is still open when the owner reads it later.
import forward from "@std/io/forward.ms"
import ReadStream, WriteStream, pipe from "@std/io/io.ms"

enum Command:
	Join(out WriteStream[Int])
	Say(text String)

fn owner(var inbox ReadStream[Command]) Void!:
	var members List[WriteStream[Int]] = []

	for command in inbox:
		match command:
			Command.Join(out):
				members.append(out)
			Command.Say(text):
				print(text)

	print(members.length())
	members[0].write(7)?
	return ok()

fn main() Void!:
	var commands = pipe[Command](4)
	var inbox = commands.reader()
	var outbox = commands.writer()
	var sink = pipe[Int](4)
	var heard = sink.reader()
	outbox.write(Command.Join(forward(sink.writer())))?
	outbox.write(Command.Say("hi"))?
	outbox.close()?
	owner(inbox)?
	print(heard.next()?)
	return ok()
