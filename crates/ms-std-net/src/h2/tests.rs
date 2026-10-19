use super::frame::*;
use super::hpack::Encoder;
use super::*;

fn h(n: &str, v: &str) -> Header {
    (n.as_bytes().to_vec(), v.as_bytes().to_vec())
}

fn get_request() -> Vec<Header> {
    vec![
        h(":method", "GET"),
        h(":scheme", "https"),
        h(":path", "/"),
        h(":authority", "example.com"),
    ]
}

fn post_request() -> Vec<Header> {
    let mut r = get_request();
    r[0] = h(":method", "POST");
    r
}

fn ok_response() -> Vec<Header> {
    vec![h(":status", "200"), h("content-type", "text/plain")]
}

/// Move bytes between the two endpoints until both are quiet and return the
/// events each side saw.
fn pump(client: &mut Connection, server: &mut Connection) -> (Vec<Event>, Vec<Event>) {
    let (mut cev, mut sev) = (Vec::new(), Vec::new());
    loop {
        let to_server = client.take_output();
        let to_client = server.take_output();
        if to_server.is_empty() && to_client.is_empty() {
            return (cev, sev);
        }
        if !to_server.is_empty() {
            sev.extend(server.feed(&to_server).unwrap());
        }
        if !to_client.is_empty() {
            cev.extend(client.feed(&to_client).unwrap());
        }
    }
}

fn pair(client: Settings, server: Settings) -> (Connection, Connection) {
    let mut c = Connection::client(client);
    let mut s = Connection::server(server);
    let (cev, sev) = pump(&mut c, &mut s);
    assert!(cev.contains(&Event::SettingsAcked));
    assert!(sev.contains(&Event::SettingsAcked));
    (c, s)
}

fn data_bytes(events: &[Event], want_id: StreamId) -> Vec<u8> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::Data { id, data, .. } if *id == want_id => Some(data.clone()),
            _ => None,
        })
        .flatten()
        .collect()
}

fn frames(mut bytes: &[u8]) -> Vec<Frame> {
    let mut out = Vec::new();
    while let Some((f, n)) = parse_frame(bytes, MAX_MAX_FRAME_SIZE).unwrap() {
        out.push(f);
        bytes = &bytes[n..];
    }
    assert!(bytes.is_empty(), "trailing partial frame");
    out
}

/// A server that has completed the handshake and receives hand-built frames.
fn raw_server() -> Connection {
    let mut s = Connection::server(Settings::default());
    let mut input = PREFACE.to_vec();
    write_settings(&mut input, &[]);
    s.feed(&input).unwrap();
    s.take_output();
    s
}

fn raw_client() -> Connection {
    let mut c = Connection::client(Settings::default());
    let mut input = Vec::new();
    write_settings(&mut input, &[]);
    c.feed(&input).unwrap();
    c.take_output();
    c
}

fn block(headers: &[Header]) -> Vec<u8> {
    let mut out = Vec::new();
    Encoder::new(4096, false).encode(headers, &mut out);
    out
}

fn headers_frame(id: u32, headers: &[Header], end_stream: bool) -> Vec<u8> {
    let mut out = Vec::new();
    write_header_block(&mut out, id, &block(headers), end_stream, 16384);
    out
}

#[test]
fn handshake_bytes() {
    let mut c = Connection::client(Settings::default());
    let out = c.take_output();
    assert!(out.starts_with(PREFACE));
    let f = frames(&out[PREFACE.len()..]);
    assert_eq!(
        f,
        [Frame::Settings {
            ack: false,
            params: vec![(SETTINGS_ENABLE_PUSH, 0)]
        }]
    );
    let mut s = Connection::server(Settings::default());
    assert_eq!(
        frames(&s.take_output()),
        [Frame::Settings {
            ack: false,
            params: vec![]
        }]
    );
}

#[test]
fn custom_settings_are_advertised() {
    let settings = Settings {
        max_concurrent_streams: Some(7),
        initial_window_size: 1 << 20,
        max_frame_size: 1 << 15,
        max_header_list_size: Some(10_000),
        header_table_size: 1024,
        connection_window: 1 << 20,
    };
    let mut s = Connection::server(settings);
    let f = frames(&s.take_output());
    assert_eq!(
        f[0],
        Frame::Settings {
            ack: false,
            params: vec![
                (SETTINGS_HEADER_TABLE_SIZE, 1024),
                (SETTINGS_MAX_CONCURRENT_STREAMS, 7),
                (SETTINGS_INITIAL_WINDOW_SIZE, 1 << 20),
                (SETTINGS_MAX_FRAME_SIZE, 1 << 15),
                (SETTINGS_MAX_HEADER_LIST_SIZE, 10_000),
            ]
        }
    );
    assert_eq!(
        f[1],
        Frame::WindowUpdate {
            id: 0,
            increment: (1 << 20) - 65_535
        }
    );
}

#[test]
fn simple_request_response() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(get_request(), true).unwrap();
    assert_eq!(id, 1);
    let (_, sev) = pump(&mut c, &mut s);
    assert_eq!(
        sev,
        [Event::Headers {
            id: 1,
            headers: get_request(),
            end_stream: true
        }]
    );
    s.send_response_headers(1, ok_response(), false).unwrap();
    assert_eq!(s.send_data(1, b"hello", true), 5);
    let (cev, _) = pump(&mut c, &mut s);
    assert_eq!(
        cev,
        [
            Event::Headers {
                id: 1,
                headers: ok_response(),
                end_stream: false
            },
            Event::Data {
                id: 1,
                data: b"hello".to_vec(),
                end_stream: true
            },
        ]
    );
    assert_eq!(c.open_streams(), 0);
    assert_eq!(s.open_streams(), 0);
    assert_eq!(c.open_stream(get_request(), true).unwrap(), 3);
}

