//! Host inventories behind `System.network_interfaces`, `cpus` and `metrics`.
//!
//! Each call takes a snapshot; the exports in `lib.rs` hand its parts out one field at a time.
//! Network interfaces work on every unix host; CPU and memory figures come from `/proc`, so
//! `cpus` and `metrics` answer `Unsupported` off Linux.
#![allow(unsafe_code)] // libc `getifaddrs` and friends

use alloc::vec::Vec;
use core::cell::RefCell;
#[cfg(unix)]
use ms_rt_abi::STATUS_FAILED;
use ms_rt_abi::STATUS_UNSUPPORTED;
#[cfg(any(target_os = "linux", target_os = "android"))]
use ms_rt_abi::{STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED};
use ms_std_core::Global;

/// One address of one network interface.
#[derive(Default)]
pub struct Interface {
    pub name: Vec<u8>,
    pub address: Vec<u8>,
    pub netmask: Vec<u8>,
    pub v6: bool,
    pub mac: Vec<u8>,
    pub internal: bool,
    pub scope_id: i64,
}

/// One logical CPU; times are cumulative milliseconds.
#[derive(Clone, Default)]
pub struct Cpu {
    pub model: Vec<u8>,
    pub speed_mhz: i64,
    pub user: i64,
    pub nice: i64,
    pub system: i64,
    pub idle: i64,
    pub irq: i64,
}

#[derive(Default)]
pub struct Metrics {
    pub total_memory: i64,
    pub free_memory: i64,
    pub available_memory: i64,
    pub uptime_ns: i64,
    pub load: [f64; 3],
    pub parallelism: i64,
}

/// Process-wide holder of the last snapshot; the runtime calls natives from one thread at a time.
pub struct Slot<T>(Global<RefCell<Option<T>>>);

impl<T> Slot<T> {
    pub const fn new() -> Self {
        Self(Global::new(RefCell::new(None)))
    }

    pub fn set(&self, value: T) {
        *self.0.get().borrow_mut() = Some(value);
    }

    /// Reads the snapshot (`None` before the first one).
    pub fn with<R>(&self, read: impl FnOnce(Option<&T>) -> R) -> R {
        read(self.0.get().borrow().as_ref())
    }
}

#[cfg(unix)]
fn failed(text: &[u8]) -> u8 {
    ms_std_rt::record_failure(text.to_vec());
    STATUS_FAILED
}

#[cfg(unix)]
pub fn interfaces() -> Result<Vec<Interface>, u8> {
    use core::ffi::CStr;

    let mut head: *mut libc::ifaddrs = core::ptr::null_mut();
    // SAFETY: `head` receives a list that `freeifaddrs` releases below.
    if unsafe { libc::getifaddrs(&mut head) } != 0 {
        return Err(failed(b"getifaddrs failed"));
    }
    let mut macs: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    let mut found = Vec::new();
    let mut result = Ok(());
    let mut at = head;
    while !at.is_null() {
        // SAFETY: the list nodes stay valid until `freeifaddrs`.
        let ifa = unsafe { &*at };
        at = ifa.ifa_next;
        if ifa.ifa_addr.is_null() {
            continue;
        }
        // SAFETY: `ifa_name` is a NUL-terminated string.
        let name = unsafe { CStr::from_ptr(ifa.ifa_name) }.to_bytes().to_vec();
        if core::str::from_utf8(&name).is_err() {
            result = Err(STATUS_UNSUPPORTED);
            break;
        }
        // SAFETY: a non-null `ifa_addr` points at a sockaddr.
        let family = i32::from(unsafe { (*ifa.ifa_addr).sa_family });
        #[cfg(any(target_os = "linux", target_os = "android"))]
        if family == libc::AF_PACKET {
            // SAFETY: AF_PACKET addresses are `sockaddr_ll`.
            let ll = unsafe { &*(ifa.ifa_addr as *const libc::sockaddr_ll) };
            let len = usize::from(ll.sll_halen).min(ll.sll_addr.len());
            // Interfaces without a hardware address (loopback) report all zeros.
            if ll.sll_addr[..len].iter().any(|&b| b != 0) {
                macs.push((name, hex_mac(&ll.sll_addr[..len])));
            }
            continue;
        }
        let v6 = match family {
            libc::AF_INET => false,
            libc::AF_INET6 => true,
            _ => continue,
        };
        if ifa.ifa_netmask.is_null() {
            continue;
        }
        let (Some(address), Some(netmask)) =
            (ip_text(ifa.ifa_addr, v6), ip_text(ifa.ifa_netmask, v6))
        else {
            continue;
        };
        found.push(Interface {
            // SAFETY: `ifa_name` is a NUL-terminated string.
            scope_id: i64::from(unsafe { libc::if_nametoindex(ifa.ifa_name) }),
            name,
            address,
            netmask,
            v6,
            mac: Vec::new(),
            internal: ifa.ifa_flags & libc::IFF_LOOPBACK as u32 != 0,
        });
    }
    // SAFETY: `head` came from `getifaddrs` and nothing borrows it any more.
    unsafe { libc::freeifaddrs(head) };
    result?;
    for item in &mut found {
        if let Some((_, mac)) = macs.iter().find(|(n, _)| *n == item.name) {
            item.mac = mac.clone();
        }
    }
    // The kernel's interface order, like `net.Interfaces`; the sort is stable.
    found.sort_by_key(|i| i.scope_id);
    Ok(found)
}

