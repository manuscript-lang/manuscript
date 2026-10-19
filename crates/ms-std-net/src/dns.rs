//! A small DNS client for the record kinds the system resolver does not expose
//! (`CNAME`, `MX`, `NS`, `TXT`, `PTR`, `SRV`) and for networks with an explicit
//! resolver (`with_resolver`).

use crate::error::{NetErr, cannot_resolve};
use crate::ip::ip_text;
use crate::rt;
use crate::sys::AsSock;
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, UdpSocket};
use std::time::Duration;

pub const TYPE_A: u16 = 1;
pub const TYPE_NS: u16 = 2;
pub const TYPE_CNAME: u16 = 5;
pub const TYPE_PTR: u16 = 12;
pub const TYPE_MX: u16 = 15;
pub const TYPE_TXT: u16 = 16;
pub const TYPE_AAAA: u16 = 28;
pub const TYPE_SRV: u16 = 33;

/// One answer record, reduced to what `DnsRecord` exposes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Record {
    pub rtype: u16,
    pub value: String,
    pub priority: i64,
    pub weight: i64,
    pub port: i64,
}

/// Outcome of a query.
#[derive(Debug, PartialEq, Eq)]
pub enum Reply {
    Records(Vec<Record>),
    /// The name does not exist or has no data of the type.
    NotFound,
}

fn encode_name(name: &str, out: &mut Vec<u8>) -> Result<(), NetErr> {
    let name = name.strip_suffix('.').unwrap_or(name);
    if name.len() > 253 {
        return Err(NetErr::InvalidInput);
    }
    if !name.is_empty() {
        for label in name.split('.') {
            if label.is_empty() || label.len() > 63 {
                return Err(NetErr::InvalidInput);
            }
            out.push(label.len() as u8);
            out.extend_from_slice(label.as_bytes());
        }
    }
    out.push(0);
    Ok(())
}

/// Builds a recursive query for `name` of `qtype`.
pub fn build_query(id: u16, name: &str, qtype: u16) -> Result<Vec<u8>, NetErr> {
    let mut q = Vec::with_capacity(32 + name.len());
    q.extend_from_slice(&id.to_be_bytes());
    q.extend_from_slice(&[0x01, 0x00]); // RD
    q.extend_from_slice(&[0, 1, 0, 0, 0, 0, 0, 0]);
    encode_name(name, &mut q)?;
    q.extend_from_slice(&qtype.to_be_bytes());
    q.extend_from_slice(&1u16.to_be_bytes());
    Ok(q)
}

fn read_name(msg: &[u8], mut at: usize) -> Option<(String, usize)> {
    let mut out = String::new();
    let mut end = None;
    let mut hops = 0;
    loop {
        let len = *msg.get(at)? as usize;
        if len == 0 {
            at += 1;
            break;
        }
        if len & 0xC0 == 0xC0 {
            let low = *msg.get(at + 1)? as usize;
            if end.is_none() {
                end = Some(at + 2);
            }
            at = ((len & 0x3F) << 8) | low;
            hops += 1;
            if hops > 32 {
                return None;
            }
            continue;
        }
        if len & 0xC0 != 0 {
            return None;
        }
        let label = msg.get(at + 1..at + 1 + len)?;
        out.push_str(&String::from_utf8_lossy(label));
        out.push('.');
        at += 1 + len;
    }
    if out.is_empty() {
        out.push('.');
    }
    Some((out, end.unwrap_or(at)))
}

/// Parsed response header and answers.
#[derive(Debug)]
pub struct Response {
    pub id: u16,
    pub truncated: bool,
    pub rcode: u8,
    pub answers: Vec<Record>,
}

