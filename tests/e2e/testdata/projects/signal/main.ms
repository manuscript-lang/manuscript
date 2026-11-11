import (
	Closeable from "@std/core.ms",
	WriteStream, stdout from "@std/io/io.ms",
)

type Resource:
	label: String
	output: WriteStream[String]

impl Closeable for Resource:
	var fn close() Unit!:
		_ignored := self.output.write("close {self.label}\n")

fn main() Unit:
	var output = stdout()
	var _resource = Resource("parent", stdout())
	_child := Resource("child", stdout())
	_ignored := output.write("ready\n")
	while true:
		continue
	_resource.close().get(none)