#[test]
fn flow_control_exhaustion_and_window_updates() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    let body: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();

    // The first write is capped by the 65535-byte default windows.
    let sent = c.send_data(id, &body, true);
    assert_eq!(sent, 65_535);
    assert_eq!(c.window_available(id), 0);
    assert_eq!(c.send_data(id, &body[sent..], true), 0);
    let (_, sev) = pump(&mut c, &mut s);
    assert_eq!(data_bytes(&sev, id).len(), 65_535);

    // Nothing is released yet, so the sender stays blocked.
    assert_eq!(c.send_data(id, &body[sent..], true), 0);

    // Releasing opens both windows and the client sees WindowOpened.
    let mut received = data_bytes(&sev, id);
    let mut offset = sent;
    let mut rounds = 0;
    s.release(id, received.len());
    loop {
        let (cev, sev) = pump(&mut c, &mut s);
        received.extend(data_bytes(&sev, id));
        let opened = cev.iter().any(|e| matches!(e, Event::WindowOpened { .. }));
        if offset == body.len() {
            break;
        }
        assert!(opened || !sev.is_empty(), "stalled at {offset}");
        let n = c.send_data(id, &body[offset..], true);
        offset += n;
        // Consume what the server just received.
        s.release(id, data_bytes(&sev, id).len());
        rounds += 1;
        assert!(rounds < 20, "too many rounds");
    }
    let (_, sev) = pump(&mut c, &mut s);
    received.extend(data_bytes(&sev, id));
    assert_eq!(received.len(), body.len());
    assert_eq!(received, body);
    assert!(rounds >= 2, "window updates were required");
}

#[test]
fn flow_control_on_response_with_small_stream_window() {
    let small = Settings {
        initial_window_size: 1000,
        ..Settings::default()
    };
    let (mut c, mut s) = pair(small, Settings::default());
    let id = c.open_stream(get_request(), true).unwrap();
    pump(&mut c, &mut s);
    s.send_response_headers(id, ok_response(), false).unwrap();
    // The server learned the client's window of 1000 from SETTINGS.
    assert_eq!(s.window_available(id), 1000);
    let body = vec![7u8; 2500];
    let mut sent = s.send_data(id, &body, true);
    assert_eq!(sent, 1000);
    let mut got = Vec::new();
    while got.len() < body.len() {
        let (cev, _) = pump(&mut c, &mut s);
        let chunk = data_bytes(&cev, id);
        c.release(id, chunk.len());
        got.extend(chunk);
        let (_, _) = pump(&mut c, &mut s);
        sent += s.send_data(id, &body[sent..], true);
    }
    assert_eq!(got, body);
    let (cev, _) = pump(&mut c, &mut s);
    assert!(cev.is_empty());
    assert_eq!(c.open_streams(), 0);
}

#[test]
fn data_frames_respect_peer_max_frame_size() {
    let big = Settings {
        initial_window_size: 1 << 20,
        connection_window: 1 << 20,
        ..Settings::default()
    };
    let (mut c, mut s) = pair(big.clone(), big);
    let id = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    let sent = c.send_data(id, &vec![1u8; 40_000], true);
    assert_eq!(sent, 40_000);
    let f = frames(&c.take_output());
    let sizes: Vec<usize> = f
        .iter()
        .map(|f| match f {
            Frame::Data { data, .. } => data.len(),
            _ => 0,
        })
        .collect();
    assert_eq!(sizes, [16_384, 16_384, 7_232]);
}

#[test]
fn server_honors_raised_peer_frame_size() {
    let raised = Settings {
        max_frame_size: 1 << 17,
        initial_window_size: 1 << 20,
        connection_window: 1 << 20,
        ..Settings::default()
    };
    let (mut c, mut s) = pair(raised, Settings::default());
    let id = c.open_stream(get_request(), true).unwrap();
    pump(&mut c, &mut s);
    s.send_response_headers(id, ok_response(), false).unwrap();
    s.send_data(id, &vec![0u8; 60_000], false);
    let f = frames(&s.take_output());
    let data: Vec<_> = f
        .iter()
        .filter_map(|f| match f {
            Frame::Data { data, .. } => Some(data.len()),
            _ => None,
        })
        .collect();
    // 60000 fits in one frame once the client raised its max frame size, but
    // the server's window for the stream is only the default 65535 from
    // the client's initial window setting (1 MiB), so all of it goes.
    assert_eq!(data, [60_000]);
}

