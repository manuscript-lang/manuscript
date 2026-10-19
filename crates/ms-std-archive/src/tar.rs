//! Tar reading and writing with the behavior of Go's `archive/tar` as used by
//! `pkg/runtime/archive.go`: USTAR, GNU long names and PAX records are read; writing emits
//! USTAR headers when the path fits and PAX path records otherwise, with deterministic metadata.
use alloc::collections::BTreeMap;
use alloc::string::String;
use alloc::vec::Vec;

const BLOCK: usize = 512;

pub const TYPE_REG: u8 = b'0';
pub const TYPE_REG_A: u8 = 0;
pub const TYPE_DIR: u8 = b'5';
const TYPE_X_HEADER: u8 = b'x';
const TYPE_X_GLOBAL: u8 = b'g';
const TYPE_GNU_LONG_NAME: u8 = b'L';
const TYPE_GNU_LONG_LINK: u8 = b'K';
const TYPE_GNU_SPARSE: u8 = b'S';
const MAX_SPECIAL: usize = 1 << 20;

/// A header failure; the runtime reports all of them as invalid data.
#[derive(Debug, PartialEq, Eq)]
pub struct Bad;

pub struct Header {
    pub name: Vec<u8>,
    pub typeflag: u8,
    pub size: i64,
}

/// One entry returned by [`Reader::next`]: the header and where its data section lies.
pub struct Item {
    pub header: Header,
    /// Offset and length of the data bytes inside the archive (empty for header-only types).
    pub data: (usize, usize),
    /// Declared data was not fully present (read of the body fails).
    pub truncated: bool,
}

pub struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
    pad: usize,
}

fn parse_string(b: &[u8]) -> &[u8] {
    match b.iter().position(|&c| c == 0) {
        Some(i) => &b[..i],
        None => b,
    }
}

fn parse_octal(b: &[u8]) -> Result<i64, Bad> {
    let trimmed: &[u8] = {
        let is_pad = |c: &u8| *c == b' ' || *c == 0;
        let start = b.iter().position(|c| !is_pad(c)).unwrap_or(b.len());
        let end = b.iter().rposition(|c| !is_pad(c)).map_or(start, |i| i + 1);
        &b[start..end]
    };
    if trimmed.is_empty() {
        return Ok(0);
    }
    let s = parse_string(trimmed);
    let mut x: u64 = 0;
    if s.is_empty() {
        return Err(Bad);
    }
    for &c in s {
        if !(b'0'..=b'7').contains(&c) {
            return Err(Bad);
        }
        x = x
            .checked_mul(8)
            .and_then(|x| x.checked_add(u64::from(c - b'0')))
            .ok_or(Bad)?;
    }
    Ok(x as i64)
}

fn parse_numeric(b: &[u8]) -> Result<i64, Bad> {
    if b.first().is_some_and(|c| c & 0x80 != 0) {
        let inv: u8 = if b[0] & 0x40 != 0 { 0xff } else { 0 };
        let mut x: u64 = 0;
        for (i, &c) in b.iter().enumerate() {
            let mut c = c ^ inv;
            if i == 0 {
                c &= 0x7f;
            }
            if x >> 56 > 0 {
                return Err(Bad);
            }
            x = x << 8 | u64::from(c);
        }
        if x >> 63 > 0 {
            return Err(Bad);
        }
        return Ok(if inv == 0xff { !(x as i64) } else { x as i64 });
    }
    parse_octal(b)
}

#[derive(PartialEq, Eq, Clone, Copy)]
enum Format {
    Unknown,
    V7,
    UstarPax,
    Star,
    Gnu,
}

fn checksums(b: &[u8; BLOCK]) -> (i64, i64) {
    let (mut unsigned, mut signed) = (0i64, 0i64);
    for (i, &c) in b.iter().enumerate() {
        let c = if (148..156).contains(&i) { b' ' } else { c };
        unsigned += i64::from(c);
        signed += i64::from(c as i8);
    }
    (unsigned, signed)
}

