// conform: tags=control-flow,formatter,interfaces,interpolation,modules,parser,records,stdlib-cleanup,stdlib-io,strings,tier-stdlib,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/projects/signal/main.ms
import (
	Closeable from "@std/core.ms",
	WriteStream, stdout from "@std/io/io.ms",
)

type Resource {
	label String
	output WriteStream
}

fn Resource.close() Void! {
	_ignored := self.output.write(f"close {self.label}\n")
}

fn main() Void {
	output := stdout()
	var _resource = Resource("parent", output)
	_child := Resource("child", output)
	_ignored := output.write("ready\n")
	while true {
		continue
	}
	_resource.close()
}
// expect-format: unchanged