#[test]
fn peer_initial_window_change_adjusts_open_streams() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    assert_eq!(c.send_data(id, &vec![0u8; 65_535], false), 65_535);
    assert_eq!(c.window_available(id), 0);
    // Server raises its per-stream window mid-connection.
    let mut input = Vec::new();
    write_settings(&mut input, &[(SETTINGS_INITIAL_WINDOW_SIZE, 100_000)]);
    let ev = c.feed(&input).unwrap();
    // Stream window is +34465 but the connection window is still exhausted.
    assert_eq!(ev, [Event::WindowOpened { id }]);
    assert_eq!(c.window_available(id), 0);
    let mut wu = Vec::new();
    write_window_update(&mut wu, 0, 10_000);
    c.feed(&wu).unwrap();
    assert_eq!(c.window_available(id), 10_000);
    // Shrinking below zero is legal and blocks until updates catch up.
    let mut input = Vec::new();
    write_settings(&mut input, &[(SETTINGS_INITIAL_WINDOW_SIZE, 0)]);
    c.feed(&input).unwrap();
    assert_eq!(c.window_available(id), 0);
}

#[test]
fn rst_stream_both_directions() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    c.send_rst(id, error_code::CANCEL);
    let (_, sev) = pump(&mut c, &mut s);
    assert_eq!(
        sev,
        [Event::Reset {
            id,
            code: error_code::CANCEL
        }]
    );
    assert_eq!(c.open_streams(), 0);
    assert_eq!(s.open_streams(), 0);
    // The client ignores late frames for the stream it reset.
    let mut late = Vec::new();
    write_data(&mut late, id, b"late", false);
    assert!(c.feed(&late).unwrap().is_empty());
}

#[test]
fn reset_returns_unread_bytes_to_connection_window() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    c.send_data(id, &vec![0u8; 30_000], false);
    pump(&mut c, &mut s);
    s.send_rst(id, error_code::CANCEL);
    let out = s.take_output();
    assert!(frames(&out).contains(&Frame::WindowUpdate {
        id: 0,
        increment: 30_000
    }));
}

#[test]
fn ping_is_acked_and_reported() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    c.send_ping(*b"abcdefgh");
    let (cev, _) = pump(&mut c, &mut s);
    assert_eq!(cev, [Event::PingAck { data: *b"abcdefgh" }]);
}

#[test]
fn goaway_refuses_unprocessed_streams() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let a = c.open_stream(get_request(), true).unwrap();
    pump(&mut c, &mut s);
    let b = c.open_stream(get_request(), true).unwrap();
    // The server says it only processed stream `a` before b arrived.
    let mut bytes = Vec::new();
    write_goaway(&mut bytes, a, error_code::NO_ERROR, b"draining");
    let ev = c.feed(&bytes).unwrap();
    assert_eq!(
        ev,
        [
            Event::GoAway {
                last_stream_id: a,
                code: error_code::NO_ERROR,
                debug: b"draining".to_vec()
            },
            Event::Reset {
                id: b,
                code: error_code::REFUSED_STREAM
            },
        ]
    );
    assert!(c.open_stream(get_request(), true).is_err());
    assert_eq!(c.open_streams(), 1);
}

#[test]
fn server_shutdown_sends_goaway_and_ignores_new_streams() {
    let mut s = raw_server();
    s.feed(&headers_frame(1, &get_request(), true)).unwrap();
    s.shutdown(error_code::NO_ERROR);
    let f = frames(&s.take_output());
    assert_eq!(
        f,
        [Frame::GoAway {
            last_stream_id: 1,
            code: 0,
            debug: vec![]
        }]
    );
    let ev = s.feed(&headers_frame(3, &get_request(), true)).unwrap();
    assert!(ev.is_empty());
}

#[test]
fn continuation_and_padding_and_priority() {
    let mut s = raw_server();
    let b = block(&get_request());
    let (first, second) = b.split_at(5);
    let mut input = Vec::new();
    // PRIORITY for an idle stream is accepted and ignored.
    write_frame_header(&mut input, 5, TYPE_PRIORITY, 0, 1);
    input.extend_from_slice(&[0, 0, 0, 0, 10]);
    // HEADERS without END_HEADERS, padded, with priority fields.
    let mut payload = vec![3u8, 0, 0, 0, 0, 16];
    payload.extend_from_slice(first);
    payload.extend_from_slice(&[0, 0, 0]);
    write_frame_header(
        &mut input,
        payload.len(),
        TYPE_HEADERS,
        FLAG_PADDED | FLAG_PRIORITY | FLAG_END_STREAM,
        1,
    );
    input.extend_from_slice(&payload);
    // Split delivery to exercise buffering as well.
    let mut cont = Vec::new();
    write_frame_header(
        &mut cont,
        second.len(),
        TYPE_CONTINUATION,
        FLAG_END_HEADERS,
        1,
    );
    cont.extend_from_slice(second);
    assert!(s.feed(&input[..7]).unwrap().is_empty());
    let mut ev = s.feed(&input[7..]).unwrap();
    assert!(ev.is_empty());
    ev.extend(s.feed(&cont).unwrap());
    assert_eq!(
        ev,
        [Event::Headers {
            id: 1,
            headers: get_request(),
            end_stream: true
        }]
    );
}