fn block_format(b: &[u8; BLOCK]) -> Format {
    let Ok(value) = parse_octal(&b[148..156]) else {
        return Format::Unknown;
    };
    let (u, s) = checksums(b);
    if value != u && value != s {
        return Format::Unknown;
    }
    let magic = &b[257..263];
    let version = &b[263..265];
    let trailer = &b[508..512];
    if magic == b"ustar\0" && trailer == b"tar\0" {
        Format::Star
    } else if magic == b"ustar\0" {
        Format::UstarPax
    } else if magic == b"ustar " && version == b" \0" {
        Format::Gnu
    } else {
        Format::V7
    }
}

fn is_header_only(flag: u8) -> bool {
    matches!(flag, b'1'..=b'6')
}

fn padding(n: i64) -> usize {
    ((-n) & (BLOCK as i64 - 1)) as usize
}

fn is_ascii(s: &[u8]) -> bool {
    s.iter().all(|&c| c < 0x80 && c != 0)
}

fn parse_dec(s: &[u8]) -> Result<i64, Bad> {
    let t = core::str::from_utf8(s).map_err(|_| Bad)?;
    t.parse::<i64>().map_err(|_| Bad)
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Reader {
            data,
            pos: 0,
            pad: 0,
        }
    }

    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.data.get(self.pos..self.pos.checked_add(n)?)?;
        self.pos += n;
        Some(s)
    }

    fn read_header(&mut self) -> Result<Option<(Header, Format)>, Bad> {
        let rest = &self.data[self.pos.min(self.data.len())..];
        if rest.is_empty() {
            return Ok(None);
        }
        let Some(blk) = self.take(BLOCK) else {
            return Err(Bad);
        };
        let blk: &[u8; BLOCK] = blk.try_into().map_err(|_| Bad)?;
        if blk.iter().all(|&c| c == 0) {
            if self.pos >= self.data.len() {
                return Ok(None);
            }
            let Some(second) = self.take(BLOCK) else {
                return Err(Bad);
            };
            return if second.iter().all(|&c| c == 0) {
                Ok(None)
            } else {
                Err(Bad)
            };
        }
        let format = block_format(blk);
        if format == Format::Unknown {
            return Err(Bad);
        }
        let mut name = parse_string(&blk[0..100]).to_vec();
        let typeflag = blk[156];
        let size = parse_numeric(&blk[124..136])?;
        parse_numeric(&blk[100..108])?;
        parse_numeric(&blk[108..116])?;
        parse_numeric(&blk[116..124])?;
        parse_numeric(&blk[136..148])?;
        let mut prefix: Vec<u8> = Vec::new();
        if format != Format::V7 {
            parse_numeric(&blk[329..337])?;
            parse_numeric(&blk[337..345])?;
            match format {
                Format::UstarPax => prefix = parse_string(&blk[345..500]).to_vec(),
                Format::Star => {
                    prefix = parse_string(&blk[345..476]).to_vec();
                    parse_numeric(&blk[476..488])?;
                    parse_numeric(&blk[488..500])?;
                }
                Format::Gnu => {
                    let times_ok = |r: &[u8]| r[0] == 0 || parse_numeric(r).is_ok();
                    if !(times_ok(&blk[345..357]) && times_ok(&blk[357..369])) {
                        // Pre-Go1.8 writers: the fields are really the USTAR prefix.
                        let p = parse_string(&blk[345..500]);
                        if is_ascii(p) {
                            prefix = p.to_vec();
                        }
                    }
                }
                _ => {}
            }
        }
        if !prefix.is_empty() {
            let mut full = prefix;
            full.push(b'/');
            full.extend_from_slice(&name);
            name = full;
        }
        Ok(Some((
            Header {
                name,
                typeflag,
                size,
            },
            format,
        )))
    }

    /// Reads a PAX/GNU special file of `size` bytes.
    fn special(&mut self, size: i64) -> Result<&'a [u8], Bad> {
        let size = usize::try_from(size).map_err(|_| Bad)?;
        if size > MAX_SPECIAL {
            return Err(Bad);
        }
        self.take(size).ok_or(Bad)
    }

    /// Advances to the next regular entry; `Ok(None)` is the end of the archive.
    pub fn next(&mut self) -> Result<Option<Item>, Bad> {
        let mut pax: Option<BTreeMap<Vec<u8>, Vec<u8>>> = None;
        let mut gnu_name: Option<Vec<u8>> = None;
        loop {
            // Padding after the previous data section; a short tail is a clean end.
            if self.take(self.pad).is_none() {
                return Ok(None);
            }
            self.pad = 0;
            let Some((mut hdr, format)) = self.read_header()? else {
                return Ok(None);
            };
            let nb = if is_header_only(hdr.typeflag) {
                0
            } else {
                hdr.size
            };
            if nb < 0 {
                return Err(Bad);
            }
            self.pad = padding(nb);
            match hdr.typeflag {
                TYPE_X_HEADER | TYPE_X_GLOBAL => {
                    let body = self.special(nb)?;
                    let records = parse_pax(body)?;
                    if hdr.typeflag == TYPE_X_GLOBAL {
                        merge_pax(&mut hdr, &records)?;
                        return Ok(Some(Item {
                            header: Header {
                                name: hdr.name,
                                typeflag: TYPE_X_GLOBAL,
                                size: 0,
                            },
                            data: (self.pos, 0),
                            truncated: false,
                        }));
                    }
                    pax = Some(records);
                    continue;
                }
                TYPE_GNU_LONG_NAME | TYPE_GNU_LONG_LINK => {
                    let body = self.special(nb)?;
                    if hdr.typeflag == TYPE_GNU_LONG_NAME {
                        gnu_name = Some(parse_string(body).to_vec());
                    }
                    continue;
                }
                _ => {}
            }
            let old_sparse = hdr.typeflag == TYPE_GNU_SPARSE;
            if let Some(records) = &pax {
                merge_pax(&mut hdr, records)?;
            }
            if let Some(n) = gnu_name.take().filter(|n| !n.is_empty()) {
                hdr.name = n;
            }
            if hdr.typeflag == TYPE_REG_A {
                hdr.typeflag = if hdr.name.last() == Some(&b'/') {
                    TYPE_DIR
                } else {
                    TYPE_REG
                };
            }
            let nb = if is_header_only(hdr.typeflag) {
                0
            } else {
                hdr.size
            };
            if nb < 0 {
                return Err(Bad);
            }
            self.pad = padding(nb);
            if old_sparse && format != Format::Gnu {
                return Err(Bad);
            }
            let nb = nb as u64;
            let avail = (self.data.len() - self.pos.min(self.data.len())) as u64;
            let (start, truncated) = (self.pos, avail < nb);
            let len = if truncated { avail } else { nb } as usize;
            self.pos += len;
            return Ok(Some(Item {
                header: hdr,
                data: (start, len),
                truncated,
            }));
        }
    }
}

