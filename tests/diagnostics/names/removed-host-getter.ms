// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	host := filesystem()
	return host.read_file("a.txt").length()
}
// expect-error: MS2001 4:13 unknown binding filesystem; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