#[test]
fn padded_data_is_released_automatically() {
    let mut s = raw_server();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    let mut input = Vec::new();
    // pad length 9 -> 10 octets of padding overhead, 4 data bytes.
    let mut payload = vec![9u8];
    payload.extend_from_slice(b"data");
    payload.extend_from_slice(&[0; 9]);
    write_frame_header(&mut input, payload.len(), TYPE_DATA, FLAG_PADDED, 1);
    input.extend_from_slice(&payload);
    let ev = s.feed(&input).unwrap();
    assert_eq!(
        ev,
        [Event::Data {
            id: 1,
            data: b"data".to_vec(),
            end_stream: false
        }]
    );
    let f = frames(&s.take_output());
    assert_eq!(
        f,
        [
            Frame::WindowUpdate {
                id: 0,
                increment: 10
            },
            Frame::WindowUpdate {
                id: 1,
                increment: 10
            },
        ]
    );
    // Only the 4 real bytes remain charged.
    s.release(1, 4);
    let f = frames(&s.take_output());
    assert_eq!(
        f,
        [
            Frame::WindowUpdate {
                id: 1,
                increment: 4
            },
            Frame::WindowUpdate {
                id: 0,
                increment: 4
            },
        ]
    );
}

#[test]
fn trailers_roundtrip() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    c.send_data(id, b"body", false);
    c.send_trailers(id, vec![h("x-checksum", "abc")]).unwrap();
    let (_, sev) = pump(&mut c, &mut s);
    assert_eq!(
        sev.last(),
        Some(&Event::Headers {
            id,
            headers: vec![h("x-checksum", "abc")],
            end_stream: true
        })
    );
    // Trailers without END_STREAM are a stream error.
    let id2 = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    let mut bad = headers_frame(id2, &[h("x", "y")], false);
    let ev = s.feed(&std::mem::take(&mut bad)).unwrap();
    assert_eq!(
        ev,
        [Event::Reset {
            id: id2,
            code: error_code::PROTOCOL_ERROR
        }]
    );
}

#[test]
fn interim_responses_are_delivered() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    s.send_response_headers(id, vec![h(":status", "100")], false)
        .unwrap();
    s.send_response_headers(id, ok_response(), true).unwrap();
    assert!(
        s.send_response_headers(id, ok_response(), true).is_err(),
        "stream is over"
    );
    let (cev, _) = pump(&mut c, &mut s);
    assert_eq!(cev.len(), 2);
    assert!(matches!(
        &cev[0],
        Event::Headers {
            end_stream: false,
            ..
        }
    ));
    assert!(matches!(
        &cev[1],
        Event::Headers {
            end_stream: true,
            ..
        }
    ));
}

#[test]
fn max_concurrent_streams_both_sides() {
    let server_settings = Settings {
        max_concurrent_streams: Some(1),
        ..Settings::default()
    };
    let (mut c, mut s) = pair(Settings::default(), server_settings);
    c.open_stream(post_request(), false).unwrap();
    let err = c.open_stream(post_request(), false).unwrap_err();
    assert_eq!(err.code, error_code::REFUSED_STREAM);
    assert!(!err.fatal);
    pump(&mut c, &mut s);

    // A misbehaving client that ignores the limit gets REFUSED_STREAM.
    let mut raw = raw_server_with(Settings {
        max_concurrent_streams: Some(1),
        ..Settings::default()
    });
    raw.feed(&headers_frame(1, &post_request(), false)).unwrap();
    raw.take_output();
    let ev = raw.feed(&headers_frame(3, &post_request(), false)).unwrap();
    assert!(ev.is_empty());
    assert_eq!(
        frames(&raw.take_output()),
        [Frame::RstStream {
            id: 3,
            code: error_code::REFUSED_STREAM
        }]
    );
    // Finishing the first stream frees a slot.
    raw.send_response_headers(1, ok_response(), true).unwrap();
    let mut end = Vec::new();
    write_data(&mut end, 1, b"", true);
    raw.feed(&end).unwrap();
    let ev = raw.feed(&headers_frame(5, &post_request(), false)).unwrap();
    assert_eq!(ev.len(), 1);
}

fn raw_server_with(settings: Settings) -> Connection {
    let mut s = Connection::server(settings);
    let mut input = PREFACE.to_vec();
    write_settings(&mut input, &[]);
    s.feed(&input).unwrap();
    s.take_output();
    s
}

#[test]
fn max_header_list_size_enforced() {
    let mut s = raw_server_with(Settings {
        max_header_list_size: Some(300),
        ..Settings::default()
    });
    let mut big = get_request();
    big.push(h("x-big", &"a".repeat(200)));
    let ev = s.feed(&headers_frame(1, &big, true)).unwrap();
    assert!(ev.is_empty());
    assert_eq!(
        frames(&s.take_output()),
        [Frame::RstStream {
            id: 1,
            code: error_code::ENHANCE_YOUR_CALM
        }]
    );
    // HPACK state stayed in sync: a later small request still decodes.
    let ev = s.feed(&headers_frame(3, &get_request(), true)).unwrap();
    assert_eq!(ev.len(), 1);

    // Outgoing blocks honor the peer's limit.
    let mut c = Connection::client(Settings::default());
    let mut input = Vec::new();
    write_settings(&mut input, &[(SETTINGS_MAX_HEADER_LIST_SIZE, 100)]);
    c.feed(&input).unwrap();
    let err = c.open_stream(big, true).unwrap_err();
    assert!(!err.fatal);
}

#[test]
fn hpack_state_shared_across_many_requests() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    for i in 0..50 {
        let mut req = get_request();
        req.push(h("x-request", &format!("value-{i}")));
        req.push(h("user-agent", "ms-test/1.0"));
        let id = c.open_stream(req.clone(), true).unwrap();
        let (_, sev) = pump(&mut c, &mut s);
        assert_eq!(
            sev,
            [Event::Headers {
                id,
                headers: req,
                end_stream: true
            }]
        );
        s.send_response_headers(id, ok_response(), true).unwrap();
        pump(&mut c, &mut s);
    }
}

