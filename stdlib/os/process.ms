import (
	Bytes from "@std/bytes.ms",
	Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	DescriptorSink,
	DescriptorSource,
	ReadStream,
	Source,
	WriteStream from "@std/io/io.ms",
	Duration from "@std/time.ms",

	msstd_process_command_run,
	msstd_process_command_spawn,
	msstd_process_cpu_usage,
	msstd_process_groups,
	msstd_process_info,
	msstd_process_initialize_groups,
	msstd_process_replace,
	msstd_process_resource_usage,
	msstd_process_send_signal,
	msstd_process_set_groups,
	msstd_process_set_identity,
	msstd_process_set_title,
	msstd_process_signal_close,
	msstd_process_signal_next,
	msstd_process_subprocess_close,
	msstd_process_subprocess_kill,
	msstd_process_subprocess_max_resident,
	msstd_process_subprocess_stream_id,
	msstd_process_subprocess_terminate,
	msstd_process_subprocess_wait,
	msstd_process_title,
	msstd_process_umask,
	msstd_process_watch_signals,
	msstd_system_get_priority,
	msstd_system_set_priority from "@std/internal/process.ms",
)

// Captured exit status and standard output/error from a completed command.
export type CommandOutput:
	// The child's exit status; 0 conventionally means success. A nonzero status is
	// still an Ok result, and a child ended by a signal reports -1 on Unix.
	exit_code: Int
	// Everything the child wrote to standard output, as raw bytes that may not be valid
	// UTF-8.
	stdout: Bytes
	// Everything the child wrote to standard error, as raw bytes that may not be valid
	// UTF-8.
	stderr: Bytes
	// The child's peak resident set size in bytes, or 0 when the host cannot report it.
	max_resident_bytes: Int

// Where a child's standard input, output, or error goes, chosen per stream.
// `spawn("make", [], SpawnOptions(stdout: Stdio.Inherit, stderr: Stdio.Inherit))` lets the child's output reach the parent's terminal while stdin stays piped.
export enum Stdio:
	// An OS pipe to the parent, read or written through the Subprocess's stream.
	Pipe
	Inherit  // The parent's own stream, so the child reads or writes it directly.
	Null  // The null device: input is at end of file, output is discarded.

// Settings for `run`. Every field has a default, so `RunOptions()` runs the program
// with no input, no output cap, no deadline, the caller's directory and the inherited
// environment.
export type RunOptions:
	// Bytes written to the child's standard input.
	input: Bytes = "".to_bytes()
	// Largest total output of both streams in bytes; none sets no cap. More returns
	// EOVERFLOW.
	max_output_bytes: Int?
	// How long the child may run; none waits without limit. Expiry returns ETIMEDOUT.
	timeout: Duration?
	// The child's working directory; none inherits the caller's.
	cwd: String?
	// Variables added to or replaced in the inherited environment.
	env: Map[String, String] = Map[String, String]()

// Settings for `spawn`. Every field has a default, so `SpawnOptions()` pipes all three
// streams, inherits the caller's directory and environment.
export type SpawnOptions:
	// Where the child reads standard input.
	stdin: Stdio = Stdio.Pipe
	// Where the child writes standard output.
	stdout: Stdio = Stdio.Pipe
	// Where the child writes standard error.
	stderr: Stdio = Stdio.Pipe
	// The child's working directory; none inherits the caller's.
	cwd: String?
	// Variables added to or replaced in the inherited environment.
	env: Map[String, String] = Map[String, String]()

// The shape of `run` and `spawn`, for code that takes child-process operations as a
// parameter so a test can pass a fake. Programs call the module functions `run` and
// `spawn` directly.
export interface Commands:
	/*
    Starts `program` directly, without a shell, searching the PATH, and waits for it to finish. `arguments` are passed after the program name, `options.input` is written to its standard input, and its output is captured.
    Output beyond `options.max_output_bytes` in total across both streams returns EOVERFLOW, `options.timeout` returns ETIMEDOUT, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
    `options.cwd` is the child's working directory (none inherits the caller's); `options.env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns ENOENT. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
    */
	fn run(
		program: String,
		arguments: List[String],
		options: RunOptions = RunOptions(),
	) CommandOutput!
	// Starts `program` directly, without a shell, searching the PATH, and returns a
	// live Subprocess that its scope closes. `arguments` follow the program name;
	// `options.stdin`, `options.stdout`, and `options.stderr` each choose a pipe (the
	// default), the parent's own stream, or the null device. Returns EINVAL, ENOENT (no such program or
	// working directory), EACCES (not executable), or EIO when it cannot start. Closing the Subprocess, or cancelling the acquiring
	// execution, kills the child's process group.
	// `options.cwd` and `options.env` behave as in `run`.
	fn spawn(
		program: String,
		arguments: List[String],
		options: SpawnOptions = SpawnOptions(),
	) Subprocess!

