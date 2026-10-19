//! Directory cursors and scoped temporary directories, ported from `osDirectory` and
//! `osTemporary` in `pkg/runtime/fs_handle.go`.
use crate::err::{Fail, Res};
use crate::ops;
use crate::sys::{self, CPath};
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_CLOSED, STATUS_UNSUPPORTED};
use ms_std_rt::poll_cancel;

/// One entry of a directory cursor.
pub struct Item {
    pub name: Vec<u8>,
    pub directory: bool,
    pub symlink: bool,
}

pub struct Directory {
    dir: *mut libc::DIR,
    path: Vec<u8>,
    closed: bool,
}

impl Directory {
    /// Opens `path`; anything but a directory is `Failed("not a directory")`, as in the Go runtime.
    pub fn open(path: &[u8]) -> Res<Directory> {
        let p = CPath::new(path).ok_or_else(Fail::invalid)?;
        let fd = sys::open(&p, libc::O_RDONLY, 0).map_err(|e| Fail::errno(e, "open", path))?;
        let is_dir = sys::fstat(fd).map(|st| sys::is_dir(&st));
        match is_dir {
            Ok(true) => {}
            Ok(false) => {
                let _ = sys::close(fd);
                return Err(Fail::failed("not a directory"));
            }
            Err(e) => {
                let _ = sys::close(fd);
                return Err(Fail::errno(e, "stat", path));
            }
        }
        // SAFETY: `fd` is an open directory descriptor; `fdopendir` takes ownership on success.
        let dir = unsafe { libc::fdopendir(fd) };
        if dir.is_null() {
            let e = sys::errno();
            let _ = sys::close(fd);
            return Err(Fail::errno(e, "fdopendir", path));
        }
        Ok(Directory {
            dir,
            path: path.to_vec(),
            closed: false,
        })
    }

    pub fn path(&self) -> &[u8] {
        &self.path
    }

    pub fn close(&mut self) {
        if !self.closed {
            self.closed = true;
            // SAFETY: the stream is open and closed exactly once.
            unsafe { libc::closedir(self.dir) };
        }
    }

    /// The next entry in native order, `None` at the end.
    pub fn read(&mut self) -> Res<Option<Item>> {
        if self.closed {
            return Err(Fail::status(STATUS_CLOSED));
        }
        poll_cancel();
        loop {
            sys::set_errno(0);
            // SAFETY: the stream is open.
            let ent = unsafe { libc::readdir(self.dir) };
            if ent.is_null() {
                return match sys::errno() {
                    0 => Ok(None),
                    e => Err(Fail::errno(e, "readdirent", &self.path)),
                };
            }
            // SAFETY: `d_name` is NUL-terminated within the entry, which is valid until the next call.
            let (name, kind) = unsafe {
                (
                    core::ffi::CStr::from_ptr((*ent).d_name.as_ptr())
                        .to_bytes()
                        .to_vec(),
                    (*ent).d_type,
                )
            };
            if name == b"." || name == b".." {
                continue;
            }
            if core::str::from_utf8(&name).is_err() {
                return Err(Fail::status(STATUS_UNSUPPORTED));
            }
            let (directory, symlink) = ops::entry_kind(&self.path, &name, kind);
            return Ok(Some(Item {
                name,
                directory,
                symlink,
            }));
        }
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        self.close();
    }
}

/// A temporary directory removed with its contents when closed.
pub struct Temporary {
    path: Vec<u8>,
    closed: bool,
}

impl Temporary {
    pub fn create(prefix: &[u8]) -> Res<Temporary> {
        Ok(Temporary {
            path: ops::temporary_directory(prefix)?,
            closed: false,
        })
    }

    pub fn path(&self) -> &[u8] {
        &self.path
    }

    /// Removes the tree. The caller raises a fault with the text on failure.
    pub fn close(&mut self) -> Res<()> {
        if !self.closed {
            ops::remove_tree(&self.path)?;
            self.closed = true;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::string::String;
    use ms_rt_abi::STATUS_NOT_FOUND;

    #[test]
    fn cursor_and_temporary() {
        let mut t = Temporary::create(b"msfs-dir-").unwrap();
        let root = t.path().to_vec();
        ops::write_file(&crate::path::join(&root, b"a"), b"x", false).unwrap();
        ops::create_directory(&crate::path::join(&root, b"d"), false).unwrap();
        ops::create_link(&crate::path::join(&root, b"l"), b"a").unwrap();
        let mut d = Directory::open(&root).unwrap();
        let mut seen: Vec<(String, bool, bool)> = Vec::new();
        while let Some(i) = d.read().unwrap() {
            seen.push((String::from_utf8(i.name).unwrap(), i.directory, i.symlink));
        }
        seen.sort();
        assert_eq!(
            seen,
            [
                ("a".into(), false, false),
                ("d".into(), true, false),
                ("l".into(), false, true)
            ]
        );
        d.close();
        assert_eq!(d.read().err().unwrap().status, STATUS_CLOSED);
        let err = Directory::open(&crate::path::join(&root, b"a"))
            .err()
            .unwrap();
        assert_eq!(err.message.as_deref(), Some(b"not a directory".as_slice()));
        t.close().unwrap();
        assert_eq!(
            ops::stat(&root, true).err().unwrap().status,
            STATUS_NOT_FOUND
        );
    }
}
