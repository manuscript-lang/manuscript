import (
	Closeable from "@std/core.ms",
	WriteStream, stdout from "@std/io/io.ms",
)

type Resource:
	label: String
	output: WriteStream[String]

fn var Resource.close() Void!:
	_ignored := self.output.write("close {self.label}\n")

fn main() Void:
	var output = stdout()
	var _resource = Resource("parent", stdout())
	_child := Resource("child", stdout())
	_ignored := output.write("ready\n")
	while true:
		continue
	_resource.close().get(none)
