//! The seam between the socket layer and the HTTP server's reactor. Without the `http` feature
//! there is no server, so every hook is a no-op.

#[cfg(feature = "http")]
pub fn give_up_role() {
    crate::http::server::give_up_reactor_role();
}

#[cfg(not(feature = "http"))]
pub fn give_up_role() {}

#[cfg(all(test, feature = "http"))]
pub fn serialize_tests() {
    crate::http::server::serialize_tests();
}

#[cfg(all(test, not(feature = "http")))]
pub fn serialize_tests() {}

/// Whether a request handler of the server `net` owns is running on this thread.
pub fn in_handler_of_network(net: &crate::net::Network) -> bool {
    #[cfg(feature = "http")]
    {
        crate::http::server::Reactor::get().in_handler_of_network(net)
    }
    #[cfg(not(feature = "http"))]
    {
        let _ = net;
        false
    }
}
