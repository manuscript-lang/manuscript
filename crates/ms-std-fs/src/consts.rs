//! `fs.constants()`: host file constants, sorted by name.
#[cfg(windows)]
use crate::sys;
use alloc::vec::Vec;

#[cfg(unix)]
pub fn file_constants() -> Vec<(&'static str, i64)> {
    let mut v: Vec<(&'static str, i64)> = alloc::vec![
        ("COPYFILE_EXCL", 1),
        ("COPYFILE_FICLONE", 2),
        ("COPYFILE_FICLONE_FORCE", 4),
        ("F_OK", 0),
        ("O_APPEND", libc::O_APPEND as i64),
        ("O_CREAT", libc::O_CREAT as i64),
        ("O_DIRECTORY", libc::O_DIRECTORY as i64),
        ("O_DSYNC", libc::O_DSYNC as i64),
        ("O_EXCL", libc::O_EXCL as i64),
        ("O_NOCTTY", libc::O_NOCTTY as i64),
        ("O_NOFOLLOW", libc::O_NOFOLLOW as i64),
        ("O_NONBLOCK", libc::O_NONBLOCK as i64),
        ("O_RDONLY", libc::O_RDONLY as i64),
        ("O_RDWR", libc::O_RDWR as i64),
        ("O_SYNC", libc::O_SYNC as i64),
        ("O_TRUNC", libc::O_TRUNC as i64),
        ("O_WRONLY", libc::O_WRONLY as i64),
        ("R_OK", 4),
        ("S_IFBLK", libc::S_IFBLK as i64),
        ("S_IFCHR", libc::S_IFCHR as i64),
        ("S_IFDIR", libc::S_IFDIR as i64),
        ("S_IFIFO", libc::S_IFIFO as i64),
        ("S_IFLNK", libc::S_IFLNK as i64),
        ("S_IFMT", libc::S_IFMT as i64),
        ("S_IFREG", libc::S_IFREG as i64),
        ("S_IFSOCK", libc::S_IFSOCK as i64),
        ("S_IRGRP", 0o040),
        ("S_IROTH", 0o004),
        ("S_IRUSR", 0o400),
        ("S_IRWXG", 0o070),
        ("S_IRWXO", 0o007),
        ("S_IRWXU", 0o700),
        ("S_IWGRP", 0o020),
        ("S_IWOTH", 0o002),
        ("S_IWUSR", 0o200),
        ("S_IXGRP", 0o010),
        ("S_IXOTH", 0o001),
        ("S_IXUSR", 0o100),
        ("UV_DIRENT_BLOCK", 7),
        ("UV_DIRENT_CHAR", 6),
        ("UV_DIRENT_DIR", 2),
        ("UV_DIRENT_FIFO", 4),
        ("UV_DIRENT_FILE", 1),
        ("UV_DIRENT_LINK", 3),
        ("UV_DIRENT_SOCKET", 5),
        ("UV_DIRENT_UNKNOWN", 0),
        ("UV_FS_COPYFILE_EXCL", 1),
        ("UV_FS_COPYFILE_FICLONE", 2),
        ("UV_FS_COPYFILE_FICLONE_FORCE", 4),
        ("UV_FS_O_FILEMAP", 0),
        ("UV_FS_SYMLINK_DIR", 1),
        ("UV_FS_SYMLINK_JUNCTION", 2),
        ("W_OK", 2),
        ("X_OK", 1),
    ];
    #[cfg(target_os = "linux")]
    {
        v.push(("O_DIRECT", libc::O_DIRECT as i64));
        v.push(("O_NOATIME", libc::O_NOATIME as i64));
    }
    v.sort_by(|a, b| a.0.cmp(b.0));
    v
}

/// The Windows set is what Go's `os` package defines there; the flag values are Go's own.
#[cfg(windows)]
pub fn file_constants() -> Vec<(&'static str, i64)> {
    alloc::vec![
        ("COPYFILE_EXCL", 1),
        ("COPYFILE_FICLONE", 2),
        ("COPYFILE_FICLONE_FORCE", 4),
        ("F_OK", 0),
        ("O_APPEND", sys::O_APPEND as i64),
        ("O_CREAT", sys::O_CREAT as i64),
        ("O_EXCL", sys::O_EXCL as i64),
        ("O_RDONLY", sys::O_RDONLY as i64),
        ("O_RDWR", sys::O_RDWR as i64),
        ("O_SYNC", sys::O_SYNC as i64),
        ("O_TRUNC", sys::O_TRUNC as i64),
        ("O_WRONLY", sys::O_WRONLY as i64),
        ("R_OK", 4),
        ("W_OK", 2),
        ("X_OK", 1),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_the_go_table() {
        let go = "COPYFILE_EXCL 1;COPYFILE_FICLONE 2;COPYFILE_FICLONE_FORCE 4;F_OK 0;O_APPEND 1024;O_CREAT 64;O_DIRECT 16384;O_DIRECTORY 65536;O_DSYNC 4096;O_EXCL 128;O_NOATIME 262144;O_NOCTTY 256;O_NOFOLLOW 131072;O_NONBLOCK 2048;O_RDONLY 0;O_RDWR 2;O_SYNC 1052672;O_TRUNC 512;O_WRONLY 1;R_OK 4;S_IFBLK 24576;S_IFCHR 8192;S_IFDIR 16384;S_IFIFO 4096;S_IFLNK 40960;S_IFMT 61440;S_IFREG 32768;S_IFSOCK 49152;S_IRGRP 32;S_IROTH 4;S_IRUSR 256;S_IRWXG 56;S_IRWXO 7;S_IRWXU 448;S_IWGRP 16;S_IWOTH 2;S_IWUSR 128;S_IXGRP 8;S_IXOTH 1;S_IXUSR 64;UV_DIRENT_BLOCK 7;UV_DIRENT_CHAR 6;UV_DIRENT_DIR 2;UV_DIRENT_FIFO 4;UV_DIRENT_FILE 1;UV_DIRENT_LINK 3;UV_DIRENT_SOCKET 5;UV_DIRENT_UNKNOWN 0;UV_FS_COPYFILE_EXCL 1;UV_FS_COPYFILE_FICLONE 2;UV_FS_COPYFILE_FICLONE_FORCE 4;UV_FS_O_FILEMAP 0;UV_FS_SYMLINK_DIR 1;UV_FS_SYMLINK_JUNCTION 2;W_OK 2;X_OK 1";
        let ours: Vec<alloc::string::String> = file_constants()
            .iter()
            .map(|(k, v)| alloc::format!("{k} {v}"))
            .collect();
        // The values in this table were recorded on linux/amd64.
        if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
            assert_eq!(ours.join(";"), go);
        } else if cfg!(windows) {
            let windows = "COPYFILE_EXCL 1;COPYFILE_FICLONE 2;COPYFILE_FICLONE_FORCE 4;F_OK 0;O_APPEND 1024;O_CREAT 64;O_EXCL 128;O_RDONLY 0;O_RDWR 2;O_SYNC 4096;O_TRUNC 512;O_WRONLY 1;R_OK 4;W_OK 2;X_OK 1";
            assert_eq!(ours.join(";"), windows);
        } else {
            assert_eq!(ours.len(), go.split(';').count());
        }
    }
}
