//! Helpers shared by the command implementations.

use ms_project::{ProjectError, gopath};

use crate::backend::Io;
use crate::json::Json;

pub fn plural(n: usize, one: &'static str, many: &'static str) -> &'static str {
    if n == 1 { one } else { many }
}

/// Print `message` and a newline to stderr and return the usage status, 2.
pub fn usage_error(io: &mut Io, message: impl AsRef<str>) -> i32 {
    let _ = writeln!(io.stderr, "{}", message.as_ref());
    2
}

/// Levenshtein distance over bytes.
pub fn distance(a: &str, b: &str) -> usize {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    let mut previous: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut current = vec![i; b.len() + 1];
        for j in 1..=b.len() {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            current[j] = (previous[j] + 1)
                .min(current[j - 1] + 1)
                .min(previous[j - 1] + cost);
        }
        previous = current;
    }
    previous[b.len()]
}

/// Turn a failed file operation into a cause and a fix.
pub fn file_error(error: &ProjectError) -> String {
    match error {
        ProjectError::Path(path) if error.is_not_exist() => {
            format!(
                "file not found: {}; check the path and run from the directory that contains it",
                path.path
            )
        }
        ProjectError::Manifest(manifest) => file_error(&manifest.cause),
        other => other.to_string(),
    }
}

/// Write a JSON document to stdout and return `status`.
pub fn emit_json(io: &mut Io, value: &Json, status: i32) -> i32 {
    match io.stdout.write_all(value.encode().as_bytes()) {
        Ok(()) => status,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            1
        }
    }
}

/// Write to a file, or to stdout when `filename` is empty.
pub fn write_output(io: &mut Io, filename: &str, data: &[u8]) -> i32 {
    let result = if filename.is_empty() {
        io.stdout.write_all(data)
    } else {
        std::fs::write(filename, data)
    };
    match result {
        Ok(()) => 0,
        Err(error) => {
            let message = match (filename.is_empty(), &error) {
                (false, e) => ProjectError::path("open", filename, e).to_string(),
                (true, e) => e.to_string(),
            };
            let _ = writeln!(io.stderr, "{message}");
            1
        }
    }
}

/// A directory argument selects the `ms.toml` inside it.
pub fn resolve_input(command: &str, filename: &str) -> Result<String, String> {
    if std::fs::metadata(filename).is_ok_and(|m| m.is_dir()) {
        let manifest = gopath::join(&[filename, "ms.toml"]);
        if std::fs::metadata(&manifest).is_err() {
            return Err(format!(
                "ms {command}: {filename} is a directory without an ms.toml; pass a .ms file or a project ms.toml, e.g. ms {command} ms.toml"
            ));
        }
        return Ok(manifest);
    }
    Ok(filename.to_string())
}

/// The working directory with symlinks resolved.
pub fn format_cwd() -> Result<String, ProjectError> {
    let cwd = std::env::current_dir().map_err(|e| ProjectError::path("getwd", "", &e))?;
    gopath::eval_symlinks(&cwd.to_string_lossy())
}

/// Display uses physical identity for both explicit and discovered targets.
/// Outside the invocation directory it stays absolute.
pub fn format_display(cwd: &str, path: &str) -> String {
    let Ok(mut absolute) = gopath::abs(path) else {
        return gopath::clean(path);
    };
    if let Ok(physical) = gopath::eval_symlinks(&absolute) {
        absolute = physical;
    }
    if let Ok(relative) = gopath::rel(cwd, &absolute)
        && !gopath::escapes(&relative)
    {
        if relative.starts_with('-') {
            return format!("./{relative}");
        }
        return relative;
    }
    absolute
}

/// Recognize `--name=value` only for long options that take values; keep other
/// tokens intact for diagnostics. Returns `(name, value, inline)`.
pub fn split_value_option<'a>(arg: &'a str, options: &[&str]) -> (&'a str, &'a str, bool) {
    if let Some((name, value)) = arg.split_once('=')
        && name.starts_with("--")
        && options.contains(&name)
    {
        return (name, value, true);
    }
    (arg, "", false)
}

/// Consume a split value or use its inline spelling; empty values are rejected.
pub fn required_value<'a>(
    args: &'a [String],
    index: &mut usize,
    value: &'a str,
    inline: bool,
) -> Option<&'a str> {
    let value = if inline {
        value
    } else {
        *index += 1;
        args.get(*index)?
    };
    (!value.is_empty()).then_some(value)
}