// The runtime handle behind a `Subprocess`.
export extern type NativeSubprocess

/*
A long-lived child process with live stdin, stdout, and stderr streams. Closing it
kills the child's process group, joins it, and closes all three streams.
A stream spawned as Stdio.Inherit or Stdio.Null has no pipe: it is already closed, so a read returns end of stream (`none`) and a write returns EBADF.
*/
export opaque type Subprocess:
	// The runtime handle; it is released by `close` and owned by this value.
	native: NativeSubprocess

// Kills the process group, joins the child, kills leftover group members, and
// closes all three streams. Idempotent; scope exit calls it.
fn var Subprocess.close() Unit!:
	msstd_process_subprocess_close(self.native)

// The child's standard input as a WriteStream; writes block when the pipe is full.
// Closing the stream delivers end-of-input to the child.
fn Subprocess.stdin() WriteStream[Bytes]:
	return WriteStream[Bytes](
		DescriptorSink(msstd_process_subprocess_stream_id(self.native, 0))
	)

// The child's standard output as a ReadStream over the OS pipe; reads block until
// output or end-of-file, and nothing is buffered without bound.
fn Subprocess.stdout() ReadStream[Bytes]:
	return ReadStream[Bytes](
		DescriptorSource(msstd_process_subprocess_stream_id(self.native, 1))
	)

// The child's standard error as a ReadStream over the OS pipe, with the same
// blocking and backpressure behavior as stdout.
fn Subprocess.stderr() ReadStream[Bytes]:
	return ReadStream[Bytes](
		DescriptorSource(msstd_process_subprocess_stream_id(self.native, 2))
	)

// Waits for the child to exit and returns its exit status. Returns ETIMEDOUT if
// `timeout` elapses first, leaving the child running.
fn Subprocess.wait(timeout: Duration? = none) Int!:
	return msstd_process_subprocess_wait(self.native, timeout)

// The child's peak resident set size in bytes, known once `wait` has returned its
// exit status; 0 before that or when the host cannot report it.
fn Subprocess.max_resident_bytes() Int:
	return msstd_process_subprocess_max_resident(self.native)

// Sends SIGTERM to the child's process group on Unix; Windows has no SIGTERM, so it
// kills the direct process. Does not wait.
fn Subprocess.terminate() Unit:
	return msstd_process_subprocess_terminate(self.native)

// Sends SIGKILL to the child's process group. Does not wait.
fn Subprocess.kill() Unit:
	return msstd_process_subprocess_kill(self.native)

// Identity and invocation details for the current process.
export type ProcessInfo:
	// Operating system id of this process.
	pid: Int
	// Operating system id of the parent process at the time of the call.
	parent_pid: Int
	// Absolute path of the running program file.
	executable: String
	// Live native argv including argv[0]; process.arguments() is the supplied startup
	// tail without it.
	arguments: List[String]
	// Operating system name, such as `linux`, `darwin`, or `windows`.
	os: String
	// Processor architecture name, such as `amd64` or `arm64`.
	architecture: String
	// Real user id; -1 on Windows, where ids are not numeric.
	uid: Int
	// Real group id; -1 on Windows, where ids are not numeric.
	gid: Int
	// Effective user id used for permission checks; -1 on Windows.
	effective_uid: Int
	// Effective group id used for permission checks; -1 on Windows.
	effective_gid: Int

// Which of the process identities `set_identity` changes.
export enum IdentityKind:
	Uid  // The real user id.
	Gid  // The real group id.
	Euid  // The effective user id.
	Egid  // The effective group id.

// Cumulative CPU time consumed by the current process, in integer microseconds.
export type CpuUsage:
	// User CPU time in microseconds.
	user_microseconds: Int
	// Kernel CPU time in microseconds.
	system_microseconds: Int