fn parse_pax(mut s: &[u8]) -> Result<BTreeMap<Vec<u8>, Vec<u8>>, Bad> {
    let mut out = BTreeMap::new();
    let mut sparse_offsets = 0usize;
    while !s.is_empty() {
        let sp = s.iter().position(|&c| c == b' ').ok_or(Bad)?;
        let n = parse_dec(&s[..sp])?;
        if n < 5 || n > s.len() as i64 {
            return Err(Bad);
        }
        let n = n as usize - (sp + 1);
        if n == 0 {
            return Err(Bad);
        }
        let rest = &s[sp + 1..];
        let (rec, nl, rem) = (&rest[..n - 1], rest[n - 1], &rest[n..]);
        if nl != b'\n' {
            return Err(Bad);
        }
        let eq = rec.iter().position(|&c| c == b'=').ok_or(Bad)?;
        let (k, v) = (&rec[..eq], &rec[eq + 1..]);
        let has_nul = |x: &[u8]| x.contains(&0);
        let valid = !k.is_empty()
            && !k.contains(&b'=')
            && match k {
                b"path" | b"linkpath" | b"uname" | b"gname" => !has_nul(v),
                _ => !has_nul(k),
            };
        if !valid {
            return Err(Bad);
        }
        s = rem;
        if k == b"GNU.sparse.offset" || k == b"GNU.sparse.numbytes" {
            let want_offset = sparse_offsets.is_multiple_of(2);
            if (want_offset && k != b"GNU.sparse.offset")
                || (!want_offset && k != b"GNU.sparse.numbytes")
                || v.contains(&b',')
            {
                return Err(Bad);
            }
            sparse_offsets += 1;
            out.entry(b"GNU.sparse.map".to_vec())
                .or_insert_with(Vec::new);
        } else {
            out.insert(k.to_vec(), v.to_vec());
        }
    }
    Ok(out)
}

