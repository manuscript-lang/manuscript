//! `@std/fs` file-handle operations.
//!
//! A file handle is a [`Stream`] whose descriptor was opened by [`open`]; the same object also
//! serves as the `reader()` / `writer()` `@std/io` views. Every operation first returns bytes a
//! line reader took ahead to the file, so offsets agree with what the program has consumed.
use crate::err::{Fail, Res};
use crate::ops::{self, Info};
use crate::path;
use crate::stream::Stream;
use crate::sys::{self, CPath};
use alloc::vec::Vec;
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_INVALID_DATA, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED,
    STATUS_UNSUPPORTED,
};

/// `os.OpenFile` flag combinations for the mode strings of `open`.
pub fn flags_of_mode(mode: &[u8]) -> Option<i32> {
    use sys::{O_APPEND, O_CREAT, O_EXCL, O_RDONLY, O_RDWR, O_TRUNC, O_WRONLY};
    Some(match mode {
        b"r" => O_RDONLY,
        b"r+" => O_RDWR,
        b"w" => O_WRONLY | O_CREAT | O_TRUNC,
        b"wx" => O_WRONLY | O_CREAT | O_EXCL,
        b"w+" => O_RDWR | O_CREAT | O_TRUNC,
        b"wx+" => O_RDWR | O_CREAT | O_EXCL,
        b"a" => O_WRONLY | O_CREAT | O_APPEND,
        b"ax" => O_WRONLY | O_CREAT | O_APPEND | O_EXCL,
        b"a+" => O_RDWR | O_CREAT | O_APPEND,
        b"ax+" => O_RDWR | O_CREAT | O_APPEND | O_EXCL,
        _ => return None,
    })
}

/// Opens `path` with host `flags` and permission bits `mode` in `0..=4095`.
pub fn open(path: &[u8], flags: i64, mode: i64) -> Res<Stream> {
    if !(0..=2_147_483_647).contains(&flags) || !(0..=0o7777).contains(&mode) {
        return Err(Fail::invalid());
    }
    let p = CPath::new(path).ok_or_else(Fail::invalid)?;
    let flags = flags as i32;
    let fd = sys::open(&p, flags, mode as u32).map_err(|e| Fail::errno(e, "open", path))?;
    Ok(Stream::file_handle(fd, flags, path))
}

fn offset_ok(offset: i64) -> Res<()> {
    if offset < 0 {
        return Err(Fail::invalid());
    }
    Ok(())
}

impl Stream {
    /// Admits an operation: closed handles fail, the open mode is enforced, read-ahead is returned.
    fn admit(&mut self, kind: Access) -> Res<()> {
        if self.is_closed() {
            return Err(Fail::status(STATUS_CLOSED));
        }
        poll_cancel();
        self.rewind();
        if (kind == Access::Read && self.no_read) || (kind == Access::Write && self.no_write) {
            return Err(Fail::invalid());
        }
        Ok(())
    }

    fn fail(&self, op: &str, e: i32) -> Fail {
        Fail::errno(e, op, &self.name)
    }

    /// One positioned read of up to `max` bytes (`read_at`); short only at end of file.
    pub fn read_at(&mut self, offset: i64, max: Option<i64>) -> Res<Vec<u8>> {
        let n = chunk_size(max)?;
        self.admit(Access::Read)?;
        offset_ok(offset)?;
        let mut data = alloc::vec![0u8; n];
        let got = pread_full(self.fd, &mut data, offset).map_err(|e| self.fail("read", e))?;
        data.truncate(got);
        Ok(data)
    }

    /// Reads to the end of the file from the current position, failing past `max` bytes.
    pub fn read_file(&mut self, max: i64) -> Res<Vec<u8>> {
        self.admit(Access::Read)?;
        let data = ops::read_bounded(self.fd, max)?;
        if self.is_closed() {
            return Err(Fail::status(STATUS_CLOSED));
        }
        Ok(data)
    }

    pub fn write_at(&mut self, offset: i64, data: &[u8]) -> Res<()> {
        self.admit(Access::Write)?;
        offset_ok(offset)?;
        pwrite_all(self.fd, data, offset)
            .map_err(|e| self.fail("write", e))
            .map(|_| ())
    }

    /// `read_vectors`: `offset == -1` reads from the current position.
    pub fn read_vectors(&mut self, sizes: &[i64], mut offset: i64) -> Res<Vec<Vec<u8>>> {
        self.admit(Access::Read)?;
        if offset < -1 {
            return Err(Fail::invalid());
        }
        let mut total: i64 = 0;
        for &n in sizes {
            if !(0..=65536).contains(&n) || total > 16 * 1024 * 1024 - n {
                return Err(Fail::invalid());
            }
            total += n;
        }
        let mut out = Vec::with_capacity(sizes.len());
        for &size in sizes {
            poll_cancel();
            let mut b = alloc::vec![0u8; size as usize];
            let n = if offset == -1 {
                sys::read(self.fd, &mut b).map_err(|e| self.fail("read", e))?
            } else {
                let n = pread_full(self.fd, &mut b, offset).map_err(|e| self.fail("read", e))?;
                offset += n as i64;
                n
            };
            b.truncate(n);
            out.push(b);
        }
        Ok(out)
    }