/*
Kernel resource counters for the current process. CPU times are integer microseconds;
max_resident_bytes is bytes; other fields are counts, not durations or byte totals.
Filesystem reads/writes count native block I/O on Unix and I/O operations on Windows.
Unavailable Windows fault/context-switch counters are zero.
*/
export type ResourceUsage:
	// Cumulative CPU time spent running this process's own code, in microseconds.
	user_microseconds: Int
	// Cumulative CPU time the kernel spent on behalf of this process, in microseconds.
	system_microseconds: Int
	// Peak physical memory the process has held at once, in bytes.
	max_resident_bytes: Int
	// Page faults served without disk I/O, as a count.
	minor_faults: Int
	// Page faults that required disk I/O, as a count.
	major_faults: Int
	// Block input operations charged to the process, as a count.
	filesystem_reads: Int
	// Block output operations charged to the process, as a count.
	filesystem_writes: Int
	// Context switches where the process gave up the CPU, such as to wait for I/O, as a
	// count.
	voluntary_switches: Int
	// Context switches where the scheduler preempted the process, as a count.
	involuntary_switches: Int

// The runtime observer behind `watch_signals`; signals arriving while no read waits are
// buffered.
export extern type NativeSignals

type SignalSource:
	signals: NativeSignals

fn var SignalSource.next() Int?!:
	return ok(msstd_process_signal_next(self.signals)?)

// Stops observing signals and wakes a pending read with EBADF.
fn var SignalSource.close() Unit!:
	msstd_process_signal_close(self.signals)

// The names of an environment map, in the order of its values.
fn environment_names(environment: Map[String, String]) List[String]:
	var names = environment.entries().map(fn entry: entry.key.clone())
	return names

// The values of an environment map, in the order of its names.
fn environment_values(environment: Map[String, String]) List[String]:
	var values = environment.entries().map(fn entry: entry.value.clone())
	return values

// The work of `run`.
fn run_command(
	program: String,
	arguments: List[String],
	options: RunOptions,
) CommandOutput!:
	return msstd_process_command_run(
		program,
		arguments,
		options.input,
		options.max_output_bytes,
		options.timeout,
		options.cwd,
		environment_names(options.env),
		environment_values(options.env),
	)

/*
Starts `program` directly, without a shell, searching the PATH, and returns a promise that finishes when it does. `arguments` are passed after the program name, `options.input` is written to its standard input, and its output is captured.
Output beyond `options.max_output_bytes` in total across both streams returns EOVERFLOW, `options.timeout` returns ETIMEDOUT, and in both cases the child's process group is killed. Cancelling the calling task also kills it.
`options.cwd` is the child's working directory (none inherits the caller's); `options.env` adds or replaces variables on top of the inherited environment, and a name that is empty or holds `=`, or a NUL byte anywhere, returns EINVAL. A `cwd` that does not exist returns ENOENT. Neither touches the caller's own directory or environment, so concurrent tasks can run children in different directories.
*/
// ms: effect std.process.run
export fn run(
	program: String,
	arguments: List[String] = [],
	options: RunOptions = RunOptions(),
) Promise[CommandOutput]:
	owned_program := program.clone()
	owned_arguments := arguments.clone()
	owned_options := options.clone()
	return promise(
		fn: run_command(owned_program, owned_arguments, owned_options),
		options: PromiseOptions(placement: Placement.Here)
	)

// Starts `program` directly, without a shell, searching the PATH, and returns a live
// Subprocess that its scope closes. `arguments` follow the program name;
// `options.stdin`, `options.stdout`, and `options.stderr` each choose a pipe (the
// default), the parent's own stream, or the null device. Returns EINVAL, ENOENT (no such program or working
// directory), EACCES (not executable), or EIO when it cannot start. Closing the Subprocess, or cancelling the acquiring execution,
// kills the child's process group.
// `options.cwd` and `options.env` behave as in `run`.
// ms: effect std.process.run
export fn spawn(
	program: String,
	arguments: List[String] = [],
	options: SpawnOptions = SpawnOptions(),
) Subprocess!:
	return msstd_process_command_spawn(
		program,
		arguments,
		options.stdin,
		options.stdout,
		options.stderr,
		options.cwd,
		environment_names(options.env),
		environment_values(options.env),
	)

/*
Observes native signal numbers 1..64, excluding SIGKILL/SIGSTOP; the list must be nonempty.
Capacity must be 1..1048576; omission/none uses 128 buffered signals.
Numeric validation does not guarantee OS support. Observing does not suppress host cancellation.
Each read yields the next signal number; the stream never ends on its own. Dropping it unregisters the observer.
Use scope-owned `Closeable` resources for shutdown cleanup, since cancellation may prevent code after a read from running.
*/
// ms: effect std.process.signal
export fn watch_signals(signals: List[Int], capacity: Int?) ReadStream[Int]!:
	native := msstd_process_watch_signals(signals, capacity)?
	return ok(ReadStream[Int](SignalSource(native)))