/// Parses a response message.
pub fn parse_response(msg: &[u8]) -> Option<Response> {
    if msg.len() < 12 {
        return None;
    }
    let id = u16::from_be_bytes([msg[0], msg[1]]);
    let flags = u16::from_be_bytes([msg[2], msg[3]]);
    if flags & 0x8000 == 0 {
        return None;
    }
    let qd = u16::from_be_bytes([msg[4], msg[5]]) as usize;
    let an = u16::from_be_bytes([msg[6], msg[7]]) as usize;
    let mut at = 12;
    for _ in 0..qd {
        let (_, next) = read_name(msg, at)?;
        at = next + 4;
    }
    let mut answers = Vec::new();
    for _ in 0..an {
        let (_, next) = read_name(msg, at)?;
        let rtype = u16::from_be_bytes([*msg.get(next)?, *msg.get(next + 1)?]);
        let rdlen = u16::from_be_bytes([*msg.get(next + 8)?, *msg.get(next + 9)?]) as usize;
        let data = next + 10;
        let rdata = msg.get(data..data + rdlen)?;
        at = data + rdlen;
        let rec = |value: String| Record {
            rtype,
            value,
            priority: 0,
            weight: 0,
            port: 0,
        };
        match rtype {
            TYPE_A if rdlen == 4 => {
                let ip = IpAddr::from([rdata[0], rdata[1], rdata[2], rdata[3]]);
                answers.push(rec(ip_text(&ip)));
            }
            TYPE_AAAA if rdlen == 16 => {
                let mut b = [0u8; 16];
                b.copy_from_slice(rdata);
                answers.push(rec(ip_text(&IpAddr::from(b))));
            }
            TYPE_NS | TYPE_CNAME | TYPE_PTR => {
                let (name, _) = read_name(msg, data)?;
                answers.push(rec(name));
            }
            TYPE_MX if rdlen >= 3 => {
                let (name, _) = read_name(msg, data + 2)?;
                let mut r = rec(name);
                r.priority = u16::from_be_bytes([rdata[0], rdata[1]]) as i64;
                answers.push(r);
            }
            TYPE_SRV if rdlen >= 7 => {
                let (name, _) = read_name(msg, data + 6)?;
                let mut r = rec(name);
                r.priority = u16::from_be_bytes([rdata[0], rdata[1]]) as i64;
                r.weight = u16::from_be_bytes([rdata[2], rdata[3]]) as i64;
                r.port = u16::from_be_bytes([rdata[4], rdata[5]]) as i64;
                answers.push(r);
            }
            TYPE_TXT => {
                let mut text = Vec::new();
                let mut i = 0;
                while i < rdata.len() {
                    let n = rdata[i] as usize;
                    text.extend_from_slice(rdata.get(i + 1..i + 1 + n)?);
                    i += 1 + n;
                }
                answers.push(rec(String::from_utf8_lossy(&text).into_owned()));
            }
            _ => {}
        }
    }
    Some(Response {
        id,
        truncated: flags & 0x0200 != 0,
        rcode: (flags & 0xF) as u8,
        answers,
    })
}

fn query_id() -> u16 {
    use std::hash::{BuildHasher, Hasher};
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u64(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos() as u64),
    );
    h.finish() as u16
}

fn io_failed(e: std::io::Error) -> NetErr {
    NetErr::Failed(crate::error::describe_io_error(&e))
}