#[cfg(unix)]
fn ip_text(sa: *const libc::sockaddr, v6: bool) -> Option<Vec<u8>> {
    let mut buf = [0u8; 64];
    let (af, src) = if v6 {
        // SAFETY: an AF_INET6 sockaddr is a `sockaddr_in6`.
        let a = unsafe { &*(sa as *const libc::sockaddr_in6) };
        (
            libc::AF_INET6,
            (&a.sin6_addr as *const libc::in6_addr).cast(),
        )
    } else {
        // SAFETY: an AF_INET sockaddr is a `sockaddr_in`.
        let a = unsafe { &*(sa as *const libc::sockaddr_in) };
        (libc::AF_INET, (&a.sin_addr as *const libc::in_addr).cast())
    };
    unsafe extern "C" {
        // The `libc` crate does not bind it.
        fn inet_ntop(
            af: libc::c_int,
            src: *const libc::c_void,
            dst: *mut libc::c_char,
            size: libc::socklen_t,
        ) -> *const libc::c_char;
    }
    // SAFETY: `src` is a valid address of the family and `buf` is writable for its length.
    let text = unsafe { inet_ntop(af, src, buf.as_mut_ptr().cast(), buf.len() as _) };
    if text.is_null() {
        return None;
    }
    let end = buf.iter().position(|&b| b == 0)?;
    Some(buf[..end].to_vec())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn hex_mac(bytes: &[u8]) -> Vec<u8> {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = Vec::with_capacity(bytes.len() * 3);
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 {
            out.push(b':');
        }
        out.push(DIGITS[usize::from(b >> 4)]);
        out.push(DIGITS[usize::from(b & 15)]);
    }
    out
}

#[cfg(not(unix))]
pub fn interfaces() -> Result<Vec<Interface>, u8> {
    Err(STATUS_UNSUPPORTED)
}

/// The whole of `path`; `/proc` files report no size, so it reads until the end.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn read_file(path: &str) -> Result<Vec<u8>, u8> {
    use std::io::ErrorKind;

    std::fs::read(path).map_err(|e| match e.kind() {
        ErrorKind::NotFound => STATUS_NOT_FOUND,
        ErrorKind::PermissionDenied => STATUS_PERMISSION_DENIED,
        _ => failed(b"cannot read host statistics"),
    })
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn number(bytes: &[u8]) -> i64 {
    let digits = bytes.iter().take_while(|b| b.is_ascii_digit());
    digits.fold(0i64, |n, &b| {
        n.saturating_mul(10).saturating_add(i64::from(b - b'0'))
    })
}

