//! Zip reading and writing for `@std/archive`: end-of-central-directory search (with prefix data and zip64),
//! stored and deflated members, data descriptors and CRC verification.
use alloc::vec::Vec;
use ms_std_compress::{crc32, inflate};

use crate::tar::Bad;

const FILE_HEADER_SIG: u32 = 0x0403_4b50;
const DIR_HEADER_SIG: u32 = 0x0201_4b50;
const DIR_END_SIG: u32 = 0x0605_4b50;
const DIR64_END_SIG: u32 = 0x0606_4b50;
const DIR64_LOC_SIG: u32 = 0x0706_4b50;
const DATA_DESC_SIG: u32 = 0x0807_4b50;
const FILE_HEADER_LEN: usize = 30;
const DIR_HEADER_LEN: usize = 46;
const DIR_END_LEN: usize = 22;
const DIR64_END_LEN: usize = 56;
const DIR64_LOC_LEN: usize = 20;

const CREATOR_FAT: u16 = 0;
const CREATOR_UNIX: u16 = 3;
const CREATOR_NTFS: u16 = 11;
const CREATOR_VFAT: u16 = 14;
const CREATOR_MAC: u16 = 19;

fn u16le(b: &[u8], at: usize) -> u16 {
    u16::from_le_bytes([b[at], b[at + 1]])
}
fn u32le(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}
fn u64le(b: &[u8], at: usize) -> u64 {
    let mut a = [0u8; 8];
    a.copy_from_slice(&b[at..at + 8]);
    u64::from_le_bytes(a)
}

pub struct File {
    pub name: Vec<u8>,
    creator: u16,
    flags: u16,
    method: u16,
    crc32: u32,
    csize: u64,
    pub usize: u64,
    attrs: u32,
    offset: i64,
}

struct End {
    records: u64,
    size: u64,
    offset: u64,
}

fn find_end(data: &[u8]) -> Result<(usize, usize), Bad> {
    let size = data.len();
    for (i, mut len) in [1024usize, 65 * 1024].into_iter().enumerate() {
        if len > size {
            len = size;
        }
        let buf = &data[size - len..];
        let found = (0..=buf.len().wrapping_sub(DIR_END_LEN))
            .rev()
            .take_while(|_| buf.len() >= DIR_END_LEN)
            .find(|&at| buf[at..at + 4] == *b"PK\x05\x06")
            .map(|at| {
                let n = usize::from(buf[at + DIR_END_LEN - 2])
                    | usize::from(buf[at + DIR_END_LEN - 1]) << 8;
                (at, n + DIR_END_LEN + at > buf.len())
            });
        match found {
            Some((_, true)) => {
                // Go returns "not found" for this block rather than scanning on.
                if i == 1 || len == size {
                    return Err(Bad);
                }
            }
            Some((at, false)) => return Ok((size - len + at, at)),
            None => {
                if i == 1 || len == size {
                    return Err(Bad);
                }
            }
        }
    }
    Err(Bad)
}