fn query_udp(
    server: SocketAddr,
    query: &[u8],
    id: u16,
    deadline: Deadline,
) -> Result<Vec<u8>, NetErr> {
    let bind: SocketAddr = if server.is_ipv4() {
        "0.0.0.0:0"
    } else {
        "[::]:0"
    }
    .parse()
    .expect("bind address");
    let sock = UdpSocket::bind(bind).map_err(io_failed)?;
    sock.set_nonblocking(true).map_err(io_failed)?;
    crate::sys::prepare_udp(&sock).map_err(io_failed)?;
    sock.send_to(query, server).map_err(io_failed)?;
    let mut buf = vec![0u8; 4096];
    loop {
        match sock.recv_from(&mut buf) {
            Ok((n, from)) => {
                if from.ip() == server.ip() && n >= 2 && u16::from_be_bytes([buf[0], buf[1]]) == id
                {
                    buf.truncate(n);
                    return Ok(buf);
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if wait_fd(sock.as_sock(), Interest::Read, deadline) == Wait::TimedOut {
                    return Err(NetErr::Timeout);
                }
            }
            Err(e) => return Err(io_failed(e)),
        }
    }
}

fn query_tcp(server: SocketAddr, query: &[u8], deadline: Deadline) -> Result<Vec<u8>, NetErr> {
    // DNS over TCP is rare (truncated answers); a bounded blocking exchange is enough.
    let timeout = deadline
        .remaining()
        .unwrap_or(Duration::from_secs(5))
        .max(Duration::from_millis(1));
    let mut stream = TcpStream::connect_timeout(&server, timeout).map_err(io_failed)?;
    stream.set_read_timeout(Some(timeout)).map_err(io_failed)?;
    stream.set_write_timeout(Some(timeout)).map_err(io_failed)?;
    let mut framed = (query.len() as u16).to_be_bytes().to_vec();
    framed.extend_from_slice(query);
    stream.write_all(&framed).map_err(io_failed)?;
    let mut len = [0u8; 2];
    stream.read_exact(&mut len).map_err(io_failed)?;
    let mut msg = vec![0u8; u16::from_be_bytes(len) as usize];
    stream.read_exact(&mut msg).map_err(io_failed)?;
    Ok(msg)
}

/// Sends one query to `server` and interprets the answer.
pub fn query(
    server: SocketAddr,
    name: &str,
    qtype: u16,
    deadline: Deadline,
) -> Result<Reply, NetErr> {
    rt::check_cancel();
    let id = query_id();
    let packet = build_query(id, name, qtype)?;
    let mut raw = query_udp(server, &packet, id, deadline)?;
    let mut response =
        parse_response(&raw).ok_or_else(|| NetErr::failed("malformed DNS response"))?;
    if response.truncated {
        raw = query_tcp(server, &packet, deadline)?;
        response = parse_response(&raw).ok_or_else(|| NetErr::failed("malformed DNS response"))?;
    }
    match response.rcode {
        0 => {}
        3 => return Ok(Reply::NotFound),
        _ => return Err(NetErr::failed(cannot_resolve(name))),
    }
    let wanted: Vec<Record> = response
        .answers
        .into_iter()
        .filter(|r| r.rtype == qtype || (qtype == TYPE_CNAME && r.rtype == TYPE_CNAME))
        .collect();
    if wanted.is_empty() {
        return Ok(Reply::NotFound);
    }
    Ok(Reply::Records(wanted))
}

/// The resolver configuration of the host: `/etc/resolv.conf` on Unix, the DNS servers
/// and suffixes of the operational network adapters on Windows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostConfig {
    pub servers: Vec<SocketAddr>,
    pub search: Vec<String>,
    pub ndots: usize,
}

impl HostConfig {
    pub fn parse(text: &str) -> HostConfig {
        let mut servers = Vec::new();
        let mut search = Vec::new();
        let mut ndots = 1;
        for line in text.lines() {
            let line = line.split(['#', ';']).next().unwrap_or("").trim();
            let mut words = line.split_whitespace();
            match words.next() {
                Some("nameserver") => {
                    if let Some(ip) = words.next().and_then(|w| w.parse::<IpAddr>().ok()) {
                        servers.push(SocketAddr::new(ip, 53));
                    }
                }
                Some("search") => {
                    search = words.map(|w| w.trim_end_matches('.').to_string()).collect()
                }
                Some("domain") => {
                    if search.is_empty() {
                        search = words
                            .take(1)
                            .map(|w| w.trim_end_matches('.').to_string())
                            .collect();
                    }
                }
                Some("options") => {
                    for w in words {
                        if let Some(n) = w
                            .strip_prefix("ndots:")
                            .and_then(|n| n.parse::<usize>().ok())
                        {
                            ndots = n.min(15);
                        }
                    }
                }
                _ => {}
            }
        }
        if servers.is_empty() {
            servers = HostConfig::default_servers();
        }
        HostConfig {
            servers,
            search,
            ndots,
        }
    }

    #[cfg(unix)]
    pub fn load() -> HostConfig {
        HostConfig::parse(&std::fs::read_to_string("/etc/resolv.conf").unwrap_or_default())
    }

