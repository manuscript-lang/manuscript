//! `IpAddress` and `Cidr`: validated numeric addresses and ranges.
//!
//! Text: IPv4-mapped IPv6 input is normalized to IPv4,
//! zones are rejected, IPv6 prints in RFC 5952 form, and a 4-in-6 address keeps
//! the `::ffff:a.b.c.d` spelling when it appears inside an IPv6 prefix.

use crate::error::NetErr;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// Parses an address. Zones and surrounding space are rejected.
pub fn parse_ip(text: &str) -> Result<IpAddr, NetErr> {
    let ip = text.parse::<IpAddr>().map_err(|_| NetErr::InvalidData)?;
    Ok(normalize(ip))
}

/// Maps an IPv4-mapped IPv6 address to IPv4.
pub fn normalize(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        },
        v4 => v4,
    }
}

/// Canonical text of an address.
pub fn ip_text(ip: &IpAddr) -> String {
    match ip {
        IpAddr::V4(v4) => v4.to_string(),
        IpAddr::V6(v6) => ipv6_text(v6),
    }
}

/// RFC 5952 text with the IPv4-mapped spelling.
pub fn ipv6_text(ip: &Ipv6Addr) -> String {
    let groups = ip.segments();
    if let Some(v4) = ip.to_ipv4_mapped() {
        return format!("::ffff:{v4}");
    }
    // Longest run of at least two zero groups; the first wins a tie.
    let (mut best_at, mut best_len) = (usize::MAX, 0usize);
    let mut i = 0;
    while i < 8 {
        if groups[i] != 0 {
            i += 1;
            continue;
        }
        let start = i;
        while i < 8 && groups[i] == 0 {
            i += 1;
        }
        if i - start > best_len {
            best_at = start;
            best_len = i - start;
        }
    }
    if best_len < 2 {
        best_at = usize::MAX;
    }
    let mut out = String::new();
    let mut i = 0;
    while i < 8 {
        if i == best_at {
            out.push_str("::");
            i += best_len;
            continue;
        }
        if !out.is_empty() && !out.ends_with(':') {
            out.push(':');
        }
        out.push_str(&format!("{:x}", groups[i]));
        i += 1;
    }
    out
}

/// A masked CIDR range.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cidr {
    addr: IpAddr,
    bits: u8,
}

impl Cidr {
    /// Parses and masks a range such as `192.0.2.3/24`.
    pub fn parse(text: &str) -> Result<Cidr, NetErr> {
        let (addr_text, bits_text) = text.split_once('/').ok_or(NetErr::InvalidData)?;
        if bits_text.is_empty()
            || !bits_text.bytes().all(|b| b.is_ascii_digit())
            || (bits_text.len() > 1 && bits_text.starts_with('0'))
        {
            return Err(NetErr::InvalidData);
        }
        // A prefix keeps IPv4-mapped IPv6 addresses as IPv6.
        let addr = addr_text
            .parse::<IpAddr>()
            .map_err(|_| NetErr::InvalidData)?;
        let bits: u32 = bits_text.parse().map_err(|_| NetErr::InvalidData)?;
        let max = if addr.is_ipv4() { 32 } else { 128 };
        if bits > max {
            return Err(NetErr::InvalidData);
        }
        Ok(Cidr {
            addr: mask(addr, bits as u8),
            bits: bits as u8,
        })
    }

    pub fn text(&self) -> String {
        format!("{}/{}", ip_text(&self.addr), self.bits)
    }

    /// Whether `ip` lies in the range; the families must match exactly.
    pub fn contains(&self, ip: &IpAddr) -> bool {
        if self.addr.is_ipv4() != ip.is_ipv4() {
            return false;
        }
        mask(*ip, self.bits) == self.addr
    }
}