fn merge_pax(hdr: &mut Header, records: &BTreeMap<Vec<u8>, Vec<u8>>) -> Result<(), Bad> {
    for (k, v) in records {
        if v.is_empty() {
            continue;
        }
        match k.as_slice() {
            b"path" => hdr.name = v.clone(),
            b"uid" | b"gid" => {
                parse_dec(v)?;
            }
            b"atime" | b"mtime" | b"ctime" => parse_pax_time(v)?,
            b"size" => hdr.size = parse_dec(v)?,
            _ => {}
        }
    }
    if records.keys().any(|k| k.starts_with(b"GNU.sparse.")) {
        // Sparse members are expanded by Go; treat them as unsupported typeflags instead.
        hdr.typeflag = TYPE_GNU_SPARSE;
    }
    Ok(())
}

fn parse_pax_time(s: &[u8]) -> Result<(), Bad> {
    let (secs, frac) = match s.iter().position(|&c| c == b'.') {
        Some(i) => (&s[..i], &s[i + 1..]),
        None => (s, &b""[..]),
    };
    parse_dec(secs)?;
    if !frac.iter().all(u8::is_ascii_digit) {
        return Err(Bad);
    }
    Ok(())
}

// ---- writing ----

fn octal(field: &mut [u8], x: u64) {
    let s = alloc::format!("{x:o}");
    let width = field.len() - 1;
    let mut text = String::new();
    for _ in s.len()..width {
        text.push('0');
    }
    text.push_str(&s);
    put_string(field, text.as_bytes());
}

fn put_string(field: &mut [u8], s: &[u8]) {
    let n = s.len().min(field.len());
    field[..n].copy_from_slice(&s[..n]);
    if s.len() < field.len() {
        field[s.len()] = 0;
    }
    if s.len() > field.len() && field[field.len() - 1] == b'/' {
        let trimmed = &s[..field.len() - 1];
        let end = trimmed
            .iter()
            .rposition(|&c| c != b'/')
            .map_or(0, |i| i + 1);
        field[end] = 0;
    }
}

fn finish_block(b: &mut [u8; BLOCK]) {
    b[148..156].fill(b' ');
    let (sum, _) = checksums(b);
    octal(&mut b[148..155], sum as u64);
    b[155] = b' ';
}

fn split_ustar(name: &[u8]) -> Option<(&[u8], &[u8])> {
    let mut length = name.len();
    if length <= 100 || !is_ascii(name) {
        return None;
    }
    if length > 156 {
        length = 156;
    } else if name[length - 1] == b'/' {
        length -= 1;
    }
    let i = name[..length].iter().rposition(|&c| c == b'/')?;
    let nlen = name.len() - i - 1;
    if i == 0 || nlen > 100 || nlen == 0 || i > 155 {
        return None;
    }
    Some((&name[..i], &name[i + 1..]))
}

fn pax_record(key: &str, value: &[u8]) -> Vec<u8> {
    let base = key.len() + value.len() + 3;
    let mut size = base + alloc::format!("{base}").len();
    let mut rec = alloc::format!("{size} {key}=").into_bytes();
    rec.extend_from_slice(value);
    rec.push(b'\n');
    if rec.len() != size {
        size = rec.len();
        rec = alloc::format!("{size} {key}=").into_bytes();
        rec.extend_from_slice(value);
        rec.push(b'\n');
    }
    rec
}