#[test]
fn large_headers_use_continuation_frames() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let mut req = get_request();
    for i in 0..40 {
        // Random-looking values defeat both indexing and Huffman savings.
        let v: String = (0..900)
            .map(|j| char::from(b'!' + ((i * 31 + j * 17) % 90) as u8))
            .collect();
        req.push(h(&format!("x-h-{i}"), &v));
    }
    let id = c.open_stream(req.clone(), true).unwrap();
    let out = c.take_output();
    let kinds: Vec<u8> = {
        let mut v = Vec::new();
        let mut rest = &out[..];
        while let Some((f, n)) = parse_frame(rest, MAX_MAX_FRAME_SIZE).unwrap() {
            rest = &rest[n..];
            v.push(match f {
                Frame::Headers { .. } => 1,
                Frame::Continuation { .. } => 9,
                _ => 0,
            });
        }
        v
    };
    assert!(kinds.iter().filter(|&&k| k == 9).count() >= 1, "{kinds:?}");
    let ev = s.feed(&out).unwrap();
    assert_eq!(
        ev,
        [Event::Headers {
            id,
            headers: req,
            end_stream: true
        }]
    );
}

// ---------------------------------------------------------------------------
// Protocol errors
// ---------------------------------------------------------------------------

fn assert_goaway(conn: &mut Connection, code: u32) {
    let f = frames(&conn.take_output());
    let last = f.last().expect("output");
    assert!(
        matches!(last, Frame::GoAway { code: c, .. } if *c == code),
        "expected GOAWAY {code:#x}, got {f:?}"
    );
}

#[test]
fn bad_preface_is_rejected() {
    let mut s = Connection::server(Settings::default());
    s.take_output();
    let err = s.feed(b"GET / HTTP/1.1\r\nHost: x\r\n\r\n").unwrap_err();
    assert_eq!(err.code, error_code::PROTOCOL_ERROR);
    assert!(err.fatal);
    assert_goaway(&mut s, error_code::PROTOCOL_ERROR);
    // The failure is sticky.
    assert!(s.feed(b"anything").is_err());
    assert!(s.is_failed());
}

#[test]
fn bad_preface_detected_on_first_differing_byte() {
    let mut s = Connection::server(Settings::default());
    assert!(s.feed(b"PRI * HT").unwrap().is_empty());
    assert!(s.feed(b"TP/1.1").is_err());
}

#[test]
fn preface_delivered_in_pieces() {
    let mut s = Connection::server(Settings::default());
    let mut input = PREFACE.to_vec();
    write_settings(&mut input, &[]);
    for b in &input {
        s.feed(std::slice::from_ref(b)).unwrap();
    }
    let f = frames(&s.take_output());
    assert!(f.contains(&Frame::Settings {
        ack: true,
        params: vec![]
    }));
}

#[test]
fn first_frame_must_be_settings() {
    let mut s = Connection::server(Settings::default());
    let mut input = PREFACE.to_vec();
    write_ping(&mut input, false, [0; 8]);
    assert_eq!(s.feed(&input).unwrap_err().code, error_code::PROTOCOL_ERROR);
}

#[test]
fn stream_id_parity_and_ordering() {
    // Even stream id from a client.
    let mut s = raw_server();
    let err = s.feed(&headers_frame(2, &get_request(), true)).unwrap_err();
    assert_eq!(err.code, error_code::PROTOCOL_ERROR);
    assert_goaway(&mut s, error_code::PROTOCOL_ERROR);

    // Decreasing stream id.
    let mut s = raw_server();
    s.feed(&headers_frame(5, &get_request(), true)).unwrap();
    let err = s.feed(&headers_frame(3, &get_request(), true)).unwrap_err();
    assert_eq!(err.code, error_code::STREAM_CLOSED);

    // Server-initiated (even) stream seen by a client: push is disabled.
    let mut c = raw_client();
    let err = c
        .feed(&headers_frame(2, &[h(":status", "200")], false))
        .unwrap_err();
    assert_eq!(err.code, error_code::PROTOCOL_ERROR);

    // Response for a client stream that was never opened.
    let mut c = raw_client();
    let err = c
        .feed(&headers_frame(1, &[h(":status", "200")], true))
        .unwrap_err();
    assert_eq!(err.code, error_code::PROTOCOL_ERROR);
}

#[test]
fn oversize_frame_is_frame_size_error() {
    let mut s = raw_server();
    let mut input = Vec::new();
    write_frame_header(&mut input, 16_385, TYPE_DATA, 0, 1);
    let err = s.feed(&input).unwrap_err();
    assert_eq!(err.code, error_code::FRAME_SIZE_ERROR);
    assert_goaway(&mut s, error_code::FRAME_SIZE_ERROR);

    // A larger advertised limit is honored.
    let mut s = raw_server_with(Settings {
        max_frame_size: 100_000,
        ..Settings::default()
    });
    let mut input = Vec::new();
    write_frame_header(&mut input, 16_385, TYPE_PING, 0, 0);
    // Not a PING-sized payload, so this fails as a size error only after the
    // payload arrives; the header alone is accepted.
    assert!(s.feed(&input).unwrap().is_empty());
}

