//! `ms init [--lib | --workspace] [directory]`: create a runnable project or a workspace. Fully implemented here;
//! it needs no engine.

use ms_driver::project::pathops;

use crate::backend::Io;

const MAIN: &str = "import arguments from \"@std/os/env.ms\"\n\nfn main() Void:\n\tprint(f\"Arguments: {arguments().length()}\")\n";
const TEST: &str = "import panic from \"@std/core.ms\"\n\ntest \"arithmetic\":\n\tif not (2 + 3 == 5): return panic(message: \"arithmetic failed\")\n";
const LIB: &str = "export fn greeting(name: String) String: f\"Hello, {name}\"\n";
const LIB_TEST: &str = "import (\n\texpect_equal from \"@std/test/test.ms\",\n\n\tgreeting from \"./src/lib.ms\",\n)\n\ntest \"greeting\":\n\texpect_equal(greeting(\"ms\"), \"Hello, ms\")?\n";
const WORKSPACE_MAIN: &str = include_str!("init/workspace_main.ms");
const IGNORE: &str = ".ms-cache/\n";

pub fn run_init(args: &[String], io: &mut Io) -> i32 {
    let mut directory = ".".to_string();
    let mut given = false;
    let mut library = false;
    let mut workspace = false;
    for arg in args {
        if arg == "--lib" && !library && !workspace {
            library = true;
            continue;
        }
        if arg == "--workspace" && !workspace && !library {
            workspace = true;
            continue;
        }
        if arg.starts_with('-') || given {
            let _ = writeln!(
                io.stderr,
                "unexpected init argument: {arg}; ms init takes --lib or --workspace (not both) and at most one directory, e.g. ms init --lib greeter"
            );
            return 2;
        }
        if arg.is_empty() {
            let _ = writeln!(
                io.stderr,
                "ms init: the directory is empty; pass a directory name such as ms init hello, or omit it for the current directory"
            );
            return 2;
        }
        directory = arg.clone();
        given = true;
    }
    let absolute = match pathops::abs(&directory) {
        Ok(path) => path,
        Err(error) => return fail_plain(io, &error.to_string()),
    };
    let manifest = |name: &str, source: &str, entry: &str, extra: &str| {
        format!(
            "[project]\nname = {}\nsource = \"{source}\"\n{entry}{extra}",
            ms_driver::project::quoting::quote(name)
        )
    };
    let files: Vec<(String, String)> = if workspace {
        let app = manifest(
            "app",
            "./src",
            "entry = \"./src/main.ms\"\n",
            "\n[dependencies]\n\"@greeter\" = { path = \"../libs/greeter\" }\n",
        );
        vec![
            (
                "ms.toml".to_string(),
                "[workspace]\nmembers = [\"app\", \"libs/*\"]\n".to_string(),
            ),
            ("app/ms.toml".to_string(), app),
            ("app/src/main.ms".to_string(), WORKSPACE_MAIN.to_string()),
            ("app/test.ms".to_string(), TEST.to_string()),
            (
                "libs/greeter/ms.toml".to_string(),
                manifest("greeter", "./src", "", ""),
            ),
            ("libs/greeter/src/lib.ms".to_string(), LIB.to_string()),
            ("libs/greeter/test.ms".to_string(), LIB_TEST.to_string()),
        ]
    } else {
        let (entry, source_name, source, test) = if library {
            ("", "lib.ms", LIB, LIB_TEST)
        } else {
            ("entry = \"./src/main.ms\"\n", "main.ms", MAIN, TEST)
        };
        vec![
            (
                "ms.toml".to_string(),
                manifest(&project_name(&absolute), "./src", entry, ""),
            ),
            (pathops::join(&["src", source_name]), source.to_string()),
            ("test.ms".to_string(), test.to_string()),
        ]
    };
    for (name, _) in &files {
        if std::fs::symlink_metadata(pathops::join(&[&absolute, name])).is_ok() {
            let _ = writeln!(
                io.stderr,
                "ms init: {} already exists; run it in an empty directory or remove the file first",
                pathops::join(&[&directory, name])
            );
            return 1;
        }
    }
    let create = || -> std::io::Result<()> {
        for (name, content) in &files {
            let path = pathops::join(&[&absolute, name]);
            std::fs::create_dir_all(pathops::dir(&path))?;
            std::fs::write(path, content)?;
        }
        ignore_build_cache(&pathops::join(&[&absolute, ".gitignore"]))
    };
    if let Err(error) = create() {
        let message = ms_driver::project::error::errno_message(error.raw_os_error().unwrap_or(0));
        let _ = writeln!(
            io.stderr,
            "ms init: cannot create project in {directory}: {message}"
        );
        return 1;
    }
    let _ = writeln!(io.stdout, "Created project in {directory}");
    let manifest = shell_quote(&operand(&pathops::join(&[&directory, "ms.toml"])));
    let next = if workspace {
        let app = shell_quote(&operand(&pathops::join(&[&directory, "app/ms.toml"])));
        format!("ms run {app}; ms test runs every member from {directory}")
    } else if library {
        format!("ms test {manifest}")
    } else {
        format!("ms run {manifest} -- first second")
    };
    let _ = writeln!(io.stdout, "Next: {next}");
    0
}

