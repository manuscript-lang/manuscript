//! Downloads and unpacks the pinned LLVM tools archive with `ms`'s own HTTPS client and tar reader,
//! so no `curl` or `tar` needs to exist on the machine.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::sync::Arc;

const MAX_REDIRECTS: usize = 5;

/// The body of `url`, following redirects. `HTTPS_PROXY` (an `http://host:port` proxy) is honored.
pub fn get(url: &str) -> Result<Vec<u8>, String> {
    let mut url = url.to_string();
    for _ in 0..=MAX_REDIRECTS {
        let (status, location, body) = request(&url)?;
        match status {
            200 => return Ok(body),
            301 | 302 | 303 | 307 | 308 => {
                let to = location.ok_or("redirect without a Location")?;
                url = if to.starts_with("https://") {
                    to
                } else {
                    let host = url["https://".len()..].split('/').next().unwrap_or("");
                    format!("https://{host}{to}")
                };
            }
            other => return Err(format!("{url}: HTTP status {other}")),
        }
    }
    Err("too many redirects".into())
}

fn request(url: &str) -> Result<(u16, Option<String>, Vec<u8>), String> {
    let rest = url
        .strip_prefix("https://")
        .ok_or("only https URLs are fetched")?;
    let (host, path) = rest.split_once('/').map_or((rest, ""), |(h, p)| (h, p));
    let (name, port) = host
        .rsplit_once(':')
        .map_or((host, 443), |(n, p)| (n, p.parse().unwrap_or(443)));
    let tcp = connect(name, port)?;
    let mut roots = rustls::RootCertStore::empty();
    for cert in rustls_native_certs::load_native_certs().certs {
        let _ = roots.add(cert);
    }
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| e.to_string())?
    .with_root_certificates(roots)
    .with_no_client_auth();
    let server = rustls::pki_types::ServerName::try_from(name.to_string())
        .map_err(|e| format!("{name}: {e}"))?;
    let conn =
        rustls::ClientConnection::new(Arc::new(config), server).map_err(|e| e.to_string())?;
    let mut tls = rustls::StreamOwned::new(conn, tcp);
    write!(
        tls,
        "GET /{path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: ms\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
    )
    .map_err(|e| format!("{url}: {e}"))?;
    let mut reader = BufReader::new(tls);
    let mut head = Vec::new();
    loop {
        let before = head.len();
        reader
            .read_until(b'\n', &mut head)
            .map_err(|e| format!("{url}: {e}"))?;
        if head.len() == before {
            return Err(format!("{url}: connection closed before the response"));
        }
        if head.ends_with(b"\r\n\r\n") {
            break;
        }
    }
    let mut headers = [httparse::EMPTY_HEADER; 64];
    let mut response = httparse::Response::new(&mut headers);
    response.parse(&head).map_err(|e| format!("{url}: {e}"))?;
    let status = response.code.unwrap_or(0);
    let header = |name: &str| {
        response
            .headers
            .iter()
            .find(|h| h.name.eq_ignore_ascii_case(name))
            .map(|h| String::from_utf8_lossy(h.value).trim().to_string())
    };
    let location = header("location");
    let chunked = header("transfer-encoding").is_some_and(|v| v.eq_ignore_ascii_case("chunked"));
    let length = header("content-length").and_then(|v| v.parse::<usize>().ok());
    let mut body = Vec::new();
    if status != 200 {
        return Ok((status, location, body));
    }
    if chunked {
        loop {
            let mut line = String::new();
            reader
                .read_line(&mut line)
                .map_err(|e| format!("{url}: {e}"))?;
            let size = usize::from_str_radix(line.trim().split(';').next().unwrap_or(""), 16)
                .map_err(|_| format!("{url}: malformed chunk"))?;
            if size == 0 {
                break;
            }
            let start = body.len();
            body.resize(start + size, 0);
            reader
                .read_exact(&mut body[start..])
                .map_err(|e| format!("{url}: {e}"))?;
            let mut crlf = [0u8; 2];
            reader
                .read_exact(&mut crlf)
                .map_err(|e| format!("{url}: {e}"))?;
        }
    } else {
        reader.read_to_end(&mut body).or_else(|e| {
            // Servers that close without a TLS close_notify still delivered the body.
            if e.kind() == std::io::ErrorKind::UnexpectedEof {
                Ok(0)
            } else {
                Err(format!("{url}: {e}"))
            }
        })?;
    }
    if length.is_some_and(|n| n != body.len()) {
        return Err(format!("{url}: the download was cut short"));
    }
    Ok((status, location, body))
}