// Returns the current process title.
// Platforms that cannot read it return ENOTSUP.
// ms: effect std.process.read
export fn title() String!:
	return msstd_process_title()

// Sets the process title shown by tools such as `ps`. A title with NUL or newline
// returns EINVAL, and platforms that cannot rename a process return ENOTSUP.
// ms: effect std.process.write
export fn set_title(title: String) Unit!:
	return msstd_process_set_title(title)

// Replaces the supplementary group list with the groups of `username` from the account
// database plus `gid` first. Requires privilege. A failed user lookup returns EIO, a
// `gid` outside 0 through 2147483647 returns EINVAL, and a lack of privilege returns
// EACCES.
// ms: effect std.process.write
export fn initialize_groups(username: String, gid: Int) Unit!:
	return msstd_process_initialize_groups(username, gid)

// Replaces the running process image with `program` using exactly the given `arguments`
// as argv, where `arguments[0]` is the program name, and exactly the given
// `environment`. On success it never returns.
// `program` is a path, not a PATH lookup. An empty program, an empty argument list, or NUL bytes return EINVAL, and exec failures return ENOENT, EACCES, or EIO. ENOTSUP on Windows.
// ms: effect std.process.run
export fn replace(
	program: String,
	arguments: List[String],
	environment: Map[String, String],
) Unit!:
	var names: List[String] = []
	var values: List[String] = []

	for entry in environment.entries():
		names.append(entry.key.clone())
		values.append(entry.value.clone())

	return msstd_process_replace(program, arguments, names, values)

// Returns the process id, parent id, executable path, arguments, platform, and real and
// effective user and group ids. Text that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.process.read
export fn process_info() ProcessInfo!:
	return msstd_process_info()

// Returns cumulative user and kernel CPU time consumed by this process in microseconds.
// Platforms without resource accounting return ENOTSUP.
// ms: effect std.process.read
export fn cpu_usage() CpuUsage!:
	return msstd_process_cpu_usage()

// Validates a signed 32-bit PID and signal 0..64; the OS decides supported
// numbers/permissions. Signal 0 checks existence; Windows positive PIDs support 0 and
// forced INT/KILL/TERM termination. A pid that names no process returns ENOENT.
// ms: effect std.process.signal
export fn send_signal(pid: Int, signal: Int) Unit!:
	return msstd_process_send_signal(pid, signal)

// Returns the numeric ids of the supplementary groups of the process.
// Windows returns ENOTSUP.
// ms: effect std.process.read
export fn groups() List[Int]!:
	return msstd_process_groups()

// Returns kernel resource counters for this process: CPU times, peak resident size,
// page faults, block I/O, and context switches. Platforms without them return ENOTSUP.
// ms: effect std.process.read
export fn resource_usage() ResourceUsage!:
	return msstd_process_resource_usage()

// Sets mask 0..511 (0777) and returns the previous mask; ENOTSUP on Windows.
// ms: effect std.process.write
export fn umask(mask: Int) Int!:
	return msstd_process_umask(mask)

// Sets the real or effective user or group id to `id`, 0..2147483647; other ids return
// EINVAL. Identity changes require OS permission and are ENOTSUP on Windows.
// ms: effect std.process.write
export fn set_identity(kind: IdentityKind, id: Int) Unit!:
	if kind == IdentityKind.Uid: return msstd_process_set_identity("uid", id)
	if kind == IdentityKind.Gid: return msstd_process_set_identity("gid", id)
	if kind == IdentityKind.Euid: return msstd_process_set_identity("euid", id)

	return msstd_process_set_identity("egid", id)

// Replaces the supplementary group list with the given numeric ids, each 0 through
// 2147483647. Requires privilege. Invalid ids return EINVAL, a lack of privilege
// returns EACCES, and Windows returns ENOTSUP.
// ms: effect std.process.write
export fn set_groups(groups: List[Int]) Unit!:
	return msstd_process_set_groups(groups)

// Returns the scheduling priority of process `pid` (0 means the calling process) as a
// nice-style value, from -20 for highest to 19 for lowest. Windows maps its priority
// classes onto this range. A pid outside 0 through 2147483647 returns EINVAL, and
// platforms without priorities return ENOTSUP.
// ms: effect std.process.read
export fn get_priority(pid: Int) Int!:
	return msstd_system_get_priority(pid)

// Accepts pid 0..2147483647 and priority -20..19 (lower is higher priority).
// Unix uses nice values; Windows maps ranges to native priority classes.
// ms: effect std.process.write
export fn set_priority(pid: Int, priority: Int) Unit!:
	return msstd_system_set_priority(pid, priority)