    #[cfg(windows)]
    pub fn load() -> HostConfig {
        let (servers, search) = crate::sys::adapter_dns();
        let mut servers: Vec<SocketAddr> = servers
            .into_iter()
            .map(|ip| SocketAddr::new(ip, 53))
            .collect();
        if servers.is_empty() {
            servers = HostConfig::default_servers();
        }
        HostConfig {
            servers,
            search,
            ndots: 1,
        }
    }

    fn default_servers() -> Vec<SocketAddr> {
        vec![
            "127.0.0.1:53".parse().expect("addr"),
            "[::1]:53".parse().expect("addr"),
        ]
    }

    /// Names to try for `name`: absolute names are exact; others follow the search list.
    pub fn candidates(&self, name: &str) -> Vec<String> {
        if name.ends_with('.') {
            return vec![name.to_string()];
        }
        let dots = name.matches('.').count();
        let absolute = format!("{name}.");
        let searched = self.search.iter().map(|s| format!("{name}.{s}."));
        if dots >= self.ndots {
            std::iter::once(absolute).chain(searched).collect()
        } else {
            searched.chain(std::iter::once(absolute)).collect()
        }
    }
}

/// Reverse-lookup name of an address (`4.3.2.1.in-addr.arpa.`).
pub fn reverse_name(ip: &IpAddr) -> String {
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            format!("{}.{}.{}.{}.in-addr.arpa.", o[3], o[2], o[1], o[0])
        }
        IpAddr::V6(v6) => {
            let mut s = String::new();
            for b in v6.octets().iter().rev() {
                s.push_str(&format!("{:x}.{:x}.", b & 0xF, b >> 4));
            }
            s.push_str("ip6.arpa.");
            s
        }
    }
}

