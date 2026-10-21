//! `ms run --watch` and `ms test --watch`: rebuild after each saved change to the input, its
//! manifest or a module it loaded. A failed edit only reports diagnostics, and the previous
//! program keeps running until a replacement builds.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use ms_driver::Lower;
use ms_project::Overlay;

use super::tooling::{
    FileState, WATCH_INTERVAL, WATCH_SETTLE, absolute, analyze_with, file_state, watched_files,
};
use super::{RustBackend, TempDir, compile, testing};
use crate::backend::{BackendResult, Io, RunRequest, TestRequest};
use crate::process::{Stops, exit_code, interrupt};

/// A replaced program gets this long to finish cancellation and cleanup before it is killed.
const GRACE: Duration = Duration::from_secs(5);

/// The files whose change restarts the program, and their last seen state.
#[derive(Default)]
struct Files(BTreeMap<String, Option<FileState>>);

impl Files {
    /// The input, its manifest and every local module it loads, as of now.
    fn refresh(&mut self, input: &str) {
        let checked = analyze_with(input, &Overlay::new(), false, false);
        self.0 = watched_files(input, &checked)
            .into_iter()
            .chain(absolute(input))
            .map(|path| (path.clone(), file_state(&path)))
            .collect();
    }

    /// Whether any watched file changed since the last call.
    fn changed(&mut self) -> bool {
        let mut changed = false;
        for (path, previous) in &mut self.0 {
            let current = file_state(path);
            if current != *previous {
                *previous = current;
                changed = true;
            }
        }
        changed
    }
}

/// When the next rebuild is due, once edits have settled.
#[derive(Default)]
struct Settle {
    at: Option<Instant>,
    since: Option<Instant>,
}

impl Settle {
    fn touch(&mut self) {
        let now = Instant::now();
        self.since.get_or_insert(now);
        self.at = Some(now + WATCH_SETTLE);
    }

    /// The time the change that is due was first seen, once it has settled.
    fn due(&mut self) -> Option<Instant> {
        self.at.filter(|at| Instant::now() >= *at)?;
        self.at = None;
        self.since.take()
    }
}

struct Running {
    child: Child,
    executable: PathBuf,
}

impl Running {
    /// Interrupt the program and wait for its cleanup, killing it after the grace period.
    fn stop(mut self) {
        interrupt(&mut self.child);
        let deadline = Instant::now() + GRACE;
        while matches!(self.child.try_wait(), Ok(None)) {
            if Instant::now() >= deadline {
                let _ = self.child.kill();
                let _ = self.child.wait();
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let _ = std::fs::remove_file(&self.executable);
    }
}

pub(super) fn run<L: Lower>(
    backend: &RustBackend<L>,
    request: &RunRequest,
    io: &mut Io,
) -> BackendResult {
    let directory = match TempDir::create("manuscript-watch-") {
        Ok(directory) => directory,
        Err(error) => {
            let _ = writeln!(io.stderr, "{error}");
            return Ok(1);
        }
    };
    let stops = Stops::catch();
    let mut files = Files::default();
    let mut settle = Settle::default();
    let mut running: Option<Running> = None;
    let mut generation = 0;
    let mut reason = "started";
    let mut due = Some(Instant::now());
    loop {
        if let Some(since) = due.take() {
            files.refresh(&request.filename);
            generation += 1;
            let executable = directory.0.join(format!("program-{generation}"));
            match build(backend, request, &executable, io) {
                Ok(()) => {
                    if let Some(old) = running.take() {
                        old.stop();
                    }
                    let _ = io.stdout.flush();
                    match crate::process::spawn(Command::new(&executable).args(&request.arguments))
                    {
                        Ok(child) => {
                            let _ = writeln!(
                                io.stderr,
                                "ms: {reason} run in {} ms",
                                since.elapsed().as_millis()
                            );
                            running = Some(Running { child, executable });
                        }
                        Err(error) => {
                            let _ = writeln!(io.stderr, "{error}");
                        }
                    }
                }
                Err(()) => {
                    let _ = writeln!(io.stderr, "ms: waiting for changes");
                }
            }
            reason = "restarted";
        }
        std::thread::sleep(WATCH_INTERVAL);
        if stops.take().is_some() {
            if let Some(old) = running.take() {
                old.stop();
            }
            return Ok(130);
        }
        if let Some(program) = &mut running
            && let Ok(Some(status)) = program.child.try_wait()
        {
            let _ = writeln!(
                io.stderr,
                "ms: exited with status {}; waiting for changes",
                exit_code(status)
            );
            let _ = std::fs::remove_file(&program.executable);
            running = None;
        }
        if files.changed() {
            settle.touch();
        }
        due = settle.due();
    }
}

/// Compile and link `request.filename` into `executable`; diagnostics are reported.
fn build<L: Lower>(
    backend: &RustBackend<L>,
    request: &RunRequest,
    executable: &Path,
    io: &mut Io,
) -> Result<(), ()> {
    let mut compiled = match compile(backend, &request.filename, request.build_type, false) {
        Ok(compiled) => compiled,
        Err(failure) => {
            failure.report(io);
            return Err(());
        }
    };
    backend
        .link(&mut compiled, executable, request.build_type)
        .map_err(|message| {
            let _ = writeln!(io.stderr, "{message}");
        })
}

/// Run the tests again after each saved change; a failing run keeps watching.
pub(super) fn test<L: Lower>(
    backend: &RustBackend<L>,
    request: &TestRequest,
    io: &mut Io,
) -> BackendResult {
    let once = TestRequest {
        watch: false,
        ..request.clone()
    };
    let stops = Stops::catch();
    let mut files = Files::default();
    let mut settle = Settle::default();
    let mut due = true;
    loop {
        if due {
            files.refresh(&request.filename);
            let _ = testing::test(backend, &once, io);
            let _ = writeln!(io.stderr, "ms: waiting for changes");
            let _ = io.stdout.flush();
        }
        std::thread::sleep(WATCH_INTERVAL);
        if stops.take().is_some() {
            return Ok(130);
        }
        if files.changed() {
            settle.touch();
        }
        due = settle.due().is_some();
    }
}