    /// `write_vectors`: `offset == -1` appends at the current position.
    pub fn write_vectors(&mut self, buffers: &[&[u8]], mut offset: i64) -> Res<()> {
        self.admit(Access::Write)?;
        if offset < -1 {
            return Err(Fail::invalid());
        }
        for b in buffers {
            if offset == -1 {
                write_all_fd(self.fd, b).map_err(|e| self.fail("write", e))?;
            } else {
                pwrite_all(self.fd, b, offset).map_err(|e| self.fail("write", e))?;
                offset += b.len() as i64;
            }
        }
        Ok(())
    }

    pub fn seek(&mut self, offset: i64, origin: i64) -> Res<i64> {
        self.admit(Access::Any)?;
        if !(0..=2).contains(&origin) || (offset < 0 && origin == 0) {
            return Err(Fail::invalid());
        }
        sys::seek(self.fd, offset, origin).map_err(|e| self.fail("seek", e))
    }

    pub fn stat(&mut self) -> Res<Info> {
        self.admit(Access::Any)?;
        let st = sys::fstat(self.fd).map_err(|e| self.fail("stat", e))?;
        let name = path::base(&self.name);
        if core::str::from_utf8(&name).is_err() {
            return Err(Fail::status(STATUS_UNSUPPORTED));
        }
        Ok(ops::info_of(&st, &name))
    }

    pub fn truncate(&mut self, size: i64) -> Res<()> {
        self.admit(Access::Write)?;
        if size < 0 {
            return Err(Fail::invalid());
        }
        sys::ftruncate(self.fd, size).map_err(|e| self.fail("truncate", e))
    }

    pub fn sync(&mut self) -> Res<()> {
        self.admit(Access::Any)?;
        sys::fsync(self.fd).map_err(|e| self.fail("sync", e))
    }

    pub fn data_sync(&mut self) -> Res<()> {
        self.admit(Access::Any)?;
        sys::fdatasync(self.fd).map_err(|e| self.fail("sync", e))
    }

    pub fn chmod(&mut self, mode: i64) -> Res<()> {
        self.admit(Access::Any)?;
        if !(0..=0o7777).contains(&mode) {
            return Err(Fail::invalid());
        }
        sys::fchmod(self.fd, mode as u32).map_err(|e| self.fail("chmod", e))
    }

    pub fn chown(&mut self, uid: i64, gid: i64) -> Res<()> {
        self.admit(Access::Any)?;
        if uid < -1 || gid < -1 || uid > 2_147_483_647 || gid > 2_147_483_647 {
            return Err(Fail::invalid());
        }
        sys::fchown(self.fd, uid, gid).map_err(|e| self.fail("chown", e))
    }

    pub fn set_times(&mut self, accessed: (i64, i64), modified: (i64, i64)) -> Res<()> {
        self.admit(Access::Any)?;
        sys::futimens(self.fd, accessed, modified).map_err(|e| self.fail("chtimes", e))
    }

    /// `read_lines`: the remaining text split on `\n`, a trailing `\r` removed from each line.
    pub fn read_lines(&mut self, max_bytes: i64, max_lines: i64) -> Res<Vec<Vec<u8>>> {
        let data = self.read_file(max_bytes)?;
        if core::str::from_utf8(&data).is_err() {
            return Err(Fail::status(STATUS_INVALID_DATA));
        }
        let mut lines: Vec<&[u8]> = Vec::new();
        if !data.is_empty() {
            lines = data.split(|&c| c == b'\n').collect();
            if lines.last().is_some_and(|l| l.is_empty()) {
                lines.pop();
            }
            if lines.len() as i64 > max_lines {
                return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
            }
        }
        Ok(lines
            .into_iter()
            .map(|l| l.strip_suffix(b"\r").unwrap_or(l).to_vec())
            .collect())
    }
}

#[derive(PartialEq, Eq, Clone, Copy)]
enum Access {
    Any,
    Read,
    Write,
}

/// The size of a chunk read: `65536` by default, `InvalidInput` for a non-positive request.
fn chunk_size(max: Option<i64>) -> Res<usize> {
    match max {
        None => Ok(65536),
        Some(v) if v <= 0 => Err(Fail::status(STATUS_INVALID_INPUT)),
        Some(v) => Ok(v.min(65536) as usize),
    }
}