fn read_dir_header(rd: &mut &[u8]) -> Result<File, DirErr> {
    if rd.is_empty() {
        return Err(DirErr::Eof);
    }
    if rd.len() < DIR_HEADER_LEN {
        *rd = &[];
        return Err(DirErr::Short);
    }
    let b = &rd[..DIR_HEADER_LEN];
    if u32le(b, 0) != DIR_HEADER_SIG {
        *rd = &rd[4..];
        return Err(DirErr::Format);
    }
    let name_len = usize::from(u16le(b, 28));
    let extra_len = usize::from(u16le(b, 30));
    let comment_len = usize::from(u16le(b, 32));
    let mut f = File {
        name: Vec::new(),
        creator: u16le(b, 4),
        flags: u16le(b, 8),
        method: u16le(b, 10),
        crc32: u32le(b, 16),
        csize: u64::from(u32le(b, 20)),
        usize: u64::from(u32le(b, 24)),
        attrs: u32le(b, 38),
        offset: i64::from(u32le(b, 42)),
    };
    let (c32, u32_, off32) = (u32le(b, 20), u32le(b, 24), u32le(b, 42));
    let total = name_len + extra_len + comment_len;
    let rest = &rd[DIR_HEADER_LEN..];
    if rest.len() < total {
        let eof = rest.is_empty() && total > 0;
        *rd = &[];
        return Err(if eof { DirErr::Eof } else { DirErr::Short });
    }
    f.name = rest[..name_len].to_vec();
    let extra = &rest[name_len..name_len + extra_len];
    *rd = &rest[total..];

    let (mut need_u, mut need_c, mut need_off) =
        (u32_ == u32::MAX, c32 == u32::MAX, off32 == u32::MAX);
    let mut e = extra;
    while e.len() >= 4 {
        let tag = u16le(e, 0);
        let size = usize::from(u16le(e, 2));
        e = &e[4..];
        if e.len() < size {
            break;
        }
        let mut field = &e[..size];
        e = &e[size..];
        if tag == 0x0001 {
            for (need, slot) in [(&mut need_u, 0), (&mut need_c, 1), (&mut need_off, 2)] {
                if *need {
                    *need = false;
                    if field.len() < 8 {
                        return Err(DirErr::Format);
                    }
                    let v = u64le(field, 0);
                    field = &field[8..];
                    match slot {
                        0 => f.usize = v,
                        1 => f.csize = v,
                        _ => f.offset = v as i64,
                    }
                }
            }
        }
    }
    if need_c || need_off {
        return Err(DirErr::Format);
    }
    Ok(f)
}

enum DirErr {
    /// No bytes were available (`io.EOF`): a hard error in Go's loop.
    Eof,
    /// `io.ErrUnexpectedEOF`.
    Short,
    /// `ErrFormat`.
    Format,
}

/// Opens an archive held in memory; the members in central-directory order.
pub fn open_archive(data: &[u8]) -> Result<Vec<File>, Bad> {
    let (end_at, _) = find_end(data)?;
    let size = data.len() as i64;
    let b = &data[end_at + 4..];
    let mut end = End {
        records: u64::from(u16le(b, 6)),
        size: u64::from(u32le(b, 8)),
        offset: u64::from(u32le(b, 12)),
    };
    let mut end_offset = end_at as i64;
    if end.records == 0xffff || end.size == 0xffff || end.offset == 0xffff_ffff {
        let loc = end_offset - DIR64_LOC_LEN as i64;
        if loc >= 0 {
            let l = data
                .get(loc as usize..loc as usize + DIR64_LOC_LEN)
                .ok_or(Bad)?;
            if u32le(l, 0) == DIR64_LOC_SIG && u32le(l, 4) == 0 && u32le(l, 16) == 1 {
                let p = u64le(l, 8) as i64;
                end_offset = p;
                let e = usize::try_from(p)
                    .ok()
                    .and_then(|p| data.get(p..p.checked_add(DIR64_END_LEN)?))
                    .ok_or(Bad)?;
                if u32le(e, 0) != DIR64_END_SIG {
                    return Err(Bad);
                }
                end.records = u64le(e, 32);
                end.size = u64le(e, 40);
                end.offset = u64le(e, 48);
            }
        }
    }
    let max = i64::MAX as u64;
    if end.size > max || end.offset > max {
        return Err(Bad);
    }
    let mut base = end_offset
        .wrapping_sub(end.size as i64)
        .wrapping_sub(end.offset as i64);
    let o = base.wrapping_add(end.offset as i64);
    if o < 0 || o >= size {
        return Err(Bad);
    }
    if base > 0 {
        let off = end.offset as i64;
        if off <= size {
            let mut probe: &[u8] = &data[off as usize..];
            if read_dir_header(&mut probe).is_ok() {
                base = 0;
            }
        }
    }
    let o = base.wrapping_add(end.offset as i64);
    let mut rd: &[u8] = data.get(o as usize..).ok_or(Bad)?;
    let mut files = Vec::new();
    let last: Option<DirErr> = loop {
        match read_dir_header(&mut rd) {
            Ok(mut f) => {
                f.offset = f.offset.wrapping_add(base);
                files.push(f);
            }
            Err(DirErr::Eof) => return Err(Bad),
            Err(e) => break Some(e),
        }
    };
    let _ = last;
    if files.len() as u16 != end.records as u16 {
        return Err(Bad);
    }
    Ok(files)
}

