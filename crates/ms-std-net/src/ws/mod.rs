//! WebSocket runtime: handshake helpers, frame codec and the message socket.
//!
//! The Go implementation (`pkg/runtime/websocket.go` over gorilla/websocket) is the oracle.

pub mod frame;
pub mod handshake;
pub mod socket;