/// `pread` until the buffer is full or the file ends.
fn pread_full(fd: sys::Fd, buf: &mut [u8], offset: i64) -> Result<usize, i32> {
    let mut done = 0;
    while done < buf.len() {
        poll_cancel();
        match sys::pread(fd, &mut buf[done..], offset + done as i64)? {
            0 => break,
            n => done += n,
        }
    }
    Ok(done)
}

fn write_all_fd(fd: sys::Fd, mut data: &[u8]) -> Result<(), i32> {
    while !data.is_empty() {
        poll_cancel();
        let end = data.len().min(65536);
        match sys::write(fd, &data[..end]) {
            Ok(0) => return Err(sys::EIO),
            Ok(n) => data = &data[n..],
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn pwrite_all(fd: sys::Fd, data: &[u8], offset: i64) -> Result<(), i32> {
    let mut done = 0;
    while done < data.len() {
        poll_cancel();
        let end = (done + 65536).min(data.len());
        match sys::pwrite(fd, &data[done..end], offset + done as i64)? {
            0 => return Err(sys::EIO),
            n => done += n,
        }
    }
    Ok(())
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use ms_rt_abi::STATUS_NONE;

    fn scratch() -> Vec<u8> {
        let mut dir = ops::temporary_directory(b"msfs-file-").unwrap();
        dir.push(crate::path::SEP);
        dir.push(b'f');
        dir
    }

    #[test]
    fn modes_positions_and_views() {
        let f = scratch();
        let mut h = open(&f, flags_of_mode(b"w+").unwrap() as i64, 0o600).unwrap();
        h.write(b"line one\r\nline two\nlast").unwrap();
        assert_eq!(h.seek(0, 0).unwrap(), 0);
        // The line reader takes ahead; positional operations must still see the right offset.
        assert_eq!(h.read_line(None).unwrap().unwrap(), b"line one");
        assert_eq!(h.seek(0, 1).unwrap(), 10);
        assert_eq!(h.read_at(5, Some(3)).unwrap(), b"one");
        h.write_at(0, b"LINE").unwrap();
        assert_eq!(h.seek(0, 0).unwrap(), 0);
        assert_eq!(
            h.read_lines(i64::MAX, i64::MAX).unwrap(),
            [b"LINE one".to_vec(), b"line two".to_vec(), b"last".to_vec()]
        );
        assert_eq!(h.seek(0, 0).unwrap(), 0);
        assert_eq!(
            h.read_lines(i64::MAX, 2).unwrap_err().status,
            STATUS_LIMIT_EXCEEDED
        );
        assert_eq!(h.seek(-1, 0).unwrap_err().status, STATUS_INVALID_INPUT);
        assert_eq!(h.stat().unwrap().size, 23);
        h.truncate(4).unwrap();
        h.chmod(0o640).unwrap();
        h.sync().unwrap();
        h.data_sync().unwrap();
        h.set_times((1_000_000, 0), (2_000_000, 0)).unwrap();
        assert_eq!(h.stat().unwrap().modified, (2_000_000, 0));
        assert_eq!(h.stat().unwrap().permissions, 0o640);
        h.close().unwrap();
        assert_eq!(h.sync().unwrap_err().status, STATUS_CLOSED);

        let mut r = open(&f, sys::O_RDONLY as i64, 0).unwrap();
        assert_eq!(
            r.write(b"x").map_err(|e| e.status),
            Err(STATUS_INVALID_INPUT)
        );
        assert_eq!(r.truncate(0).unwrap_err().status, STATUS_INVALID_INPUT);
        assert_eq!(
            r.read_vectors(&[2, 5], -1).unwrap(),
            [b"LI".to_vec(), b"NE".to_vec()]
        );
        assert_eq!(r.read_vectors(&[2], 1).unwrap(), [b"IN".to_vec()]);
        assert_eq!(
            r.read_vectors(&[70000], -1).unwrap_err().status,
            STATUS_INVALID_INPUT
        );
        assert_eq!(r.read(None).unwrap(), None);
        let _ = STATUS_NONE;
        let mut w = open(&f, flags_of_mode(b"a").unwrap() as i64, 0o600).unwrap();
        assert_eq!(
            w.read(None).map_err(|e| e.status),
            Err(STATUS_INVALID_INPUT)
        );
        w.write_vectors(&[b"1", b"2"], -1).unwrap();
        assert_eq!(ops::read_file(&f, i64::MAX).unwrap(), b"LINE12");
        assert!(open(&f, -1, 0).is_err());
        assert!(flags_of_mode(b"rw").is_none());
        let _ = ops::remove(&path::dir(&f), true);
    }
}
