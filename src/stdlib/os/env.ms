// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.fs.read

import (
	parse_dotenv from "@std/data/config.ms",
	access, stat from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	Os, os from "@std/os/system.ms",

	msrt_args,
	msstd_process_change_directory,
	msstd_process_environment_is_set,
	msstd_process_environment_map,
	msstd_process_set_environment,
	msstd_process_working_directory,
	msstd_system_home_directory from "@std/internal/env.ms",
	msstd_fs_read_file from "@std/internal/fs.ms",
)

// Returns the startup arguments the host supplied, excluding the executable path.
// Each call returns a new list, so changing it affects neither later calls nor the
// native argv.
// ms: effect std.env.read
export fn arguments() List[String] {
	return msrt_args()
}

/*
Finds the executable that running `name` would start, or null.
A name containing a path separator is checked without searching PATH. Otherwise each directory of `PATH` is searched in order, skipping empty entries.
Candidates are tried as given, then on Windows with each `PATHEXT` extension (`.COM;.EXE;.BAT;.CMD` when unset); environment variable names are case-insensitive there.
The result is a regular file the process may execute (any regular file on Windows). It is not made absolute or canonical.
Example: `if path := which("git"): print(path)` prints the executable found on this host.
*/
// ms: effect std.env.read
// ms: effect std.fs.read
export fn which(name String) String? {
	if name == "" { return null }

	windows := os() == Os.Windows
	has_path := name.contains("/") or (windows and name.contains("\\"))
	var extensions = List[String]()
	var separator = ":"
	var directories = List[String]()

	if windows {
		separator = ";"
		extensions = [".COM", ".EXE", ".BAT", ".CMD"]
	}

	env := environment()

	if env.is_ok() {
		for entry in env.get_or(Map[String, String]()).entries() {
			key := if windows { entry.key.upper() } else { entry.key.clone() }
			if key == "PATH" {
				directories = entry.value.split(separator).clone()
			}
			if key == "PATHEXT" and windows {
				extensions = entry.value.split(";").clone()
			}
		}
	}

	if has_path {
		directories = [""]
	}

	for directory in directories {
		if directory == "" and not has_path { continue }

		candidate := if directory == "" {
			name.clone()
		} else {
			join([directory.clone(), name.clone()])
		}
		if runnable(candidate, windows) { return candidate }

		for extension in extensions {
			if extension == "" { continue }
			if runnable(f"{candidate}{extension}", windows) { return f"{candidate}{extension}" }
		}
	}

	return null
}

fn runnable(path String, windows Bool) Bool {
	info := stat(path)
	if info.is_error() or not info.get().is_file() { return false }
	if windows { return true }

	return access(path, 1).is_ok()
}

// Returns a new map of the process's current environment. An entry whose name or value
// is not valid UTF-8 is left out.
// ms: effect std.env.read
export fn environment() Map[String, String]! {
	return msstd_process_environment_map()
}

// Sets environment variable `name` for this process to `value`, or removes it when
// `value` is null. An empty name, or a name or value with `=` or NUL, returns EINVAL.
// The change is visible to child processes started afterwards.
// ms: effect std.env.write
export fn set_environment(name String, value String?) Void! {
	return msstd_process_set_environment(name, value)
}

// Reads `KEY=value` lines from the file at `path` and sets each variable that is not
// already present in the environment. Existing variables keep their values, and a later
// duplicate name in the file replaces the earlier one.
// Blank lines, `#` comments, an `export ` prefix, and single-, double-, or
// backtick-quoted values spanning lines are accepted.
// The whole file is validated first, so a malformed or non-UTF-8 file returns EBADMSG
// and changes nothing. A file larger than `max_bytes` returns EOVERFLOW, and a
// directory returns EINVAL, as for `read_file`.
// ms: effect std.env.write
// ms: effect std.fs.read
export fn load_environment(path String, max_bytes Int? = null) Void! {
	data := msstd_fs_read_file(path, max_bytes)?
	text := data.decode_utf8()
	if text == null { return error(Error("environment: invalid data", kind: "EBADMSG")) }

	entries := parse_dotenv(text)?

	for entry in entries.entries() {
		if msstd_process_environment_is_set(entry.key) { continue }

		set_environment(entry.key, entry.value)?
	}
}

// Returns the process's current working directory. An OS failure is returned as an
// `Error`.
// ms: effect std.env.read
export fn working_directory() String! {
	return msstd_process_working_directory()
}

// Changes the working directory of the whole process, affecting relative paths
// everywhere. A missing path returns ENOENT, a path containing NUL returns EINVAL, and
// a denied path returns EACCES.
// ms: effect std.env.write
export fn change_directory(path String) Void! {
	return msstd_process_change_directory(path)
}

// Returns the current user's home directory path, from the host's environment or
// account database. A path that is not valid UTF-8 returns ENOTSUP.
// ms: effect std.env.read
export fn home_directory() String! {
	return msstd_system_home_directory()
}