#[test]
fn data_beyond_windows_is_flow_control_error() {
    // Connection window: five 16384-byte frames exceed 65535.
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    pump(&mut c, &mut s);
    let mut input = Vec::new();
    for _ in 0..5 {
        write_data(&mut input, id, &[0; 16_384], false);
    }
    let err = s.feed(&input).unwrap_err();
    assert_eq!(err.code, error_code::FLOW_CONTROL_ERROR);
    assert_goaway(&mut s, error_code::FLOW_CONTROL_ERROR);

    // Stream window smaller than the connection window: stream error.
    let mut s = raw_server_with(Settings {
        initial_window_size: 100,
        connection_window: 1 << 20,
        ..Settings::default()
    });
    let mut ack = Vec::new();
    write_settings_ack(&mut ack);
    s.feed(&ack).unwrap();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    let mut input = Vec::new();
    write_data(&mut input, 1, &[0; 101], false);
    let ev = s.feed(&input).unwrap();
    assert_eq!(
        ev,
        [Event::Reset {
            id: 1,
            code: error_code::FLOW_CONTROL_ERROR
        }]
    );
    assert!(!s.is_failed());
}

#[test]
fn window_update_errors() {
    let mut s = raw_server();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    // Zero increment on the connection is fatal.
    let mut input = Vec::new();
    write_window_update(&mut input, 0, 0);
    assert_eq!(s.feed(&input).unwrap_err().code, error_code::PROTOCOL_ERROR);

    // Zero increment on a stream resets only that stream.
    let mut s = raw_server();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    let mut input = Vec::new();
    write_window_update(&mut input, 1, 0);
    assert_eq!(
        s.feed(&input).unwrap(),
        [Event::Reset {
            id: 1,
            code: error_code::PROTOCOL_ERROR
        }]
    );

    // Overflowing the connection window is fatal.
    let mut s = raw_server();
    let mut input = Vec::new();
    write_window_update(&mut input, 0, 0x7fff_ffff);
    assert_eq!(
        s.feed(&input).unwrap_err().code,
        error_code::FLOW_CONTROL_ERROR
    );

    // Overflowing a stream window resets the stream.
    let mut s = raw_server();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    let mut input = Vec::new();
    write_window_update(&mut input, 1, 0x7fff_ffff);
    assert_eq!(
        s.feed(&input).unwrap(),
        [Event::Reset {
            id: 1,
            code: error_code::FLOW_CONTROL_ERROR
        }]
    );

    // WINDOW_UPDATE on an idle stream is fatal.
    let mut s = raw_server();
    let mut input = Vec::new();
    write_window_update(&mut input, 9, 1);
    assert!(s.feed(&input).is_err());
}

#[test]
fn settings_value_errors() {
    for (key, value, code) in [
        (
            SETTINGS_INITIAL_WINDOW_SIZE,
            0x8000_0000,
            error_code::FLOW_CONTROL_ERROR,
        ),
        (SETTINGS_MAX_FRAME_SIZE, 100, error_code::PROTOCOL_ERROR),
        (SETTINGS_MAX_FRAME_SIZE, 1 << 24, error_code::PROTOCOL_ERROR),
        (SETTINGS_ENABLE_PUSH, 2, error_code::PROTOCOL_ERROR),
    ] {
        let mut s = Connection::server(Settings::default());
        let mut input = PREFACE.to_vec();
        write_settings(&mut input, &[(key, value)]);
        assert_eq!(s.feed(&input).unwrap_err().code, code, "{key}={value}");
    }
    // Unknown settings are ignored.
    let mut s = Connection::server(Settings::default());
    let mut input = PREFACE.to_vec();
    write_settings(&mut input, &[(0x99, 1)]);
    s.feed(&input).unwrap();
}

#[test]
fn push_promise_and_misplaced_frames_are_rejected() {
    let mut s = raw_server();
    let mut input = Vec::new();
    write_frame_header(&mut input, 4, TYPE_PUSH_PROMISE, FLAG_END_HEADERS, 1);
    input.extend_from_slice(&2u32.to_be_bytes());
    assert!(s.feed(&input).is_err());

    // CONTINUATION with no preceding HEADERS.
    let mut s = raw_server();
    let mut input = Vec::new();
    write_frame_header(&mut input, 0, TYPE_CONTINUATION, FLAG_END_HEADERS, 1);
    assert!(s.feed(&input).is_err());

    // Another frame in the middle of a header block.
    let mut s = raw_server();
    let b = block(&get_request());
    let mut input = Vec::new();
    write_frame_header(&mut input, b.len(), TYPE_HEADERS, 0, 1);
    input.extend_from_slice(&b);
    write_ping(&mut input, false, [0; 8]);
    assert_eq!(s.feed(&input).unwrap_err().code, error_code::PROTOCOL_ERROR);

    // CONTINUATION for a different stream.
    let mut s = raw_server();
    let mut input = Vec::new();
    write_frame_header(&mut input, b.len(), TYPE_HEADERS, 0, 1);
    input.extend_from_slice(&b);
    write_frame_header(&mut input, 0, TYPE_CONTINUATION, FLAG_END_HEADERS, 3);
    assert!(s.feed(&input).is_err());
}

