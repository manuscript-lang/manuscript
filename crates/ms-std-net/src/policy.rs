//! Network restriction policy: which hosts, addresses and listeners a derived
//! network may reach. A `None` policy allows everything.

use crate::ip::Cidr;
use std::collections::HashSet;
use std::net::IpAddr;
use std::rc::Rc;

pub struct Policy {
    hosts: HashSet<String>,
    prefixes: Vec<Cidr>,
    pub listen: bool,
    parent: Option<Rc<Policy>>,
}

/// Lower-cases a host name and drops one trailing dot.
pub fn fold_host(name: &str) -> String {
    name.strip_suffix('.').unwrap_or(name).to_ascii_lowercase()
}

impl Policy {
    pub fn new(
        hosts: HashSet<String>,
        prefixes: Vec<Cidr>,
        listen: bool,
        parent: Option<Rc<Policy>>,
    ) -> Policy {
        Policy {
            hosts,
            prefixes,
            listen,
            parent,
        }
    }

    /// Whether a host name or literal address may be dialed.
    pub fn host(&self, name: &str) -> bool {
        let name = fold_host(name);
        let mut allowed = self.hosts.contains(&name);
        if let Ok(ip) = name.parse::<IpAddr>() {
            let ip = unmap(ip);
            if self.prefixes.iter().any(|p| p.contains(&ip)) {
                allowed = true;
            }
        }
        allowed && self.parent.as_ref().is_none_or(|p| p.host(&name))
    }

    /// Whether a resolved address may be used.
    pub fn ip(&self, ip: IpAddr) -> bool {
        let ip = unmap(ip);
        let mut allowed = self.prefixes.is_empty() && !self.hosts.is_empty();
        if self.prefixes.iter().any(|p| p.contains(&ip)) {
            allowed = true;
        }
        allowed && self.parent.as_ref().is_none_or(|p| p.ip(ip))
    }
}

fn unmap(ip: IpAddr) -> IpAddr {
    crate::ip::normalize(ip)
}

/// `policy.host(name)` where `None` means unrestricted.
pub fn host_ok(policy: &Option<Rc<Policy>>, name: &str) -> bool {
    policy.as_ref().is_none_or(|p| p.host(name))
}

/// `policy.ip(ip)` where `None` means unrestricted.
pub fn ip_ok(policy: &Option<Rc<Policy>>, ip: IpAddr) -> bool {
    policy.as_ref().is_none_or(|p| p.ip(ip))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(hosts: &[&str], cidrs: &[&str], listen: bool) -> Rc<Policy> {
        Rc::new(Policy::new(
            hosts.iter().map(|h| fold_host(h)).collect(),
            cidrs.iter().map(|c| Cidr::parse(c).unwrap()).collect(),
            listen,
            None,
        ))
    }

    #[test]
    fn hosts_and_prefixes() {
        let p = policy(&["Example.COM."], &["10.0.0.0/8"], false);
        assert!(p.host("example.com"));
        assert!(p.host("10.1.2.3"));
        assert!(!p.host("other.com"));
        assert!(p.ip("10.9.9.9".parse().unwrap()));
        assert!(!p.ip("11.0.0.1".parse().unwrap()));
        let only_hosts = policy(&["a.test"], &[], false);
        assert!(only_hosts.ip("203.0.113.9".parse().unwrap()));
        let empty = policy(&[], &[], false);
        assert!(!empty.ip("127.0.0.1".parse().unwrap()));
        assert!(!empty.host("anything"));
    }

    #[test]
    fn parents_narrow_further() {
        let parent = policy(&["a.test", "b.test"], &[], true);
        let child = Rc::new(Policy::new(
            ["a.test".to_string()].into_iter().collect(),
            vec![],
            true,
            Some(parent),
        ));
        assert!(child.host("a.test"));
        assert!(!child.host("b.test"));
    }
}