fn clean_join(dir: &[u8], mid: &[u8], file: &[u8]) -> Vec<u8> {
    // path.Join(dir, mid, file) for already-clean components.
    let mut parts: Vec<&[u8]> = Vec::new();
    for p in [dir, mid, file] {
        for seg in p.split(|&c| c == b'/') {
            match seg {
                b"" | b"." => {}
                b".." => {
                    if parts.last().is_some_and(|l| *l != b"..") {
                        parts.pop();
                    } else if !dir.starts_with(b"/") {
                        parts.push(seg);
                    }
                }
                _ => parts.push(seg),
            }
        }
    }
    let mut out = Vec::new();
    for (i, p) in parts.iter().enumerate() {
        if i > 0 {
            out.push(b'/');
        }
        out.extend_from_slice(p);
    }
    out
}

fn to_ascii(s: &[u8]) -> Vec<u8> {
    s.iter().copied().filter(|&c| c < 0x80 && c != 0).collect()
}

pub struct Writer {
    pub out: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Writer { out: Vec::new() }
    }

    fn pad(&mut self) {
        let n = padding(self.out.len() as i64);
        self.out.resize(self.out.len() + n, 0);
    }

    /// Writes one entry (`dir` for directories: `name` then ends in '/', `data` is empty).
    pub fn entry(&mut self, name: &[u8], data: &[u8], dir: bool) -> Result<(), Bad> {
        let mode = if dir { 0o700 } else { 0o600 };
        let flag = if dir { TYPE_DIR } else { TYPE_REG };
        let size = if dir { 0 } else { data.len() as u64 };
        if size >= 1 << 33 {
            return Err(Bad);
        }
        let ustar = (name.len() <= 100 && is_ascii(name)) || split_ustar(name).is_some();
        let mut b = [0u8; BLOCK];
        if ustar {
            let (prefix, suffix) = split_ustar(name).unwrap_or((&[], name));
            put_string(&mut b[0..100], suffix);
            put_string(&mut b[345..500], prefix);
        } else {
            let rec = pax_record("path", name);
            let (dir_part, file_part) = match name.iter().rposition(|&c| c == b'/') {
                Some(i) => (&name[..=i], &name[i + 1..]),
                None => (&b""[..], name),
            };
            let pax_name = clean_join(dir_part, b"PaxHeaders.0", file_part);
            let mut pax_name = to_ascii(&pax_name);
            pax_name.truncate(100);
            while pax_name.last() == Some(&b'/') {
                pax_name.pop();
            }
            self.raw_pax(&pax_name, &rec);
            put_string(&mut b[0..100], &to_ascii(name));
        }
        octal(&mut b[100..108], mode);
        octal(&mut b[108..116], 0);
        octal(&mut b[116..124], 0);
        octal(&mut b[124..136], size);
        octal(&mut b[136..148], 0);
        b[156] = flag;
        octal(&mut b[329..337], 0);
        octal(&mut b[337..345], 0);
        b[257..263].copy_from_slice(b"ustar\0");
        b[263..265].copy_from_slice(b"00");
        finish_block(&mut b);
        self.out.extend_from_slice(&b);
        if !dir {
            self.out.extend_from_slice(data);
        }
        self.pad();
        Ok(())
    }

    fn raw_pax(&mut self, name: &[u8], data: &[u8]) {
        let mut b = [0u8; BLOCK];
        put_string(&mut b[0..100], name);
        octal(&mut b[100..108], 0);
        octal(&mut b[108..116], 0);
        octal(&mut b[116..124], 0);
        octal(&mut b[124..136], data.len() as u64);
        octal(&mut b[136..148], 0);
        b[156] = TYPE_X_HEADER;
        b[257..263].copy_from_slice(b"ustar\0");
        b[263..265].copy_from_slice(b"00");
        finish_block(&mut b);
        self.out.extend_from_slice(&b);
        self.out.extend_from_slice(data);
        self.pad();
    }

    pub fn finish(mut self) -> Vec<u8> {
        self.out.resize(self.out.len() + 2 * BLOCK, 0);
        self.out
    }
}

impl Default for Writer {
    fn default() -> Self {
        Self::new()
    }
}