fn detect_utf8_valid(s: &[u8]) -> bool {
    core::str::from_utf8(s).is_ok()
}

impl File {
    /// `(is_regular, is_dir)` per `FileHeader.Mode`.
    pub fn kind(&self) -> (bool, bool) {
        const S_IFMT: u32 = 0xf000;
        let mut is_dir = false;
        let mut irregular = false;
        match self.creator >> 8 {
            CREATOR_UNIX | CREATOR_MAC => {
                let m = self.attrs >> 16;
                match m & S_IFMT {
                    0x6000 | 0x2000 | 0x1000 | 0xa000 | 0xc000 => irregular = true,
                    0x4000 => is_dir = true,
                    _ => {}
                }
            }
            CREATOR_NTFS | CREATOR_VFAT | CREATOR_FAT => is_dir = self.attrs & 0x10 != 0,
            _ => {}
        }
        if self.name.last() == Some(&b'/') {
            is_dir = true;
        }
        (!is_dir && !irregular, is_dir)
    }

    pub fn name_utf8_ok(&self) -> bool {
        detect_utf8_valid(&self.name)
    }

    /// Offset of the member body after validating its local header (Go's `findBodyOffset`).
    fn body_offset(&self, data: &[u8]) -> Result<usize, Bad> {
        let off = usize::try_from(self.offset).map_err(|_| Bad)?;
        let hdr = data
            .get(off..off.checked_add(FILE_HEADER_LEN).ok_or(Bad)?)
            .ok_or(Bad)?;
        if u32le(hdr, 0) != FILE_HEADER_SIG {
            return Err(Bad);
        }
        Ok(off + FILE_HEADER_LEN + usize::from(u16le(hdr, 26)) + usize::from(u16le(hdr, 28)))
    }

    /// The failures of Go's `File.Open`: a bad local header or an unsupported method.
    pub fn check_open(&self, data: &[u8]) -> Result<(), Bad> {
        self.body_offset(data)?;
        if self.name.last() != Some(&b'/') && self.method != 0 && self.method != 8 {
            return Err(Bad);
        }
        Ok(())
    }

    /// Fully verifies and returns the member body (a read to EOF through the checksum reader).
    pub fn read(&self, data: &[u8]) -> Result<Vec<u8>, Bad> {
        let body = self.body_offset(data)?;
        if self.name.last() == Some(&b'/') {
            return if self.usize == 0 {
                Ok(Vec::new())
            } else {
                Err(Bad)
            };
        }
        // SectionReader semantics: a body running past the file is simply short.
        let avail = data.get(body..).unwrap_or(&[]);
        let stored = &avail[..avail
            .len()
            .min(usize::try_from(self.csize).unwrap_or(usize::MAX))];
        let out = if self.method == 0 {
            if stored.len() as u64 != self.csize || self.csize > self.usize {
                return Err(Bad);
            }
            stored.to_vec()
        } else {
            let room = usize::try_from(self.usize).unwrap_or(usize::MAX - 1);
            inflate(stored, room).map_err(|_| Bad)?.0
        };
        if out.len() as u64 != self.usize {
            return Err(Bad);
        }
        let sum = crc32(0, &out);
        if self.flags & 0x8 != 0 {
            let at = body
                .checked_add(usize::try_from(self.csize).map_err(|_| Bad)?)
                .ok_or(Bad)?;
            let d = data.get(at..).unwrap_or(&[]);
            let d = &d[..d.len().min(16)];
            // A leading signature is optional; either way the CRC is followed by two sizes.
            let (crc_at, need) = if d.len() >= 4 && u32le(d, 0) == DATA_DESC_SIG {
                (4, 16)
            } else {
                (0, 12)
            };
            if d.len() < need || u32le(d, crc_at) != self.crc32 || sum != self.crc32 {
                return Err(Bad);
            }
        } else if self.crc32 != 0 && sum != self.crc32 {
            return Err(Bad);
        }
        Ok(out)
    }
}