fn fail_plain(io: &mut Io, message: &str) -> i32 {
    let _ = writeln!(io.stderr, "{message}");
    1
}

/// Create `.gitignore`, or append the cache entry to an existing one that does
/// not already exclude it.
fn ignore_build_cache(path: &str) -> std::io::Result<()> {
    let existing = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(error),
    };
    if existing.split('\n').any(|line| {
        matches!(
            line.trim(),
            ".ms-cache" | ".ms-cache/" | "/.ms-cache" | "/.ms-cache/"
        )
    }) {
        return Ok(());
    }
    let mut content = existing;
    if !content.is_empty() && !content.ends_with('\n') {
        content.push('\n');
    }
    std::fs::write(path, content + IGNORE)
}

/// A manifest name from the directory: lowercase letters, digits, `-` and `_`,
/// falling back to `app`.
fn project_name(directory: &str) -> String {
    let mut name = String::new();
    for c in pathops::base(directory)
        .chars()
        .flat_map(char::to_lowercase)
    {
        match c {
            'a'..='z' | '0'..='9' | '-' | '_' => name.push(c),
            ' ' | '.' => name.push('-'),
            _ => {}
        }
    }
    let trimmed = name.trim_matches(['-', '_']);
    if trimmed.is_empty() {
        "app".to_string()
    } else {
        trimmed.to_string()
    }
}

/// A path spelled so the argument parser reads it as a file, not an option.
fn operand(path: &str) -> String {
    if path.starts_with('-') {
        format!("./{path}")
    } else {
        path.to_string()
    }
}

/// Quote a path for display in a command the user can paste.
fn shell_quote(path: &str) -> String {
    if !path.contains(|c| " \t\n'\"\\$`!&;|<>()*?[]{}#~".contains(c)) {
        return path.to_string();
    }
    format!("'{}'", path.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(project_name("/x/My App.v2"), "my-app-v2");
        assert_eq!(project_name("/x/___"), "app");
        assert_eq!(project_name("/x/Hello"), "hello");
    }

    #[test]
    fn operands() {
        assert_eq!(operand("-demo/ms.toml"), "./-demo/ms.toml");
        assert_eq!(operand("demo/ms.toml"), "demo/ms.toml");
    }

    #[test]
    fn quoting() {
        assert_eq!(shell_quote("a b/ms.toml"), "'a b/ms.toml'");
        assert_eq!(shell_quote("hello/ms.toml"), "hello/ms.toml");
        assert_eq!(shell_quote("it's"), "'it'\\''s'");
    }
}