#[test]
fn bad_hpack_is_compression_error() {
    let mut s = raw_server();
    let mut input = Vec::new();
    // Index 126 does not exist.
    write_frame_header(
        &mut input,
        1,
        TYPE_HEADERS,
        FLAG_END_HEADERS | FLAG_END_STREAM,
        1,
    );
    input.push(0xfe);
    assert_eq!(
        s.feed(&input).unwrap_err().code,
        error_code::COMPRESSION_ERROR
    );
}

#[test]
fn data_before_headers_and_after_end_are_stream_errors() {
    let mut s = raw_server();
    s.feed(&headers_frame(1, &get_request(), true)).unwrap();
    let mut input = Vec::new();
    write_data(&mut input, 1, b"x", false);
    // Stream 1 is half-closed (remote); the server has not answered, so the
    // stream still exists and rejects DATA.
    let ev = s.feed(&input).unwrap();
    assert_eq!(
        ev,
        [Event::Reset {
            id: 1,
            code: error_code::STREAM_CLOSED
        }]
    );

    // DATA on an idle stream is a connection error.
    let mut s = raw_server();
    let mut input = Vec::new();
    write_data(&mut input, 7, b"x", false);
    assert!(s.feed(&input).is_err());
}

#[test]
fn rst_stream_on_idle_stream_is_fatal() {
    let mut s = raw_server();
    let mut input = Vec::new();
    write_rst_stream(&mut input, 5, 0);
    assert!(s.feed(&input).is_err());
}

#[test]
fn invalid_requests_reset_the_stream() {
    let cases: Vec<(&str, Vec<Header>)> = vec![
        (
            "uppercase name",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("X-Upper", "1"),
            ],
        ),
        (
            "pseudo after regular",
            vec![
                h(":method", "GET"),
                h("x", "1"),
                h(":scheme", "https"),
                h(":path", "/"),
            ],
        ),
        (
            "connection header",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("connection", "close"),
            ],
        ),
        (
            "transfer-encoding",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("transfer-encoding", "chunked"),
            ],
        ),
        (
            "te not trailers",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("te", "gzip"),
            ],
        ),
        (
            "missing path",
            vec![h(":method", "GET"), h(":scheme", "https")],
        ),
        (
            "missing method",
            vec![h(":scheme", "https"), h(":path", "/")],
        ),
        ("missing scheme", vec![h(":method", "GET"), h(":path", "/")]),
        (
            "empty path",
            vec![h(":method", "GET"), h(":scheme", "https"), h(":path", "")],
        ),
        (
            "response pseudo in request",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h(":status", "200"),
            ],
        ),
        (
            "duplicate :path",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h(":path", "/x"),
            ],
        ),
        (
            "unknown pseudo",
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h(":bogus", "1"),
            ],
        ),
        (
            "CONNECT with path",
            vec![
                h(":method", "CONNECT"),
                h(":authority", "a:1"),
                h(":path", "/"),
            ],
        ),
        ("CONNECT without authority", vec![h(":method", "CONNECT")]),
    ];
    for (name, headers) in cases {
        let mut s = raw_server();
        let ev = s.feed(&headers_frame(1, &headers, false)).unwrap();
        assert!(ev.is_empty(), "{name}: surfaced");
        assert_eq!(
            frames(&s.take_output()),
            [Frame::RstStream {
                id: 1,
                code: error_code::PROTOCOL_ERROR
            }],
            "{name}"
        );
        assert!(!s.is_failed(), "{name}");
    }
}

#[test]
fn valid_connect_and_te_trailers_pass() {
    let mut s = raw_server();
    let connect = vec![h(":method", "CONNECT"), h(":authority", "proxy:443")];
    assert_eq!(s.feed(&headers_frame(1, &connect, false)).unwrap().len(), 1);
    let mut req = get_request();
    req.push(h("te", "trailers"));
    assert_eq!(s.feed(&headers_frame(3, &req, true)).unwrap().len(), 1);
}

#[test]
fn invalid_responses_reset_the_stream() {
    let cases: Vec<(&str, Vec<Header>)> = vec![
        ("missing status", vec![h("x", "1")]),
        ("bad status", vec![h(":status", "2000")]),
        ("request pseudo", vec![h(":status", "200"), h(":path", "/")]),
        (
            "connection",
            vec![h(":status", "200"), h("keep-alive", "1")],
        ),
        (
            "uppercase",
            vec![h(":status", "200"), h("Content-Type", "x")],
        ),
    ];
    for (name, headers) in cases {
        let (mut c, _s) = pair(Settings::default(), Settings::default());
        let id = c.open_stream(get_request(), true).unwrap();
        let ev = c.feed(&headers_frame(id, &headers, false)).unwrap();
        assert_eq!(
            ev,
            [Event::Reset {
                id,
                code: error_code::PROTOCOL_ERROR
            }],
            "{name}"
        );
    }
}

#[test]
fn outgoing_headers_are_validated() {
    let mut c = Connection::client(Settings::default());
    assert!(c.open_stream(vec![h(":method", "GET")], true).is_err());
    assert!(
        c.open_stream(
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("Bad-Case", "x"),
            ],
            true
        )
        .is_err()
    );
    assert!(
        c.open_stream(
            vec![
                h(":method", "GET"),
                h(":scheme", "https"),
                h(":path", "/"),
                h("x", "a\r\nb: c"),
            ],
            true
        )
        .is_err()
    );
    // Nothing was written for rejected requests beyond the handshake.
    let out = c.take_output();
    let f = frames(&out[PREFACE.len()..]);
    assert_eq!(f.len(), 1);
    // A server cannot open streams, a client cannot respond.
    let mut s = raw_server();
    assert!(s.open_stream(get_request(), true).is_err());
    let mut c = raw_client();
    assert!(c.send_response_headers(1, ok_response(), true).is_err());
}

