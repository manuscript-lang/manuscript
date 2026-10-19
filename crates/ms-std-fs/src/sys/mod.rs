//! Thin, safe wrappers over the host calls the filesystem natives need. Paths are byte strings
//! (UTF-8 on Windows); the Unix backend adds a trailing NUL and the Windows backend converts to
//! UTF-16. Both backends return the host's native error code (`errno` or a Win32 error) and share
//! the types below.
use alloc::vec::Vec;

#[cfg(unix)]
mod unix;
#[cfg(windows)]
mod windows;

#[cfg(unix)]
pub use unix::*;
#[cfg(windows)]
pub use windows::*;

pub type Errno = i32;

pub const S_IFMT: u32 = 0o170000;
pub const S_IFSOCK: u32 = 0o140000;
pub const S_IFLNK: u32 = 0o120000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IFBLK: u32 = 0o060000;
pub const S_IFDIR: u32 = 0o040000;
pub const S_IFCHR: u32 = 0o020000;
pub const S_IFIFO: u32 = 0o010000;

/// The entry kinds `read_dir` reports (the Unix `d_type` values).
pub const DT_UNKNOWN: u8 = 0;
pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;

/// What `stat` reports, in Unix terms: `mode` carries the `S_IF*` file type and permission bits.
/// Times are `(seconds, nanoseconds)`. Fields a host cannot report are zero.
#[derive(Clone, Copy, Debug, Default)]
pub struct Stat {
    pub mode: u32,
    pub size: i64,
    pub modified: (i64, i64),
    pub accessed: (i64, i64),
    pub changed: (i64, i64),
    pub block_size: u64,
    pub blocks: u64,
    pub rdev: u64,
    pub device: u64,
    pub inode: u64,
    pub links: u64,
    pub uid: u64,
    pub gid: u64,
}

impl Stat {
    pub fn kind(&self) -> u32 {
        self.mode & S_IFMT
    }

    pub fn is_dir(&self) -> bool {
        self.kind() == S_IFDIR
    }

    pub fn is_link(&self) -> bool {
        self.kind() == S_IFLNK
    }

    pub fn is_regular(&self) -> bool {
        self.kind() == S_IFREG
    }

    /// Whether both describe the same file (`os.SameFile`).
    pub fn same_file(&self, other: &Stat) -> bool {
        self.device == other.device && self.inode == other.inode
    }
}

pub fn is_dir(st: &Stat) -> bool {
    st.is_dir()
}

#[derive(Clone, Copy)]
pub struct FsStat {
    pub kind: i64,
    pub block_size: i64,
    pub blocks: i64,
    pub blocks_free: i64,
    pub blocks_available: i64,
    pub files: i64,
    pub files_free: i64,
}

/// What a wait is for.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Interest {
    Read,
    Write,
}

/// Directory entries `(name, kind)` where `kind` is one of the `DT_*` values.
pub type DirEntries = Vec<(Vec<u8>, u8)>;
