//! Natives for `@std/processes.ms`: start a child of this executable at a process entry, and
//! move bytes over its IPC pipe. Framing, encoding and the group live in Manuscript; these only
//! start the child and read and write the pipe.
use crate::command::{self, Subprocess};
use crate::ipc::{self, Link, Reader, Writer};
use alloc::vec::Vec;
use core::cell::RefCell;
use ms_rt::ffi::{
    Handler, ObjBox, ObjMut, ObjRef, ObjShare, Object, StatusCode, abi_handle, native,
};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::fs_status;

/// One end of an IPC pipe. The halves are separate so a reading task and a writing task can use
/// the end at the same time; a second reader (or writer) at once faults.
pub struct IpcLink {
    reader: RefCell<Option<Reader>>,
    writer: RefCell<Option<Writer>>,
}

impl IpcLink {
    fn new(link: Link) -> Res<IpcLink> {
        let (reader, writer) = link.split()?;
        Ok(IpcLink {
            reader: RefCell::new(Some(reader)),
            writer: RefCell::new(Some(writer)),
        })
    }

    fn read(&self, max: i64) -> Vec<u8> {
        let Ok(mut reader) = self.reader.try_borrow_mut() else {
            ms_rt::ffi::fault("another task is already reading this process channel");
        };
        let Some(reader) = reader.as_mut() else {
            return Vec::new();
        };
        let mut buf = alloc::vec![0u8; max.clamp(1, 1 << 20) as usize];
        // A failed read means the other process is gone, the same as end of stream.
        let n = reader.read(&mut buf).unwrap_or(0);
        buf.truncate(n);
        buf
    }

    fn write(&self, data: &[u8]) -> bool {
        let Ok(mut writer) = self.writer.try_borrow_mut() else {
            ms_rt::ffi::fault("another task is already writing this process channel");
        };
        writer.as_mut().is_some_and(|w| w.write(data).is_ok())
    }

    fn close(&self) {
        if let Ok(mut w) = self.writer.try_borrow_mut() {
            w.take();
        }
        if let Ok(mut r) = self.reader.try_borrow_mut() {
            r.take();
        }
    }
}

abi_handle!(IpcLink);

/// A child started at a process entry, with the parent's end of its IPC pipe.
pub struct Forked {
    proc: Subprocess,
    link: ObjBox<IpcLink>,
}

abi_handle!(Forked);

fn start(runner: Handler, modes: [i64; 3]) -> Res<Forked> {
    // The child's own streams are the parent's or the null device; piping them is not offered yet.
    if modes.contains(&command::STDIO_PIPE) {
        return Err(Fail::invalid());
    }
    let exe = std::env::current_exe().map_err(|_| Fail::status(ms_rt_abi::STATUS_UNAVAILABLE))?;
    // SAFETY: `ProcessGroup.spawn` passes a closure that captures only the entry function.
    #[allow(unsafe_code)]
    let entry = unsafe { ms_rt::start::entry_value(runner.as_ptr().cast()) };
    let (link, end) = ipc::pair()?;
    let p: Subprocess = command::spawn_with(
        exe.as_os_str().as_encoded_bytes(),
        &[],
        modes,
        Some(&end),
        &[(ms_rt::start::ENTRY_ENV, entry.as_bytes())],
    )?;
    // The parent's copy of the child's end closes here, so the parent sees the child's exit.
    drop(end);
    Ok(Forked {
        proc: p,
        link: ObjBox::new(IpcLink::new(link)?),
    })
}

native! {
    /// Starts this executable again at the entry `runner` captures; `stdin`, `stdout`, `stderr`
    /// are `Stdio` case indexes.
    fn msstd_process_fork(
        runner: Handler,
        stdin: i64,
        stdout: i64,
        stderr: i64,
    ) -> Result<Object<Forked>, StatusCode> {
        fs_status(start(runner, [stdin, stdout, stderr])).map(Object)
    }

    /// The parent's end of the child's IPC pipe.
    fn msstd_process_forked_link(h: ObjRef<Forked>) -> ObjShare<IpcLink> {
        h.link.share()
    }

    /// Waits for exit; a negative `timeout_ns` waits without limit. `Timeout` leaves the child running.
    fn msstd_process_forked_wait(h: ObjMut<Forked>, timeout_ns: i64) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.proc.wait((timeout_ns >= 0).then_some(timeout_ns)))
    }

    /// Signals the child's process group: SIGTERM, or SIGKILL with `force`.
    fn msstd_process_forked_signal(h: ObjMut<Forked>, force: bool) -> () {
        let mut h = h;
        h.proc.child.signal(force)
    }

    /// Closes the pipe, kills the group, joins the child and closes its streams. Idempotent.
    fn msstd_process_forked_close(h: ObjMut<Forked>) -> () {
        let mut h = h;
        h.link.get_mut().close();
        h.proc.stop();
    }

    /// The child's end of its IPC pipe; faults outside a child started at a process entry.
    fn msstd_process_ipc_child() -> Object<IpcLink> {
        // SAFETY: called once from the entry runner, before user code reads the environment.
        #[allow(unsafe_code)]
        unsafe {
            std::env::remove_var(ms_rt::start::ENTRY_ENV)
        };
        match Link::adopt().and_then(|l| l.map(IpcLink::new).transpose()) {
            Ok(Some(link)) => Object(link),
            _ => ms_rt::ffi::fault("this process was not started at a process entry"),
        }
    }

    /// Up to `max` bytes, waiting until some arrive; empty once the other process closed its end
    /// or is gone.
    fn msstd_process_ipc_read(h: ObjRef<IpcLink>, max: i64) -> out Vec<u8> {
        h.read(max)
    }

    /// Writes all of `data`, waiting while the pipe is full; false once the other process is gone.
    fn msstd_process_ipc_write(h: ObjRef<IpcLink>, data: &[u8]) -> bool {
        h.write(data)
    }

    /// Closes this end: the other process reads what was sent, then end of stream. Idempotent.
    fn msstd_process_ipc_close(h: ObjRef<IpcLink>) -> () {
        h.close()
    }
}
