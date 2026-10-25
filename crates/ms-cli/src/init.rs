//! `ms init [directory]`: create a runnable project. Fully implemented here;
//! it needs no engine.

use ms_driver::project::pathops;

use crate::backend::Io;

const MAIN: &str = "from \"@std/process.ms\" import arguments\nfrom \"@std/io.ms\" import stdout\n\nexport def main() -> Int:\n    let message = f\"Arguments: {arguments().length()}\\n\"\n    if stdout().write(message).is_error():\n        return 1\n\n    return 0\n";
const TEST: &str = "from \"@std/core.ms\" import panic\n\ntest \"arithmetic\":\n    if not (2 + 3 == 5):\n        return panic(message: \"arithmetic failed\")\n";
const IGNORE: &str = ".ms-cache/\n";

pub fn run_init(args: &[String], io: &mut Io) -> i32 {
    let mut directory = ".".to_string();
    let mut given = false;
    for arg in args {
        if arg.starts_with('-') || given {
            let _ = writeln!(
                io.stderr,
                "unexpected init argument: {arg} ; ms init takes at most one directory, e.g. ms init hello"
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
    let manifest = format!(
        "[project]\nname = {}\nsource = \"./src\"\nentry = \"./src/main.ms\"\n",
        ms_driver::project::quoting::quote(&project_name(&absolute))
    );
    let files = [
        ("ms.toml".to_string(), manifest),
        (pathops::join(&["src", "main.ms"]), MAIN.to_string()),
        ("test.ms".to_string(), TEST.to_string()),
    ];
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
        std::fs::create_dir_all(pathops::join(&[&absolute, "src"]))?;
        for (name, content) in &files {
            std::fs::write(pathops::join(&[&absolute, name]), content)?;
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
    let _ = writeln!(
        io.stdout,
        "Next: ms run {} -- first second",
        shell_quote(&pathops::join(&[&directory, "ms.toml"]))
    );
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
    fn quoting() {
        assert_eq!(shell_quote("a b/ms.toml"), "'a b/ms.toml'");
        assert_eq!(shell_quote("hello/ms.toml"), "hello/ms.toml");
        assert_eq!(shell_quote("it's"), "'it'\\''s'");
    }
}
