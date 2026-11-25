// conform: tags=diagnostics,modules,stdlib-fs,tier-io
// conform: phase=check
// conform: origin=pkg/build/filesystem_defaults_test.go:52 TestFilesystemExplicitFlagsKeepDirectDispatch
import CopyOptions, copy, create_directory, remove, write_file from "@std/os/fs.ms"

fn explicit() Void {
	void write_file("", "", false).wait()
	void copy("", "", CopyOptions(replace: true))
	void copy("", "", CopyOptions(recursive: true, max_bytes: 3))
	void create_directory("", true)
	void remove("", false)
}
// expect-exit: 0