fn mask(ip: IpAddr, bits: u8) -> IpAddr {
    match ip {
        IpAddr::V4(v4) => {
            let m = if bits == 0 {
                0
            } else {
                u32::MAX << (32 - bits as u32)
            };
            IpAddr::V4(Ipv4Addr::from(u32::from(v4) & m))
        }
        IpAddr::V6(v6) => {
            let m = if bits == 0 {
                0
            } else {
                u128::MAX << (128 - bits as u32)
            };
            IpAddr::V6(Ipv6Addr::from(u128::from(v6) & m))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Recorded vectors.
    const IPS: &[(&str, Option<&str>)] = &[
        ("1.2.3.4", Some("1.2.3.4")),
        ("01.2.3.4", None),
        ("1.2.3", None),
        ("256.1.1.1", None),
        ("::1", Some("::1")),
        ("::", Some("::")),
        ("2001:0db8::1", Some("2001:db8::1")),
        ("2001:db8:0:0:1:0:0:1", Some("2001:db8::1:0:0:1")),
        ("2001:db8::0:1", Some("2001:db8::1")),
        ("::ffff:1.2.3.4", Some("1.2.3.4")),
        ("::1.2.3.4", Some("::102:304")),
        ("fe80::1%eth0", None),
        ("FE80::AB", Some("fe80::ab")),
        ("1:2:3:4:5:6:7:8", Some("1:2:3:4:5:6:7:8")),
        ("1:0:0:2:0:0:0:3", Some("1:0:0:2::3")),
        ("0:0:0:0:0:0:0:1", Some("::1")),
        ("::ffff:0:0", Some("0.0.0.0")),
        ("64:ff9b::1.2.3.4", Some("64:ff9b::102:304")),
        (" 1.2.3.4", None),
        ("1.2.3.4 ", None),
        ("", None),
        ("::g", None),
        ("1::2::3", None),
        ("2001:db8:0:1:1:1:1:1", Some("2001:db8:0:1:1:1:1:1")),
        ("0:1:0:1:0:1:0:1", Some("0:1:0:1:0:1:0:1")),
        ("::127.0.0.1", Some("::7f00:1")),
        ("1.2.3.4.5", None),
        ("1e2.1.1.1", None),
        ("0x1.2.3.4", None),
    ];

    const CIDRS: &[(&str, Option<&str>)] = &[
        ("192.0.2.3/24", Some("192.0.2.0/24")),
        ("10.0.0.0/8", Some("10.0.0.0/8")),
        ("10.0.0.0/08", None),
        ("10.0.0.0/+8", None),
        ("10.0.0.0/33", None),
        ("10.0.0.0/0", Some("0.0.0.0/0")),
        ("::/0", Some("::/0")),
        ("::1/128", Some("::1/128")),
        ("2001:db8::5/32", Some("2001:db8::/32")),
        ("::ffff:192.0.2.0/120", Some("::ffff:192.0.2.0/120")),
        ("::ffff:192.0.2.1/128", Some("::ffff:192.0.2.1/128")),
        ("fe80::1%eth0/64", None),
        ("1.2.3.4", None),
        ("1.2.3.4/", None),
        ("/8", None),
        ("1.2.3.4/8/8", None),
        ("1.2.3.4/-1", None),
        ("::ffff:1.2.3.4/96", Some("::ffff:0.0.0.0/96")),
        ("::ffff:1.2.3.4/104", Some("::ffff:1.0.0.0/104")),
        ("192.0.2.0/24 ", None),
        ("0.0.0.0/32", Some("0.0.0.0/32")),
    ];

    #[test]
    fn ip_parsing_matches_oracle() {
        for (input, want) in IPS {
            let got = parse_ip(input).ok().map(|ip| ip_text(&ip));
            assert_eq!(got.as_deref(), *want, "{input:?}");
        }
    }

    #[test]
    fn cidr_parsing_matches_oracle() {
        for (input, want) in CIDRS {
            let got = Cidr::parse(input).ok().map(|c| c.text());
            assert_eq!(got.as_deref(), *want, "{input:?}");
        }
    }

    #[test]
    fn containment_requires_the_same_family() {
        let v4 = Cidr::parse("192.0.2.0/24").unwrap();
        assert!(v4.contains(&parse_ip("192.0.2.255").unwrap()));
        assert!(!v4.contains(&parse_ip("192.0.3.0").unwrap()));
        assert!(!v4.contains(&parse_ip("2001:db8::1").unwrap()));
        let mapped = Cidr::parse("::ffff:192.0.2.0/120").unwrap();
        assert!(!mapped.contains(&parse_ip("::ffff:192.0.2.1").unwrap()));
        let all = Cidr::parse("0.0.0.0/0").unwrap();
        assert!(all.contains(&parse_ip("8.8.8.8").unwrap()));
    }
}
