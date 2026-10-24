//! Error values whose `Display` output is stable.

use std::fmt;

/// A position in the original manifest text. `offset` is a byte offset;
/// `line` and `column` are one-based.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Location {
    pub file: String,
    pub line: usize,
    pub column: usize,
    pub offset: usize,
}

/// A failed operating-system call on a path, rendered like Go's `*fs.PathError`:
/// `op path: message`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PathError {
    pub op: &'static str,
    pub path: String,
    pub errno: i32,
}

/// A manifest problem with its location kept apart from its cause.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ManifestError {
    pub location: Location,
    pub cause: Box<ProjectError>,
}

/// Every failure this crate reports.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProjectError {
    /// `ms.toml:LINE:COL: message`.
    Manifest(ManifestError),
    /// A failed system call with its path.
    Path(PathError),
    /// A bare errno, e.g. `not a directory`, as Go returns from symlink walks.
    Errno(i32),
    /// Any other message.
    Message(String),
}

impl ProjectError {
    pub(crate) fn msg(text: impl Into<String>) -> Self {
        ProjectError::Message(text.into())
    }

    pub fn path(op: &'static str, path: &str, error: &std::io::Error) -> Self {
        ProjectError::Path(PathError {
            op,
            path: path.to_string(),
            errno: error.raw_os_error().unwrap_or(0),
        })
    }

    pub(crate) fn manifest(location: Location, cause: ProjectError) -> Self {
        ProjectError::Manifest(ManifestError {
            location,
            cause: Box::new(cause),
        })
    }

    /// True for `ENOENT` only, like Go's `os.IsNotExist` (which on Windows also takes
    /// `ERROR_PATH_NOT_FOUND`, a missing directory on the way).
    pub fn is_not_exist(&self) -> bool {
        let missing = |errno: i32| errno == ENOENT || (cfg!(windows) && errno == 3);
        match self {
            ProjectError::Path(error) => missing(error.errno),
            ProjectError::Errno(errno) => missing(*errno),
            ProjectError::Manifest(error) => error.cause.is_not_exist(),
            ProjectError::Message(_) => false,
        }
    }

    /// The manifest location, when this error carries one.
    pub fn manifest_error(&self) -> Option<&ManifestError> {
        match self {
            ProjectError::Manifest(error) => Some(error),
            _ => None,
        }
    }
}

pub(crate) const ENOENT: i32 = 2;
#[cfg(not(windows))]
pub(crate) const ENOTDIR: i32 = 20;

/// The Go (`syscall.Errno`) message for an errno: lower-case, no `(os error N)`.
pub fn errno_message(errno: i32) -> String {
    let text = std::io::Error::from_raw_os_error(errno).to_string();
    let text = match text.rfind(" (os error") {
        Some(end) => &text[..end],
        None => &text,
    };
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

impl fmt::Display for PathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} {}: {}",
            self.op,
            self.path,
            errno_message(self.errno)
        )
    }
}

impl fmt::Display for ManifestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}:{}:{}: {}",
            self.location.file, self.location.line, self.location.column, self.cause
        )
    }
}

impl fmt::Display for ProjectError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProjectError::Manifest(error) => error.fmt(f),
            ProjectError::Path(error) => error.fmt(f),
            ProjectError::Errno(errno) => f.write_str(&errno_message(*errno)),
            ProjectError::Message(text) => f.write_str(text),
        }
    }
}

impl std::error::Error for ProjectError {}