/// A TCP connection to `host:port`, through the `http://` proxy named by `HTTPS_PROXY` when set.
fn connect(host: &str, port: u16) -> Result<TcpStream, String> {
    let proxy = ["HTTPS_PROXY", "https_proxy"]
        .iter()
        .find_map(|v| std::env::var(v).ok().filter(|p| !p.is_empty()));
    let Some(proxy) = proxy else {
        return TcpStream::connect((host, port))
            .map_err(|e| format!("cannot connect to {host}: {e}"));
    };
    let authority = proxy.trim_start_matches("http://").trim_end_matches('/');
    // Credentials in the proxy URL are sent as Basic authorization.
    let (auth, address) = authority
        .rsplit_once('@')
        .map_or((None, authority), |(a, h)| (Some(a), h));
    let mut stream = TcpStream::connect(address)
        .map_err(|e| format!("cannot connect to the proxy {address}: {e}"))?;
    let credentials = auth.map_or(String::new(), |a| {
        format!("Proxy-Authorization: Basic {}\r\n", base64(a.as_bytes()))
    });
    write!(
        stream,
        "CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n{credentials}\r\n"
    )
    .map_err(|e| e.to_string())?;
    let mut reply = Vec::new();
    let mut byte = [0u8; 1];
    while !reply.ends_with(b"\r\n\r\n") {
        stream
            .read_exact(&mut byte)
            .map_err(|e| format!("the proxy closed the connection: {e}"))?;
        reply.push(byte[0]);
    }
    if !reply.starts_with(b"HTTP/1.1 200") && !reply.starts_with(b"HTTP/1.0 200") {
        return Err(format!(
            "the proxy refused the connection: {}",
            String::from_utf8_lossy(&reply).lines().next().unwrap_or("")
        ));
    }
    Ok(stream)
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = chunk.iter().fold(0u32, |n, b| n << 8 | u32::from(*b)) << (8 * (3 - chunk.len()));
        for i in 0..=chunk.len() {
            out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
        out.extend(std::iter::repeat_n('=', 3 - chunk.len()));
    }
    out
}

/// Writes the files of the gzipped tar `archive` named in `wanted` into `dir`, executable, under
/// their base names. Fails when one is missing.
pub fn unpack_tools(archive: &[u8], wanted: &[String], dir: &Path) -> Result<(), String> {
    let mut tar = flate2::read::GzDecoder::new(archive);
    let mut found = 0;
    let mut header = [0u8; 512];
    while tar.read_exact(&mut header).is_ok() && header.iter().any(|b| *b != 0) {
        let text = |range: std::ops::Range<usize>| {
            let field = &header[range];
            let end = field
                .iter()
                .position(|b| *b == 0 || *b == b' ')
                .unwrap_or(field.len());
            String::from_utf8_lossy(&field[..end]).into_owned()
        };
        let name = text(0..100);
        let size = u64::from_str_radix(&text(124..136), 8).map_err(|_| "malformed tar header")?;
        let regular = matches!(header[156], 0 | b'0');
        let base = name
            .trim_start_matches("./")
            .strip_prefix("bin/")
            .map(str::to_string);
        let padded = size.div_ceil(512) * 512;
        match base.filter(|b| regular && wanted.contains(b)) {
            Some(base) => {
                let mut contents = vec![0u8; size as usize];
                tar.read_exact(&mut contents)
                    .map_err(|e| format!("{name}: {e}"))?;
                let path = dir.join(&base);
                std::fs::write(&path, contents).map_err(|e| format!("{}: {e}", path.display()))?;
                super::lld::set_mode(&path, true)
                    .map_err(|e| format!("{}: {e}", path.display()))?;
                std::io::copy(&mut (&mut tar).take(padded - size), &mut std::io::sink())
                    .map_err(|e| e.to_string())?;
                found += 1;
            }
            None => {
                std::io::copy(&mut (&mut tar).take(padded), &mut std::io::sink())
                    .map_err(|e| e.to_string())?;
            }
        }
    }
    if found == wanted.len() {
        Ok(())
    } else {
        Err("the archive does not hold every tool".into())
    }
}