// ---- writing ----

pub struct Member<'a> {
    pub name: &'a [u8],
    pub data: &'a [u8],
    pub dir: bool,
}

fn needs_utf8_flag(name: &[u8]) -> bool {
    match core::str::from_utf8(name) {
        Ok(s) => s
            .chars()
            .any(|c| (c as u32) < 0x20 || (c as u32) > 0x7d || c == '\\'),
        Err(_) => false,
    }
}

pub fn pack(
    members: &[Member],
    level: u8,
    mut deflate: impl FnMut(&[u8], u8) -> Vec<u8>,
) -> Vec<u8> {
    // 1980-01-01 00:00:00 UTC in DOS and Unix time.
    const DOS_DATE: u16 = 1 << 5 | 1;
    const UNIX_1980: u32 = 315_532_800;
    let mut out: Vec<u8> = Vec::new();
    struct Rec {
        flags: u16,
        method: u16,
        crc: u32,
        csize: u32,
        usize: u32,
        attrs: u32,
        offset: u32,
        zip64: bool,
        csize64: u64,
        usize64: u64,
        offset64: u64,
    }
    let mut dir: Vec<Rec> = Vec::new();
    let extra = {
        let mut e = Vec::new();
        e.extend_from_slice(&0x5455u16.to_le_bytes());
        e.extend_from_slice(&5u16.to_le_bytes());
        e.push(1);
        e.extend_from_slice(&UNIX_1980.to_le_bytes());
        e
    };
    for m in members {
        let mut flags: u16 = if needs_utf8_flag(m.name) { 0x800 } else { 0 };
        let offset = out.len() as u64;
        let (method, body, crc, usize_) = if m.dir {
            (0u16, Vec::new(), 0u32, 0u64)
        } else {
            flags |= 0x8;
            let method = if m.data.len() < 64 { 0 } else { 8 };
            let body = if method == 8 {
                deflate(m.data, level)
            } else {
                m.data.to_vec()
            };
            (method, body, crc32(0, m.data), m.data.len() as u64)
        };
        let csize = body.len() as u64;
        let zip64 = csize >= u64::from(u32::MAX) || usize_ >= u64::from(u32::MAX);
        // Local header.
        out.extend_from_slice(&FILE_HEADER_SIG.to_le_bytes());
        out.extend_from_slice(&(if zip64 { 45u16 } else { 20u16 }).to_le_bytes());
        out.extend_from_slice(&flags.to_le_bytes());
        out.extend_from_slice(&method.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&DOS_DATE.to_le_bytes());
        out.extend_from_slice(&[0; 12]);
        out.extend_from_slice(&(m.name.len() as u16).to_le_bytes());
        out.extend_from_slice(&(extra.len() as u16).to_le_bytes());
        out.extend_from_slice(m.name);
        out.extend_from_slice(&extra);
        out.extend_from_slice(&body);
        if !m.dir {
            out.extend_from_slice(&DATA_DESC_SIG.to_le_bytes());
            out.extend_from_slice(&crc.to_le_bytes());
            if zip64 {
                out.extend_from_slice(&csize.to_le_bytes());
                out.extend_from_slice(&usize_.to_le_bytes());
            } else {
                out.extend_from_slice(&(csize as u32).to_le_bytes());
                out.extend_from_slice(&(usize_ as u32).to_le_bytes());
            }
        }
        let attrs = if m.dir {
            (0x41c0u32 << 16) | 0x10
        } else {
            0x8180u32 << 16
        };
        dir.push(Rec {
            flags,
            method,
            crc,
            csize: csize as u32,
            usize: usize_ as u32,
            attrs,
            offset: offset as u32,
            zip64,
            csize64: csize,
            usize64: usize_,
            offset64: offset,
        });
    }
    let start = out.len() as u64;
    for (m, r) in members.iter().zip(&dir) {
        let big = r.zip64 || r.offset64 >= u64::from(u32::MAX);
        let mut ex = extra.clone();
        if big {
            ex.extend_from_slice(&1u16.to_le_bytes());
            ex.extend_from_slice(&24u16.to_le_bytes());
            ex.extend_from_slice(&r.usize64.to_le_bytes());
            ex.extend_from_slice(&r.csize64.to_le_bytes());
            ex.extend_from_slice(&r.offset64.to_le_bytes());
        }
        out.extend_from_slice(&DIR_HEADER_SIG.to_le_bytes());
        out.extend_from_slice(&0x0314u16.to_le_bytes());
        out.extend_from_slice(&(if r.zip64 { 45u16 } else { 20u16 }).to_le_bytes());
        out.extend_from_slice(&r.flags.to_le_bytes());
        out.extend_from_slice(&r.method.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&DOS_DATE.to_le_bytes());
        out.extend_from_slice(&r.crc.to_le_bytes());
        if big {
            out.extend_from_slice(&u32::MAX.to_le_bytes());
            out.extend_from_slice(&u32::MAX.to_le_bytes());
        } else {
            out.extend_from_slice(&r.csize.to_le_bytes());
            out.extend_from_slice(&r.usize.to_le_bytes());
        }
        out.extend_from_slice(&(m.name.len() as u16).to_le_bytes());
        out.extend_from_slice(&(ex.len() as u16).to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&[0; 4]);
        out.extend_from_slice(&r.attrs.to_le_bytes());
        out.extend_from_slice(
            &(if r.offset64 > u64::from(u32::MAX) {
                u32::MAX
            } else {
                r.offset
            })
            .to_le_bytes(),
        );
        out.extend_from_slice(m.name);
        out.extend_from_slice(&ex);
    }
    let end = out.len() as u64;
    let (mut records, mut size, mut offset) = (members.len() as u64, end - start, start);
    if records >= 0xffff || size >= u64::from(u32::MAX) || offset >= u64::from(u32::MAX) {
        out.extend_from_slice(&DIR64_END_SIG.to_le_bytes());
        out.extend_from_slice(&((DIR64_END_LEN - 12) as u64).to_le_bytes());
        out.extend_from_slice(&45u16.to_le_bytes());
        out.extend_from_slice(&45u16.to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes());
        out.extend_from_slice(&records.to_le_bytes());
        out.extend_from_slice(&records.to_le_bytes());
        out.extend_from_slice(&size.to_le_bytes());
        out.extend_from_slice(&offset.to_le_bytes());
        out.extend_from_slice(&DIR64_LOC_SIG.to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes());
        out.extend_from_slice(&end.to_le_bytes());
        out.extend_from_slice(&1u32.to_le_bytes());
        records = 0xffff;
        size = u64::from(u32::MAX);
        offset = u64::from(u32::MAX);
    }
    out.extend_from_slice(&DIR_END_SIG.to_le_bytes());
    out.extend_from_slice(&[0; 4]);
    out.extend_from_slice(&(records as u16).to_le_bytes());
    out.extend_from_slice(&(records as u16).to_le_bytes());
    out.extend_from_slice(&(size as u32).to_le_bytes());
    out.extend_from_slice(&(offset as u32).to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out
}
