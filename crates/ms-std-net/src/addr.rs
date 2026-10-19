//! Address text helpers shared by the network modules.

/// Splits `host:port` like Go's `net.SplitHostPort`: `[v6]:port` removes the
/// brackets, a bare host may hold no colon, and the port may be empty.
pub fn split_host_port(hostport: &str) -> Option<(&str, &str)> {
    if let Some(rest) = hostport.strip_prefix('[') {
        let close = rest.find(']')?;
        let host = &rest[..close];
        let after = &rest[close + 1..];
        let port = after.strip_prefix(':')?;
        if port.contains(':') || port.contains('[') || port.contains(']') {
            return None;
        }
        if host.contains('[') {
            return None;
        }
        return Some((host, port));
    }
    let colon = hostport.rfind(':')?;
    let host = &hostport[..colon];
    if host.contains(':') || host.contains('[') || host.contains(']') {
        return None;
    }
    let port = &hostport[colon + 1..];
    if port.contains('[') || port.contains(']') {
        return None;
    }
    Some((host, port))
}

/// Parses a port: digits only, 0 through 65535 (named services are not supported).
pub fn parse_port(text: &str) -> Option<u16> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse::<u16>().ok()
}

/// `host:port` text with IPv6 hosts in brackets.
pub fn join_host_port(host: &str, port: u16) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitting() {
        assert_eq!(
            split_host_port("example.com:80"),
            Some(("example.com", "80"))
        );
        assert_eq!(split_host_port("[::1]:80"), Some(("::1", "80")));
        assert_eq!(split_host_port(":80"), Some(("", "80")));
        assert_eq!(split_host_port("host:"), Some(("host", "")));
        assert_eq!(split_host_port("host"), None);
        assert_eq!(split_host_port("::1"), None);
        assert_eq!(split_host_port("[::1]"), None);
        assert_eq!(split_host_port("[::1]x:80"), None);
        assert_eq!(split_host_port("a:b:c"), None);
    }

    #[test]
    fn ports() {
        assert_eq!(parse_port("0"), Some(0));
        assert_eq!(parse_port("65535"), Some(65535));
        assert_eq!(parse_port("65536"), None);
        assert_eq!(parse_port("+1"), None);
        assert_eq!(parse_port(""), None);
        assert_eq!(join_host_port("::1", 80), "[::1]:80");
        assert_eq!(join_host_port("a", 80), "a:80");
    }
}
