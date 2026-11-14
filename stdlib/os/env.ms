import (
	access, stat from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	Os, os from "@std/os/system.ms",

	msrt_args,
	msstd_process_change_directory,
	msstd_process_environment_map,
	msstd_process_load_environment,
	msstd_process_set_environment,
	msstd_process_working_directory,
	msstd_system_home_directory from "@std/internal/env.ms",
)

// Returns the host-supplied startup arguments, excluding the executable path.
// Each call returns an owned list; mutations do not change later calls or native argv.
// ms: effect std.env.read
export fn arguments() List[String]:
	return msrt_args()

/*
Finds the executable that running `name` would start, or none.
A name containing a path separator is checked without searching PATH. Otherwise each directory of `PATH` is searched in order, skipping empty entries. Candidates are tried as given, then on Windows with each `PATHEXT` extension (`.COM;.EXE;.BAT;.CMD` when unset); environment variable names are case-insensitive there. The result is a regular file the process may execute (any regular file on Windows) and is not made absolute or canonical.
Example: `if path := which("git"): print(path)` prints the executable found on this host.
*/
// ms: effect std.env.read
// ms: effect std.fs.read
export fn which(name: String) String?:
	if name == "": return none

	windows := os() == Os.Windows
	has_path := name.contains("/") or (windows and name.contains("\\"))
	var extensions = List[String]()
	var separator = ":"
	var directories = List[String]()

	if windows:
		separator = ";"
		extensions = [".COM", ".EXE", ".BAT", ".CMD"]

	env := environment()

	if env.is_ok():
		for entry in env.get(Map[String, String]()).entries():
			key := if windows: entry.key.upper() else: entry.key
			if key == "PATH": directories = entry.value.split(separator).clone()
			if key == "PATHEXT" and windows: extensions = entry.value.split(";").clone()

	if has_path:
		directories = [""]

	for directory in directories:
		if directory == "" and not has_path: continue

		candidate := if directory == "": name.clone() else: join(
			[directory.clone(), name.clone()]
		)
		if runnable(candidate, windows): return candidate

		for extension in extensions:
			if extension == "": continue
			if runnable("{candidate}{extension}", windows): return "{candidate}{extension}"

	return none

fn runnable(path: String, windows: Bool) Bool:
	info := stat(path)
	if info.is_error() or not info.get().is_file(): return false
	if windows: return true

	return access(path, 1).is_ok()

// Reads a fresh live process environment map. An entry whose name or value is not valid
// UTF-8 is left out.
// ms: effect std.env.read
export fn environment() Map[String, String]!:
	return msstd_process_environment_map()

// Sets environment variable `name` for this process to `value`, or removes it when
// `value` is none. An empty name, or a name or value with `=` or NUL, returns EINVAL.
// The change is visible to child processes started afterwards.
// ms: effect std.env.write
export fn set_environment(name: String, value: String?) Unit!:
	return msstd_process_set_environment(name, value)

// Reads `KEY=value` lines from the file at `path` and sets each variable that is not
// already present in the environment. Existing variables keep their values. Blank
// lines, `#` comments, an `export ` prefix, and single-, double-, or backtick-quoted
// values spanning lines are accepted. The whole file is validated first, so a malformed
// or non-UTF-8 file returns EBADMSG and changes nothing. A file larger than `max_bytes`
// returns EOVERFLOW.
// ms: effect std.env.write
// ms: effect std.fs.read
export fn load_environment(path: String, max_bytes: Int? = none) Unit!:
	return msstd_process_load_environment(path, max_bytes)

// Reads the live process directory, preserving OS failures as `Error` values.
// ms: effect std.env.read
export fn working_directory() String!:
	return msstd_process_working_directory()

// Changes the working directory of the whole process, affecting relative paths
// everywhere. A missing path returns ENOENT, a path containing NUL returns EINVAL, and
// a denied path returns EACCES.
// ms: effect std.env.write
export fn change_directory(path: String) Unit!:
	return msstd_process_change_directory(path)

// Returns the current user's home directory path, from the host's environment or
// account database. A path that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.env.read
export fn home_directory() String!:
	return msstd_system_home_directory()