/// Tries `servers` in order, and `candidates` in order, returning the first answer.
pub fn lookup(
    servers: &[SocketAddr],
    candidates: &[String],
    qtype: u16,
    deadline: Deadline,
    original: &str,
) -> Result<Vec<Record>, NetErr> {
    let mut last = NetErr::failed(cannot_resolve(original));
    for name in candidates {
        let mut answered = false;
        for server in servers {
            match query(*server, name, qtype, deadline) {
                Ok(Reply::Records(r)) => return Ok(r),
                Ok(Reply::NotFound) => {
                    answered = true;
                    break;
                }
                Err(NetErr::Timeout) if deadline.expired() => return Err(NetErr::Timeout),
                Err(e) => last = e,
            }
        }
        if answered {
            last = NetErr::failed(cannot_resolve(original));
        }
    }
    Err(last)
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use std::thread;

    /// A server answering every question with fixed records, like the Go test's `fakeDNS`.
    pub fn fake_dns() -> SocketAddr {
        let sock = UdpSocket::bind("127.0.0.1:0").unwrap();
        let addr = sock.local_addr().unwrap();
        thread::spawn(move || {
            let mut buf = [0u8; 4096];
            while let Ok((n, peer)) = sock.recv_from(&mut buf) {
                if n < 12 {
                    continue;
                }
                let qend = {
                    let (_, e) = match read_name(&buf[..n], 12) {
                        Some(x) => x,
                        None => continue,
                    };
                    e + 4
                };
                let qtype = u16::from_be_bytes([buf[qend - 4], buf[qend - 3]]);
                let mut out = Vec::new();
                out.extend_from_slice(&buf[0..2]);
                out.extend_from_slice(&[0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0]);
                out.extend_from_slice(&buf[12..qend]);
                out.extend_from_slice(&[0xC0, 0x0C]);
                out.extend_from_slice(&qtype.to_be_bytes());
                out.extend_from_slice(&[0, 1, 0, 0, 0, 30]);
                let mut rdata = Vec::new();
                match qtype {
                    TYPE_A => rdata.extend_from_slice(&[127, 0, 0, 1]),
                    TYPE_AAAA => {
                        rdata.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
                    }
                    TYPE_TXT => rdata.extend_from_slice(b"\x05hello"),
                    TYPE_MX => {
                        rdata.extend_from_slice(&[0, 10]);
                        encode_name("mail.test.", &mut rdata).unwrap();
                    }
                    TYPE_NS => encode_name("ns.test.", &mut rdata).unwrap(),
                    TYPE_CNAME => encode_name("alias.test.", &mut rdata).unwrap(),
                    TYPE_PTR => encode_name("host.test.", &mut rdata).unwrap(),
                    TYPE_SRV => {
                        rdata.extend_from_slice(&[0, 1, 0, 2, 1, 0xBB]);
                        encode_name("service.test.", &mut rdata).unwrap();
                    }
                    _ => {}
                }
                out.extend_from_slice(&(rdata.len() as u16).to_be_bytes());
                out.extend_from_slice(&rdata);
                let _ = sock.send_to(&out, peer);
            }
        });
        addr
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn answers_every_kind() {
        let server = testing::fake_dns();
        let d = Deadline::after(Duration::from_secs(2));
        let one = |t| match query(server, "test.", t, d).unwrap() {
            Reply::Records(r) => r,
            Reply::NotFound => panic!("no records for {t}"),
        };
        assert_eq!(one(TYPE_A)[0].value, "127.0.0.1");
        assert_eq!(one(TYPE_AAAA)[0].value, "::1");
        assert_eq!(one(TYPE_TXT)[0].value, "hello");
        let mx = &one(TYPE_MX)[0];
        assert_eq!((mx.value.as_str(), mx.priority), ("mail.test.", 10));
        assert_eq!(one(TYPE_NS)[0].value, "ns.test.");
        assert_eq!(one(TYPE_CNAME)[0].value, "alias.test.");
        assert_eq!(one(TYPE_PTR)[0].value, "host.test.");
        let srv = &one(TYPE_SRV)[0];
        assert_eq!(
            (srv.value.as_str(), srv.priority, srv.weight, srv.port),
            ("service.test.", 1, 2, 443)
        );
    }

    #[test]
    fn query_times_out_without_a_server() {
        let silent = UdpSocket::bind("127.0.0.1:0").unwrap();
        let d = Deadline::after(Duration::from_millis(100));
        let r = query(silent.local_addr().unwrap(), "x.test.", TYPE_A, d);
        assert_eq!(r.unwrap_err(), NetErr::Timeout);
    }

    #[test]
    fn host_config() {
        let c = HostConfig::parse(
            "# c\nnameserver 10.0.0.1\nnameserver ::1\nsearch a.test b.test.\noptions ndots:2 timeout:1\n",
        );
        assert_eq!(c.servers.len(), 2);
        assert_eq!(c.search, vec!["a.test", "b.test"]);
        assert_eq!(c.ndots, 2);
        assert_eq!(
            c.candidates("host"),
            vec!["host.a.test.", "host.b.test.", "host."]
        );
        assert_eq!(
            c.candidates("a.b"),
            vec!["a.b.a.test.", "a.b.b.test.", "a.b."]
        );
        assert_eq!(
            c.candidates("a.b.c"),
            vec!["a.b.c.", "a.b.c.a.test.", "a.b.c.b.test."]
        );
        assert_eq!(c.candidates("x."), vec!["x."]);
        assert_eq!(HostConfig::parse("").servers.len(), 2);
    }

    #[test]
    fn reverse_names() {
        assert_eq!(
            reverse_name(&"1.2.3.4".parse().unwrap()),
            "4.3.2.1.in-addr.arpa."
        );
        let v6 = reverse_name(&"2001:db8::1".parse().unwrap());
        assert!(
            v6.starts_with("1.0.0.0.0.0.0.0") && v6.ends_with("8.b.d.0.1.0.0.2.ip6.arpa."),
            "{v6}"
        );
    }

    #[test]
    fn name_encoding_and_compression() {
        let mut v = Vec::new();
        encode_name("a.b.", &mut v).unwrap();
        assert_eq!(v, b"\x01a\x01b\x00");
        assert!(encode_name(&"x".repeat(64), &mut Vec::new()).is_err());
        let msg = [b'\x01', b'a', 0, 0xC0, 0];
        assert_eq!(read_name(&msg, 3), Some(("a.".to_string(), 5)));
    }
}