#[test]
fn send_data_edge_cases() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    // Unknown stream.
    assert_eq!(c.send_data(99, b"x", false), 0);
    // Server before the response header block.
    let id = c.open_stream(get_request(), true).unwrap();
    pump(&mut c, &mut s);
    assert_eq!(s.send_data(id, b"x", false), 0);
    s.send_response_headers(id, ok_response(), false).unwrap();
    // Empty END_STREAM data frame needs no window.
    assert_eq!(s.send_data(id, b"", false), 0);
    assert_eq!(s.send_data(id, b"", true), 0);
    let (cev, _) = pump(&mut c, &mut s);
    assert_eq!(
        cev.last(),
        Some(&Event::Data {
            id,
            data: vec![],
            end_stream: true
        })
    );
    // The stream is finished, so more data is refused.
    assert_eq!(s.send_data(id, b"x", false), 0);
}

#[test]
fn end_stream_only_when_everything_was_accepted() {
    let (mut c, _s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    let body = vec![0u8; 70_000];
    let n = c.send_data(id, &body, true);
    assert_eq!(n, 65_535);
    let f = frames(&c.take_output());
    assert!(f.iter().all(|f| !matches!(
        f,
        Frame::Data {
            end_stream: true,
            ..
        }
    )));
}

#[test]
fn release_is_capped_and_credits_both_windows() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    c.send_data(id, &[0; 1000], false);
    pump(&mut c, &mut s);
    s.release(id, 1_000_000);
    let f = frames(&s.take_output());
    assert_eq!(
        f,
        [
            Frame::WindowUpdate {
                id,
                increment: 1000
            },
            Frame::WindowUpdate {
                id: 0,
                increment: 1000
            },
        ]
    );
    // Nothing left to release.
    s.release(id, 10);
    assert!(s.take_output().is_empty());
}

#[test]
fn release_after_remote_end_only_credits_connection() {
    let (mut c, mut s) = pair(Settings::default(), Settings::default());
    let id = c.open_stream(post_request(), false).unwrap();
    c.send_data(id, &[0; 500], true);
    pump(&mut c, &mut s);
    s.release(id, 500);
    let f = frames(&s.take_output());
    assert_eq!(
        f,
        [Frame::WindowUpdate {
            id: 0,
            increment: 500
        }]
    );
}

#[test]
fn local_settings_apply_after_ack() {
    // We advertise a small window; until the peer acks it may still send 65535.
    let mut s = Connection::server(Settings {
        initial_window_size: 100,
        ..Settings::default()
    });
    s.take_output();
    let mut input = PREFACE.to_vec();
    write_settings(&mut input, &[]);
    s.feed(&input).unwrap();
    s.feed(&headers_frame(1, &post_request(), false)).unwrap();
    let mut data = Vec::new();
    write_data(&mut data, 1, &[0; 5000], false);
    assert_eq!(s.feed(&data).unwrap().len(), 1);
    // After the ACK the window is 100 - 5000 (negative) so more data fails.
    let mut ack = Vec::new();
    write_settings_ack(&mut ack);
    assert_eq!(s.feed(&ack).unwrap(), [Event::SettingsAcked]);
    let mut more = Vec::new();
    write_data(&mut more, 1, &[0; 10], false);
    let ev = s.feed(&more).unwrap();
    assert_eq!(
        ev,
        [Event::Reset {
            id: 1,
            code: error_code::FLOW_CONTROL_ERROR
        }]
    );
}

#[test]
fn unknown_frame_types_are_skipped() {
    let mut s = raw_server();
    let mut input = Vec::new();
    write_frame_header(&mut input, 3, 0xfa, 0, 1);
    input.extend_from_slice(b"abc");
    assert!(s.feed(&input).unwrap().is_empty());
    assert!(!s.is_failed());
}

#[test]
fn full_exchange_with_bodies_and_trailers_both_ways() {
    let big = Settings {
        initial_window_size: 1 << 20,
        connection_window: 1 << 20,
        ..Settings::default()
    };
    let (mut c, mut s) = pair(big.clone(), big);
    let id = c.open_stream(post_request(), false).unwrap();
    assert_eq!(c.send_data(id, b"request-body", true), 12);
    let (_, sev) = pump(&mut c, &mut s);
    assert_eq!(data_bytes(&sev, id), b"request-body");
    s.release(id, 12);
    s.send_response_headers(id, ok_response(), false).unwrap();
    let body = vec![9u8; 300_000];
    assert_eq!(s.send_data(id, &body, false), 300_000);
    s.send_trailers(id, vec![h("x-done", "1")]).unwrap();
    let (cev, _) = pump(&mut c, &mut s);
    assert_eq!(data_bytes(&cev, id).len(), 300_000);
    assert!(matches!(
        cev.last(),
        Some(Event::Headers {
            end_stream: true,
            ..
        })
    ));
    c.release(id, 300_000);
    pump(&mut c, &mut s);
    assert_eq!(c.open_streams(), 0);
    assert_eq!(s.open_streams(), 0);
}
