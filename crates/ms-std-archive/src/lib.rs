//! `@std/archive.ms` natives: in-memory zip and tar packing and unpacking with the validation,
//! limits and error mapping of `pkg/runtime/archive.go` (Go's `archive/zip` and `archive/tar`).
//! Zip members are compressed with miniz_oxide, so archives are valid but their compressed
//! bytes and sizes can differ from Go's encoder (tar output is byte-identical).
#![no_std]

extern crate alloc;

pub mod ffi;
mod tar;
mod zip;

use alloc::collections::BTreeMap;
use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::Fail;

pub struct Entry {
    pub path: String,
    pub data: Vec<u8>,
    pub directory: bool,
}

#[derive(Clone, Copy, Default)]
pub struct Limits {
    pub max_entries: Option<i64>,
    pub max_entry_bytes: Option<i64>,
    pub max_total_bytes: Option<i64>,
}

fn budget(o: Option<i64>) -> Result<usize, Fail> {
    match o {
        None => Ok(usize::MAX),
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
    }
}

fn path_valid(s: &[u8], directory: bool) -> bool {
    if s.is_empty()
        || core::str::from_utf8(s).is_err()
        || s.iter().any(|&c| matches!(c, b'\\' | b':' | 0))
        || s[0] == b'/'
    {
        return false;
    }
    let mut s = s;
    if directory {
        if let Some(rest) = s.strip_suffix(b"/") {
            s = rest;
        }
    } else if s.ends_with(b"/") {
        return false;
    }
    s.split(|&c| c == b'/')
        .all(|p| !p.is_empty() && p != b"." && p != b"..")
}

/// A regular file sharing a normalised path with an ancestor directory of another entry.
fn conflict(kinds: &BTreeMap<Vec<u8>, bool>) -> bool {
    kinds.keys().any(|key| {
        let mut dir = key.as_slice();
        while let Some(i) = dir.iter().rposition(|&c| c == b'/') {
            dir = &dir[..i];
            if kinds.get(dir) == Some(&false) {
                return true;
            }
        }
        false
    })
}

fn clean(name: &[u8], directory: bool) -> Vec<u8> {
    let name = if directory {
        name.strip_suffix(b"/").unwrap_or(name)
    } else {
        name
    };
    name.to_vec()
}

pub fn pack(entries: &[Entry], format: &str, max_bytes: Option<i64>) -> Result<Vec<u8>, Fail> {
    let max = budget(max_bytes)?;
    let mut seen: BTreeMap<Vec<u8>, ()> = BTreeMap::new();
    let mut kinds: BTreeMap<Vec<u8>, bool> = BTreeMap::new();
    for e in entries {
        if !path_valid(e.path.as_bytes(), e.directory) || e.directory && !e.data.is_empty() {
            return Err(Fail::InvalidInput);
        }
        let key = clean(e.path.as_bytes(), e.directory);
        if seen.insert(key.clone(), ()).is_some() {
            return Err(Fail::InvalidData);
        }
        kinds.insert(key, e.directory);
    }
    if conflict(&kinds) {
        return Err(Fail::InvalidData);
    }
    let names: Vec<Vec<u8>> = entries
        .iter()
        .map(|e| {
            let mut n = clean(e.path.as_bytes(), e.directory);
            if e.directory {
                n.push(b'/');
            }
            n
        })
        .collect();
    let out = match format {
        "zip" => {
            if names.iter().any(|n| n.len() > 0xffff) {
                return Err(Fail::InvalidInput);
            }
            let members: Vec<zip::Member> = entries
                .iter()
                .zip(&names)
                .map(|(e, n)| zip::Member {
                    name: n,
                    data: &e.data,
                    dir: e.directory,
                })
                .collect();
            zip::pack(&members, 5, |data, level| {
                ms_std_compress::encode(data, ms_std_compress::Format::Deflate, level)
            })
        }
        "tar" => {
            let mut w = tar::Writer::new();
            for (e, n) in entries.iter().zip(&names) {
                w.entry(n, &e.data, e.directory)
                    .map_err(|_| Fail::LimitExceeded)?;
                if w.out.len() > max {
                    return Err(Fail::LimitExceeded);
                }
            }
            w.finish()
        }
        _ => return Err(Fail::Unsupported),
    };
    if out.len() > max {
        return Err(Fail::LimitExceeded);
    }
    Ok(out)
}

