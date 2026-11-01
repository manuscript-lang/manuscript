//! Natives for `@std/os/processes.ms`: start a child of this executable at a process entry, and
//! move bytes over its IPC pipe. Framing, encoding and the group live in Manuscript; these only
//! start the child and read and write the pipe.
use crate::command::{self, Subprocess};
use crate::ipc::{self, Link, Reader, Writer};
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};
use ms_rt::fault::with_cleanup;
use ms_rt::ffi::{
    Handler, ObjBox, ObjMut, ObjRef, ObjShare, Object, StatusCode, abi_handle, native,
};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::fs_status;
use ms_std_fs::stream::Stream;

/// One end of an IPC pipe. The halves are separate so a reading task and a writing task can use
/// the end at the same time. A second reader waits for the first (see [`IpcLink::wait_reader`]);
/// a second writer waits for the first the same way.
///
/// A task parked in a read or write can be cancelled, which leaves its frame with a jump and
/// skips destructors, so the halves are guarded by `busy` flags that a runtime cleanup entry
/// clears, not by `RefCell` borrows.
pub struct IpcLink {
    reader: RefCell<Option<Reader>>,
    writer: RefCell<Option<Writer>>,
    reading: Cell<bool>,
    writing: Cell<bool>,
    /// Tokens of tasks waiting for the current reader to finish.
    waiting: RefCell<Vec<i64>>,
    /// Tokens of tasks waiting for the current writer to finish.
    writers: RefCell<Vec<i64>>,
}

impl IpcLink {
    fn new(link: Link) -> Res<IpcLink> {
        let (reader, writer) = link.split()?;
        Ok(IpcLink {
            reader: RefCell::new(Some(reader)),
            writer: RefCell::new(Some(writer)),
            reading: Cell::new(false),
            writing: Cell::new(false),
            waiting: RefCell::new(Vec::new()),
            writers: RefCell::new(Vec::new()),
        })
    }

    fn end_write(&self) {
        self.writing.set(false);
        for token in self.writers.take() {
            ms_rt::channel::msrt_channel_post(token);
        }
    }

    fn end_read(&self) {
        self.reading.set(false);
        for token in self.waiting.take() {
            ms_rt::channel::msrt_channel_post(token);
        }
    }

    /// Parks while another task is reading, and returns true once it finished: the caller
    /// re-checks what that reader recorded. False at once when nobody is reading.
    fn wait_reader(&self) -> bool {
        if !self.reading.get() {
            return false;
        }
        let token = ms_rt::channel::msrt_channel_token();
        self.waiting.borrow_mut().push(token);
        ms_rt::channel::msrt_channel_park(token);
        true
    }

    #[allow(unsafe_code)]
    fn read(&self, max: i64) -> Vec<u8> {
        while self.wait_reader() {}
        self.reading.set(true);
        // SAFETY: `reading` admits one task, so nothing else holds the half; no borrow is kept
        // across the park.
        let Some(reader) = (unsafe { &mut *self.reader.as_ptr() }).as_mut() else {
            self.end_read();
            return Vec::new();
        };
        let mut buf = alloc::vec![0u8; max.clamp(1, 1 << 20) as usize];
        // A failed read means the other process is gone, the same as end of stream.
        let n = with_cleanup(&mut || self.end_read(), || reader.read(&mut buf)).unwrap_or(0);
        self.end_read();
        buf.truncate(n);
        buf
    }

    #[allow(unsafe_code)]
    fn write(&self, data: &[u8]) -> bool {
        while self.writing.get() {
            let token = ms_rt::channel::msrt_channel_token();
            self.writers.borrow_mut().push(token);
            ms_rt::channel::msrt_channel_park(token);
        }
        self.writing.set(true);
        // SAFETY: as `read`.
        let writer = unsafe { &mut *self.writer.as_ptr() };
        let ok = writer
            .as_mut()
            .is_some_and(|w| with_cleanup(&mut || self.end_write(), || w.write(data).is_ok()));
        self.end_write();
        ok
    }

    fn close(&self) {
        // A half in use by a parked task is left to that task; it ends when the pipe does.
        if !self.writing.get() {
            self.writer.borrow_mut().take();
        }
        if !self.reading.get() {
            self.reader.borrow_mut().take();
        }
    }
}

abi_handle!(IpcLink);

/// A child started at a process entry, with the parent's end of its IPC pipe and of its piped
/// standard streams (an unpiped one is already closed).
pub struct Forked {
    proc: Subprocess,
    link: ObjBox<IpcLink>,
    streams: [ObjBox<Stream>; 3],
}

abi_handle!(Forked);

fn start(runner: Handler, modes: [i64; 3]) -> Res<Forked> {
    let exe = std::env::current_exe().map_err(|_| Fail::status(ms_rt_abi::STATUS_UNAVAILABLE))?;
    // SAFETY: `ProcessGroup.spawn` passes a closure that captures only the entry function.
    #[allow(unsafe_code)]
    let entry = unsafe { ms_rt::start::entry_value(runner.as_ptr().cast()) };
    let (link, end) = ipc::pair()?;
    let mut p: Subprocess = command::spawn_with(
        exe.as_os_str().as_encoded_bytes(),
        &[],
        modes,
        Some(&end),
        &[(ms_rt::start::ENTRY_ENV, entry.as_bytes())],
    )?;
    // The parent's copy of the child's end closes here, so the parent sees the child's exit.
    drop(end);
    let streams = [
        ObjBox::new(crate::parent_end(&mut p.stdin, b"|1")),
        ObjBox::new(crate::parent_end(&mut p.stdout, b"|0")),
        ObjBox::new(crate::parent_end(&mut p.stderr, b"|0")),
    ];
    Ok(Forked {
        proc: p,
        link: ObjBox::new(IpcLink::new(link)?),
        streams,
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

    /// The child's piped standard input; closed unless spawned with `Stdio.Pipe`.
    fn msstd_process_forked_stdin(h: ObjRef<Forked>) -> ObjShare<Stream> {
        h.streams[0].share()
    }

    /// The child's piped standard output (`which` 1) or error (2); closed unless piped.
    fn msstd_process_forked_output(h: ObjRef<Forked>, which: i64) -> ObjShare<Stream> {
        h.streams[which.clamp(1, 2) as usize].share()
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
        for s in &mut h.streams {
            let _ = s.get_mut().close();
        }
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

    /// Parks while another task reads this end, then returns true so the caller can look at what
    /// that reader recorded; false at once when no task is reading.
    fn msstd_process_ipc_wait_reader(h: ObjRef<IpcLink>) -> bool {
        h.wait_reader()
    }

    /// Closes this end: the other process reads what was sent, then end of stream. Idempotent.
    fn msstd_process_ipc_close(h: ObjRef<IpcLink>) -> () {
        h.close()
    }
}