/// The value after `key:` on a `/proc` line, without surrounding blanks.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn field<'a>(line: &'a [u8], key: &[u8]) -> Option<&'a [u8]> {
    let rest = line
        .strip_prefix(key)?
        .trim_ascii_start()
        .strip_prefix(b":")?;
    Some(rest.trim_ascii())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub fn cpus() -> Result<Vec<Cpu>, u8> {
    let stat = read_file("/proc/stat")?;
    let info = read_file("/proc/cpuinfo").unwrap_or_default();
    // (model, MHz) of each `processor` block.
    let mut models: Vec<(Vec<u8>, i64)> = Vec::new();
    for line in info.split(|&b| b == b'\n') {
        if field(line, b"processor").is_some() {
            models.push((Vec::new(), 0));
        } else if let Some(last) = models.last_mut() {
            if let Some(v) = field(line, b"model name") {
                last.0 = v.to_vec();
            } else if let Some(v) = field(line, b"cpu MHz") {
                last.1 = number(v);
            }
        }
    }
    let ticks = i64::try_from(rustix::param::clock_ticks_per_second())
        .unwrap_or(i64::MAX)
        .max(1);
    let ms = |jiffies: i64| jiffies.saturating_mul(1000) / ticks;
    let mut cpus: Vec<Cpu> = Vec::new();
    for line in stat.split(|&b| b == b'\n') {
        let Some(rest) = line.strip_prefix(b"cpu") else {
            continue;
        };
        // The aggregate `cpu ` line has no index.
        if !rest.first().is_some_and(u8::is_ascii_digit) {
            continue;
        }
        let mut parts = line.split(|&b| b == b' ').filter(|p| !p.is_empty()).skip(1);
        let mut next = || parts.next().map_or(0, number);
        let (user, nice, system, idle) = (next(), next(), next(), next());
        let (_iowait, irq, softirq) = (next(), next(), next());
        let (model, speed_mhz) = models
            .get(cpus.len())
            .or_else(|| models.first())
            .cloned()
            .unwrap_or_default();
        cpus.push(Cpu {
            model,
            speed_mhz,
            user: ms(user),
            nice: ms(nice),
            system: ms(system),
            idle: ms(idle),
            irq: ms(irq + softirq),
        });
    }
    Ok(cpus)
}

#[cfg(any(target_os = "linux", target_os = "android"))]
#[allow(clippy::useless_conversion)] // `sysinfo` fields are narrower than 64 bits on 32-bit hosts
pub fn metrics() -> Result<Metrics, u8> {
    let info = rustix::system::sysinfo();
    let unit = u64::from(info.mem_unit.max(1));
    let bytes = |n: u64| i64::try_from(n.saturating_mul(unit)).unwrap_or(i64::MAX);
    let free = bytes(info.freeram.into());
    // `sysinfo` has no available-memory figure; kernels before 3.14 lack `MemAvailable` too,
    // and free memory is the honest lower bound.
    let available = read_file("/proc/meminfo")
        .ok()
        .and_then(|mem| {
            mem.split(|&b| b == b'\n')
                .find_map(|l| field(l, b"MemAvailable"))
                .map(number)
        })
        .map_or(0, |kib| kib.saturating_mul(1024));
    // Load averages are fixed-point with 16 fractional bits.
    let load = info.loads.map(|l| l as f64 / 65536.0);
    Ok(Metrics {
        total_memory: bytes(info.totalram.into()),
        free_memory: free,
        available_memory: if available == 0 { free } else { available },
        uptime_ns: i64::from(info.uptime).saturating_mul(1_000_000_000),
        load,
        parallelism: parallelism(),
    })
}

/// Logical processors this process may run on.
#[cfg(any(target_os = "linux", target_os = "android"))]
fn parallelism() -> i64 {
    match rustix::thread::sched_getaffinity(None) {
        Ok(set) => i64::from(set.count()).max(1),
        Err(_) => crate::imp::cpu_count(),
    }
}

#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub fn cpus() -> Result<Vec<Cpu>, u8> {
    Err(STATUS_UNSUPPORTED)
}

#[cfg(not(any(target_os = "linux", target_os = "android")))]
pub fn metrics() -> Result<Metrics, u8> {
    Err(STATUS_UNSUPPORTED)
}
