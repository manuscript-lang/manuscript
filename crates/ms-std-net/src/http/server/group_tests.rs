//! The shared-listener bootstrap must work across independent runtime isolates.
use super::*;
use std::collections::{BTreeSet, VecDeque};
use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc,
};

struct Member {
    socket: socket2::Socket,
    stop: Arc<AtomicBool>,
    start: Arc<AtomicBool>,
    ready: mpsc::Sender<Result<(), String>>,
    name: &'static str,
}

static MEMBERS: Mutex<VecDeque<Member>> = Mutex::new(VecDeque::new());

struct RunningMembers {
    handles: Vec<u64>,
    stops: Vec<Arc<AtomicBool>>,
}
impl Drop for RunningMembers {
    fn drop(&mut self) {
        for stop in &self.stops {
            stop.store(true, Ordering::Release);
        }
        for handle in self.handles.drain(..) {
            // SAFETY: each remaining worker is owned by this guard and joined once.
            unsafe {
                ms_rt::worker::msrt_worker_join(handle, core::ptr::null_mut());
            }
        }
    }
}

struct Identity(&'static str);
impl Dispatch for Identity {
    fn buffered(&self, _: Request) -> Outcome<Reply> {
        Outcome::Done(Reply {
            status: 200,
            headers: Headers::new(),
            body: self.0.as_bytes().to_vec(),
        })
    }
    fn streaming(&self, _: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        Outcome::Done(Ok(()))
    }
}

unsafe extern "C-unwind" fn member_main(_: *mut u8) {
    let member = MEMBERS.lock().unwrap().pop_front().unwrap();
    let net = Network::new_root();
    let result = Server::prepare_on_listener(
        &net,
        member.socket,
        Box::new(Identity(member.name)),
        tests::opts(Limits::default()),
    );
    let server = match result {
        Ok(server) => server,
        Err(error) => {
            let _ = member.ready.send(Err(format!("{error:?}")));
            return;
        }
    };
    member.ready.send(Ok(())).unwrap();
    while !member.start.load(Ordering::Acquire) && !member.stop.load(Ordering::Acquire) {
        crate::wait::sleep(Duration::from_millis(1));
    }
    if !member.stop.load(Ordering::Acquire) {
        server.activate().unwrap();
    }
    while !member.stop.load(Ordering::Acquire) {
        crate::wait::sleep(Duration::from_millis(1));
    }
    server.close().unwrap();
}

#[test]
fn duplicated_listener_serves_across_isolates_and_survives_member_close() {
    serialize_tests();
    let net = Network::new_root();
    let listener = net.listen_tcp("127.0.0.1:0").unwrap();
    let address = crate::conn::socket_addr_text(&listener.local_addr().unwrap());
    let (ready, received) = mpsc::channel();
    let start = Arc::new(AtomicBool::new(false));
    let stops = [
        Arc::new(AtomicBool::new(false)),
        Arc::new(AtomicBool::new(false)),
    ];
    let mut running = RunningMembers {
        handles: Vec::new(),
        stops: stops.to_vec(),
    };
    for (index, stop) in stops.iter().enumerate() {
        MEMBERS.lock().unwrap().push_back(Member {
            socket: listener.try_clone().unwrap(),
            stop: stop.clone(),
            start: start.clone(),
            ready: ready.clone(),
            name: if index == 0 { "first" } else { "second" },
        });
        // SAFETY: the entry takes no argument; it constructs its own handles in its isolate.
        let handle =
            unsafe { ms_rt::worker::msrt_worker_spawn(member_main, core::ptr::null_mut(), 0) };
        assert_ne!(handle, 0);
        running.handles.push(handle);
        received
            .recv_timeout(Duration::from_secs(5))
            .unwrap()
            .unwrap();
    }
    // TCP may connect to the bound backlog before readiness, but no member may respond.
    use std::io::{Read, Write};
    let mut early = std::net::TcpStream::connect(&address).unwrap();
    early
        .set_read_timeout(Some(Duration::from_millis(30)))
        .unwrap();
    early
        .write_all(b"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        .unwrap();
    assert!(early.read(&mut [0u8; 1]).is_err());
    start.store(true, Ordering::Release);
    drop(early);
    let mut seen = BTreeSet::new();
    for _ in 0..128 {
        let response = tests::exchange(
            &address,
            b"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
        );
        if response.ends_with("first") {
            seen.insert("first");
        }
        if response.ends_with("second") {
            seen.insert("second");
        }
        if seen.len() == 2 {
            break;
        }
    }
    stops[0].store(true, Ordering::Release);
    assert_eq!(
        // SAFETY: this worker is collected exactly once; no fault report is needed.
        unsafe {
            ms_rt::worker::msrt_worker_join(running.handles.remove(0), core::ptr::null_mut())
        },
        0
    );
    let survivor = tests::exchange(
        &address,
        b"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
    );
    stops[1].store(true, Ordering::Release);
    assert_eq!(
        // SAFETY: as above, for the other worker.
        unsafe {
            ms_rt::worker::msrt_worker_join(running.handles.remove(0), core::ptr::null_mut())
        },
        0
    );
    assert_eq!(seen.len(), 2, "both isolates must execute whole handlers");
    assert!(survivor.ends_with("second"), "{survivor}");
}
