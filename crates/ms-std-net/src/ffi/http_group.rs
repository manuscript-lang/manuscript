//! Private source-library hooks for the scoped HTTP launcher.
use super::handler::Program;
use super::http_server::{HttpServerOptionsWire, server_options};
use super::{HttpGroupH, NetH, ServerH, report};
use crate::error::{HttpErr, NetErr};
use crate::http::group::launch::{Coordinator, Member};
use crate::http::server::Server;
use ms_rt::ffi::{ErrOut, Handler, ObjRef, Object, Out, StatusCode, abi_handle, native};

abi_handle!(Member);

native! {
    /// Binds the coordinator before source-owned control tasks start.
    fn msrt_http_group_new(
        net: ObjRef<NetH>, address: &str, runner: Handler, config: &str,
        processes: bool, has_count: bool, count: i64, cleanup_ns: i64,
        out: Out<Object<HttpGroupH>>, err: ErrOut,
    ) -> Result<(), StatusCode> {
        let count = if has_count { count } else {
            std::thread::available_parallelism().map_or(1, |n| n.get()) as i64
        };
        // SAFETY: the checker requires a named application; the source runner captures only it.
        let entry = unsafe { ms_rt::start::EntrySnapshot::capture(runner.as_ptr().cast()) };
        out.write(Object(HttpGroupH(report(Coordinator::new(&net, address, count, processes, entry, config.to_string(), cleanup_ns), &err)?)));
        Ok(())
    }
    /// Selected member count.
    fn msrt_http_group_count(group: ObjRef<HttpGroupH>) -> i64 { group.count() as i64 }
    /// Actual address, including the one selected for port zero.
    fn msrt_http_group_address(group: ObjRef<HttpGroupH>) -> String { group.address().to_string() }
    /// Starts one member without waiting for readiness.
    fn msrt_http_group_spawn(group: ObjRef<HttpGroupH>, index: i64, err: ErrOut) -> Result<(), StatusCode> {
        report(group.spawn(index as usize), &err)
    }
    /// Transfers the listener and immutable options to a started member.
    fn msrt_http_group_connect(group: ObjRef<HttpGroupH>, index: i64, err: ErrOut) -> Result<(), StatusCode> {
        report(group.connect(index as usize), &err)
    }
    /// Reads one bounded control frame.
    fn msrt_http_group_read(group: ObjRef<HttpGroupH>, index: i64, out: Out<Vec<u8>>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(report(group.read(index as usize), &err)?); Ok(())
    }
    /// Writes one bounded control frame.
    fn msrt_http_group_write(group: ObjRef<HttpGroupH>, index: i64, data: &[u8], err: ErrOut) -> Result<(), StatusCode> {
        report(group.write(index as usize, data), &err)
    }
    /// Enqueues a control event without blocking.
    fn msrt_http_group_post(group: ObjRef<HttpGroupH>, index: i64, kind: i64, err: ErrOut) -> Result<(), StatusCode> {
        report(group.post(index as usize, kind), &err)
    }
    /// Waits for an event, with the supervisor's remaining absolute budget.
    fn msrt_http_group_next(group: ObjRef<HttpGroupH>, timeout_ns: i64) -> i64 { group.next(timeout_ns) }
    /// Collects a normally completed member.
    fn msrt_http_group_join(group: ObjRef<HttpGroupH>, index: i64, timeout_ns: i64, err: ErrOut) -> Result<(), StatusCode> {
        report(group.join(index as usize, timeout_ns), &err)
    }
    /// Emergency rollback after control tasks have been cancelled and joined.
    fn msrt_http_group_close(group: ObjRef<HttpGroupH>) -> () { group.close(); }
    /// Stops members without invalidating endpoints still used by control tasks.
    fn msrt_http_group_abort(group: ObjRef<HttpGroupH>) -> () { group.abort(); }
    /// Takes the resources delivered to this member isolate/process.
    fn msrt_http_member_take(out: Out<Object<Member>>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(Object(report(Member::take(), &err)?)); Ok(())
    }
    /// Completes listener adoption before ordinary control reads.
    fn msrt_http_member_connect(member: ObjRef<Member>, err: ErrOut) -> Result<(), StatusCode> {
        report(member.connect(), &err)
    }
    /// Reads one bounded member control frame.
    fn msrt_http_member_read(member: ObjRef<Member>, out: Out<Vec<u8>>, err: ErrOut) -> Result<(), StatusCode> {
        out.write(report(member.bootstrap.read(), &err)?); Ok(())
    }
    /// Writes one bounded member control frame.
    fn msrt_http_member_write(member: ObjRef<Member>, data: &[u8], err: ErrOut) -> Result<(), StatusCode> {
        report(member.bootstrap.write(data), &err)
    }
    /// Stops the parent-death monitor before DONE or orderly scope completion.
    fn msrt_http_member_disarm(member: ObjRef<Member>) -> () { member.disarm(); }
    /// Closes the member control endpoint after its tasks join.
    fn msrt_http_member_close(member: ObjRef<Member>) -> () { member.close(); }
    /// Prepares a member-local streaming server without opening its readiness barrier.
    fn msrt_net_member_serve_stream(
        member: ObjRef<Member>, net: ObjRef<NetH>, env: Handler,
        opts: &HttpServerOptionsWire, out: Out<Object<ServerH>>, err: ErrOut,
    ) -> Result<(), StatusCode> {
        let listener = report(member.bootstrap.take_listener(), &err)?;
        let address = listener.local_addr().map(|a| crate::conn::socket_addr_text(&a))
            .map_err(|e| NetErr::failed(e.to_string())).map_err(HttpErr::from);
        let address = report(address, &err)?;
        let options = report(server_options(&net, &address, opts, true), &err)?;
        let server = Server::prepare_on_listener(&net, listener, Program::streaming(&env), options).map_err(HttpErr::from);
        out.write(Object(ServerH(report(server, &err)?))); Ok(())
    }
    /// Releases a prepared server after every group member has reported ready.
    fn msrt_http_server_activate(server: ObjRef<ServerH>, err: ErrOut) -> Result<(), StatusCode> {
        report(server.activate().map_err(HttpErr::from), &err)
    }
    /// Rejects a shutdown request from the server's own handler before side effects.
    fn msrt_http_server_check_close(server: ObjRef<ServerH>) -> () {
        if crate::http::server::Reactor::get().in_handler_of(&server) {
            ms_rt::ffi::fault("HTTP server cannot close from its own request");
        }
    }
}
