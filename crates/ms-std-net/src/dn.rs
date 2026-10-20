//! Distinguished-name text in the RFC 2253 style used in certificate subjects.

use x509_parser::x509::X509Name;

/// Attribute values of the standard fields, in parse order.
#[derive(Default)]
struct Fields {
    country: Vec<String>,
    province: Vec<String>,
    locality: Vec<String>,
    street: Vec<String>,
    postal: Vec<String>,
    organization: Vec<String>,
    unit: Vec<String>,
    common: Option<String>,
    serial: Option<String>,
    extra: Vec<(String, String)>,
}

/// Text of a parsed certificate name: the sequence is the
/// nonstandard attributes in certificate order, then C, ST, L, street, postal
/// code, O, OU, CN, serial number, printed from last to first.
pub fn format(name: &X509Name<'_>) -> String {
    let mut f = Fields::default();
    for rdn in name.iter_rdn() {
        for attr in rdn.iter() {
            let Ok(value) = attr.as_str() else { continue };
            let value = value.to_string();
            match attr.attr_type().to_id_string().as_str() {
                "2.5.4.3" => f.common = Some(value),
                "2.5.4.5" => f.serial = Some(value),
                "2.5.4.6" => f.country.push(value),
                "2.5.4.7" => f.locality.push(value),
                "2.5.4.8" => f.province.push(value),
                "2.5.4.9" => f.street.push(value),
                "2.5.4.10" => f.organization.push(value),
                "2.5.4.11" => f.unit.push(value),
                "2.5.4.17" => f.postal.push(value),
                other => f.extra.push((other.to_string(), value)),
            }
        }
    }
    let mut rdns: Vec<Vec<(&str, String, bool)>> = Vec::new();
    for (oid, value) in &f.extra {
        rdns.push(vec![(oid.as_str(), value.clone(), false)]);
    }
    let groups: [(&str, &Vec<String>); 7] = [
        ("C", &f.country),
        ("ST", &f.province),
        ("L", &f.locality),
        ("STREET", &f.street),
        ("POSTALCODE", &f.postal),
        ("O", &f.organization),
        ("OU", &f.unit),
    ];
    for (label, values) in groups {
        if !values.is_empty() {
            rdns.push(values.iter().map(|v| (label, v.clone(), true)).collect());
        }
    }
    if let Some(v) = &f.common {
        rdns.push(vec![("CN", v.clone(), true)]);
    }
    if let Some(v) = &f.serial {
        rdns.push(vec![("SERIALNUMBER", v.clone(), true)]);
    }
    rdns.iter()
        .rev()
        .map(|rdn| {
            rdn.iter()
                .map(|(label, value, known)| attribute(label, value, *known))
                .collect::<Vec<_>>()
                .join("+")
        })
        .collect::<Vec<_>>()
        .join(",")
}

fn attribute(label: &str, value: &str, known: bool) -> String {
    if !known {
        return format!("{label}=#{}", hex(&der_string(value)));
    }
    format!("{label}={}", escape(value))
}

/// The RFC 2253 specials, a leading `#` or space, and a trailing space are escaped.
fn escape(value: &str) -> String {
    let last = value.chars().count().saturating_sub(1);
    let mut out = String::with_capacity(value.len());
    for (i, c) in value.chars().enumerate() {
        match c {
            ',' | '+' | '"' | '\\' | '<' | '>' | ';' => {
                out.push('\\');
                out.push(c);
            }
            ' ' if i == 0 || i == last => {
                out.push('\\');
                out.push(c);
            }
            '#' if i == 0 => {
                out.push('\\');
                out.push(c);
            }
            _ => out.push(c),
        }
    }
    out
}

fn printable(c: char) -> bool {
    c.is_ascii_alphanumeric() || " '()+,-./:=?".contains(c)
}

/// DER of a string: PrintableString when possible, otherwise UTF8String.
fn der_string(value: &str) -> Vec<u8> {
    let tag = if value.chars().all(printable) {
        0x13
    } else {
        0x0c
    };
    let mut out = vec![tag];
    let n = value.len();
    if n < 128 {
        out.push(n as u8);
    } else {
        let bytes = n.to_be_bytes();
        let skip = bytes.iter().take_while(|b| **b == 0).count();
        out.push(0x80 | (bytes.len() - skip) as u8);
        out.extend_from_slice(&bytes[skip..]);
    }
    out.extend_from_slice(value.as_bytes());
    out
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes.iter().fold(String::new(), |mut s, b| {
        let _ = write!(s, "{b:02x}");
        s
    })
}
