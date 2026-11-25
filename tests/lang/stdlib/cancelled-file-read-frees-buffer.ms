// conform: tags=scope-cleanup,stdlib-fs,tier-io
// conform: phase=run
// A file read or write cancelled while it runs on the blocking pool unwinds out of its
// native: the job's buffer and text must be freed first, or every cancelled read leaks
// the file it had read (the leak check runs this fixture with the process-exit frees
// kept).
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	read_file, remove, temporary_directory, write_file from "@std/os/fs.ms",
	microseconds, sleep from "@std/time.ms",
)

fn read_many(path String) Void! {
	for i in 0..20 {
		void read_file(path).wait()?
	}
}

fn main() Void! {
	dir := temporary_directory("cancelled-read")?
	path := f"{dir}/big"
	void write_file(path, "q".repeat(8000000).to_bytes()).wait()?

	for round in 0..12 {
		stop := cancel_switch()
		target := path.clone()
		reading := promise(
			() => read_many(target),
			options: PromiseOptions(cancel: stop.signal()),
		)
		void sleep(microseconds(round * 500)).wait()?
		stop.cancel()
		void reading.wait()
	}

	void remove(dir, true)
	print("done")
}