struct Collector {
    out: Vec<Entry>,
    seen: BTreeMap<Vec<u8>, ()>,
    kinds: BTreeMap<Vec<u8>, bool>,
    count: usize,
    entry_max: usize,
    total: usize,
}

impl Collector {
    /// Go's `add` closure; `body` yields the verified data when the checks before it pass.
    fn add(
        &mut self,
        name: &[u8],
        directory: bool,
        size: usize,
        body: impl FnOnce() -> Result<Vec<u8>, Fail>,
    ) -> Result<(), Fail> {
        if !path_valid(name, directory) {
            return Err(Fail::InvalidData);
        }
        let key = clean(name, directory);
        if self.seen.insert(key.clone(), ()).is_some() {
            return Err(Fail::InvalidData);
        }
        self.kinds.insert(key, directory);
        if self.out.len() >= self.count || size > self.entry_max || size > self.total {
            return Err(Fail::LimitExceeded);
        }
        let body = body()?;
        if body.len() > self.entry_max.min(self.total) {
            return Err(Fail::LimitExceeded);
        }
        if directory && !body.is_empty() {
            return Err(Fail::InvalidData);
        }
        self.total -= body.len();
        let path = String::from_utf8(clean(name, directory)).map_err(|_| Fail::InvalidData)?;
        self.out.push(Entry {
            path,
            data: body,
            directory,
        });
        Ok(())
    }
}

pub fn unpack(data: &[u8], format: &str, limits: Option<Limits>) -> Result<Vec<Entry>, Fail> {
    let l = limits.unwrap_or_default();
    let (count, entry_max, total) = (
        budget(l.max_entries)?,
        budget(l.max_entry_bytes)?,
        budget(l.max_total_bytes)?,
    );
    let mut c = Collector {
        out: Vec::new(),
        seen: BTreeMap::new(),
        kinds: BTreeMap::new(),
        count,
        entry_max,
        total,
    };
    match format {
        "tar" => {
            let mut r = tar::Reader::new(data);
            while let Some(item) = r.next().map_err(|_| Fail::InvalidData)? {
                let flag = item.header.typeflag;
                if flag != tar::TYPE_REG && flag != tar::TYPE_REG_A && flag != tar::TYPE_DIR {
                    return Err(Fail::Unsupported);
                }
                let size = usize::try_from(item.header.size).unwrap_or(usize::MAX);
                let (start, len) = item.data;
                let truncated = item.truncated;
                c.add(&item.header.name, flag == tar::TYPE_DIR, size, || {
                    if truncated {
                        return Err(Fail::InvalidData);
                    }
                    Ok(data[start..start + len].to_vec())
                })?;
            }
        }
        "zip" => {
            let files = zip::open_archive(data).map_err(|_| Fail::InvalidData)?;
            if files.len() > count {
                return Err(Fail::LimitExceeded);
            }
            for f in &files {
                let (regular, dir) = f.kind();
                if !f.name_utf8_ok() || (!regular && !dir) {
                    return Err(Fail::Unsupported);
                }
                let usize_ = usize::try_from(f.usize).unwrap_or(usize::MAX);
                if usize_ > entry_max || usize_ > c.total {
                    return Err(Fail::LimitExceeded);
                }
                // Go opens the member (header and algorithm checks) before `add` validates.
                f.check_open(data).map_err(|_| Fail::InvalidData)?;
                c.add(&f.name, dir, usize_, || {
                    f.read(data).map_err(|_| Fail::InvalidData)
                })?;
            }
        }
        _ => return Err(Fail::Unsupported),
    }
    let kinds = c.kinds;
    if conflict(&kinds) {
        return Err(Fail::InvalidData);
    }
    Ok(c.out)
}
