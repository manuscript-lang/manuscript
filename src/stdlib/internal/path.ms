import Glob from "@std/os/path.ms"

// A glob compiled once. The leading `windows` flag selects the dialect: path separators
// are read as slashes when set. The matcher is shared with `fs.glob`'s directory walk,
// so it stays native.
export extern fn msstd_path_compile_glob(windows Bool, pattern String) move Glob!

// Tests one path against a compiled glob; a path with a NUL byte returns EINVAL.
export extern fn msstd_path_glob_matches(glob Glob, path String) Bool!

// Whether the program runs on Windows, so path functions without a dialect argument
// read Windows rules.
export extern fn msstd_path_host_windows() Bool
