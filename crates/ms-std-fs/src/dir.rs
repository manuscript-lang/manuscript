//! Directory cursors and scoped temporary directories.
use crate::err::{Fail, Res};
use crate::ops;
use crate::sys::{self, CPath};
use alloc::vec::Vec;
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{STATUS_CLOSED, STATUS_UNSUPPORTED};

/// One entry of a directory cursor.
pub struct Item {
    pub name: Vec<u8>,
    pub directory: bool,
    pub symlink: bool,
}

ms_rt::ffi::abi_handle!(Directory);

pub struct Directory {
    dir: sys::Dir,
    path: Vec<u8>,
    closed: bool,
}

impl Directory {
    /// Opens `path`; anything but a directory is `Failed("not a directory")`.
    pub fn open(path: &[u8]) -> Res<Directory> {
        let p = CPath::new(path).ok_or_else(Fail::invalid)?;
        let st = sys::stat(&p, true).map_err(|e| Fail::errno(e, "open", path))?;
        if !sys::is_dir(&st) {
            return Err(Fail::failed("not a directory"));
        }
        let dir = sys::Dir::open(&p).map_err(|e| Fail::errno(e, "fdopendir", path))?;
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
            self.dir.close();
        }
    }

    /// The next entry in native order, `None` at the end.
    pub fn read(&mut self) -> Res<Option<Item>> {
        if self.closed {
            return Err(Fail::status(STATUS_CLOSED));
        }
        poll_cancel();
        let (name, kind) = match self.dir.read_entry() {
            Ok(Some(entry)) => entry,
            Ok(None) => return Ok(None),
            Err(e) => return Err(Fail::errno(e, "readdirent", &self.path)),
        };
        if core::str::from_utf8(&name).is_err() {
            return Err(Fail::status(STATUS_UNSUPPORTED));
        }
        let (directory, symlink) = ops::entry_kind(&self.path, &name, kind);
        Ok(Some(Item {
            name,
            directory,
            symlink,
        }))
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        self.close();
    }
}

ms_rt::ffi::abi_handle!(Temporary);

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
