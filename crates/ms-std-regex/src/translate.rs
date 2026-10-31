//! Rewrites Go `regexp` (RE2, Perl flags) syntax into the `regex` crate's syntax and enforces
//! Go's own syntax rules where the two parsers disagree. Differences bridged here:
//! `\d \w \s \b` are ASCII-only in Go; classes are parsed with Go's rules (`[` and `&&` are
//! literal, `[:name:]` must be a POSIX name, ranges must be ordered); a `{` that is not a valid
//! repeat is literal; repeat counts are capped at 1000 including nested products; repeat
//! operators cannot be stacked; `\p{..}` accepts only Go's category and script names; capture
//! names are validated then dropped (duplicates are legal in Go); flags are `imsU` only.
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt::Write;

const MAX_REPEAT: u32 = 1000;
const POSIX: &[&str] = &[
    "alnum", "alpha", "ascii", "blank", "cntrl", "digit", "graph", "lower", "print", "punct",
    "space", "upper", "word", "xdigit",
];

const CATEGORIES: &[&str] = &[
    "C", "Cc", "Cf", "Co", "Cs", "L", "Ll", "Lm", "Lo", "Lt", "Lu", "M", "Mc", "Me", "Mn", "N",
    "Nd", "Nl", "No", "P", "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps", "S", "Sc", "Sk", "Sm", "So",
    "Z", "Zl", "Zp", "Zs",
];
const SCRIPTS: &[&str] = &[
    "Adlam",
    "Ahom",
    "Anatolian_Hieroglyphs",
    "Arabic",
    "Armenian",
    "Avestan",
    "Balinese",
    "Bamum",
    "Bassa_Vah",
    "Batak",
    "Bengali",
    "Bhaiksuki",
    "Bopomofo",
    "Brahmi",
    "Braille",
    "Buginese",
    "Buhid",
    "Canadian_Aboriginal",
    "Carian",
    "Caucasian_Albanian",
    "Chakma",
    "Cham",
    "Cherokee",
    "Chorasmian",
    "Common",
    "Coptic",
    "Cuneiform",
    "Cypriot",
    "Cypro_Minoan",
    "Cyrillic",
    "Deseret",
    "Devanagari",
    "Dives_Akuru",
    "Dogra",
    "Duployan",
    "Egyptian_Hieroglyphs",
    "Elbasan",
    "Elymaic",
    "Ethiopic",
    "Georgian",
    "Glagolitic",
    "Gothic",
    "Grantha",
    "Greek",
    "Gujarati",
    "Gunjala_Gondi",
    "Gurmukhi",
    "Han",
    "Hangul",
    "Hanifi_Rohingya",
    "Hanunoo",
    "Hatran",
    "Hebrew",
    "Hiragana",
    "Imperial_Aramaic",
    "Inherited",
    "Inscriptional_Pahlavi",
    "Inscriptional_Parthian",
    "Javanese",
    "Kaithi",
    "Kannada",
    "Katakana",
    "Kawi",
    "Kayah_Li",
    "Kharoshthi",
    "Khitan_Small_Script",
    "Khmer",
    "Khojki",
    "Khudawadi",
    "Lao",
    "Latin",
    "Lepcha",
    "Limbu",
    "Linear_A",
    "Linear_B",
    "Lisu",
    "Lycian",
    "Lydian",
    "Mahajani",
    "Makasar",
    "Malayalam",
    "Mandaic",
    "Manichaean",
    "Marchen",
    "Masaram_Gondi",
    "Medefaidrin",
    "Meetei_Mayek",
    "Mende_Kikakui",
    "Meroitic_Cursive",
    "Meroitic_Hieroglyphs",
    "Miao",
    "Modi",
    "Mongolian",
    "Mro",
    "Multani",
    "Myanmar",
    "Nabataean",
    "Nag_Mundari",
    "Nandinagari",
    "New_Tai_Lue",
    "Newa",
    "Nko",
    "Nushu",
    "Nyiakeng_Puachue_Hmong",
    "Ogham",
    "Ol_Chiki",
    "Old_Hungarian",
    "Old_Italic",
    "Old_North_Arabian",
    "Old_Permic",
    "Old_Persian",
    "Old_Sogdian",
    "Old_South_Arabian",
    "Old_Turkic",
    "Old_Uyghur",
    "Oriya",
    "Osage",
    "Osmanya",
    "Pahawh_Hmong",
    "Palmyrene",
    "Pau_Cin_Hau",
    "Phags_Pa",
    "Phoenician",
    "Psalter_Pahlavi",
    "Rejang",
    "Runic",
    "Samaritan",
    "Saurashtra",
    "Sharada",
    "Shavian",
    "Siddham",
    "SignWriting",
    "Sinhala",
    "Sogdian",
    "Sora_Sompeng",
    "Soyombo",
    "Sundanese",
    "Syloti_Nagri",
    "Syriac",
    "Tagalog",
    "Tagbanwa",
    "Tai_Le",
    "Tai_Tham",
    "Tai_Viet",
    "Takri",
    "Tamil",
    "Tangsa",
    "Tangut",
    "Telugu",
    "Thaana",
    "Thai",
    "Tibetan",
    "Tifinagh",
    "Tirhuta",
    "Toto",
    "Ugaritic",
    "Vai",
    "Vithkuqi",
    "Wancho",
    "Warang_Citi",
    "Yezidi",
    "Yi",
    "Zanabazar_Square",
];

type R<T> = Result<T, ()>;

fn lit(out: &mut String, c: char) {
    let _ = write!(out, "\\x{{{:x}}}", c as u32);
}

fn digits(s: &[char], from: usize) -> usize {
    s[from..].iter().take_while(|c| c.is_ascii_digit()).count()
}

fn number(s: &[char]) -> u32 {
    s.iter().fold(0u32, |n, c| {
        n.saturating_mul(10)
            .saturating_add(c.to_digit(10).unwrap_or(0))
    })
}

/// Parses `{n}`, `{n,}` or `{n,m}` at `i`; returns the length consumed and the bounds.
fn repeat(s: &[char], i: usize) -> Option<(usize, u32, Option<u32>)> {
    let a = digits(s, i + 1);
    if a == 0 {
        return None;
    }
    let lo = number(&s[i + 1..i + 1 + a]);
    let j = i + 1 + a;
    match s.get(j)? {
        '}' => Some((j + 1 - i, lo, Some(lo))),
        ',' => {
            let j = j + 1;
            let b = digits(s, j);
            if b == 0 {
                return (s.get(j) == Some(&'}')).then_some((j + 1 - i, lo, None));
            }
            let hi = number(&s[j..j + b]);
            (s.get(j + b) == Some(&'}')).then_some((j + b + 1 - i, lo, Some(hi)))
        }
        _ => None,
    }
}

/// A perl class escape (`\d \D \w \W \s \S`) as a set body and negation.
fn perl_set(c: char) -> Option<(&'static str, bool)> {
    Some(match c {
        'd' => ("0-9", false),
        'D' => ("0-9", true),
        'w' => ("0-9A-Za-z_", false),
        'W' => ("0-9A-Za-z_", true),
        's' => ("\\t\\n\\x0C\\r\\x20", false),
        'S' => ("\\t\\n\\x0C\\r\\x20", true),
        _ => return None,
    })
}

/// Parses `\pX`, `\p{Name}`, `\PX`, `\P{^Name}` at `s[i] == '\\'`; emits a regex-crate class.
fn unicode_class(s: &[char], i: &mut usize, out: &mut String) -> R<()> {
    let mut negated = s[*i + 1] == 'P';
    *i += 2;
    let name: String = if s.get(*i) == Some(&'{') {
        let end = s[*i..].iter().position(|&c| c == '}').ok_or(())?;
        let n = s[*i + 1..*i + end].iter().collect();
        *i += end + 1;
        n
    } else {
        let c = *s.get(*i).ok_or(())?;
        *i += 1;
        String::from(c)
    };
    let name = match name.strip_prefix('^') {
        Some(rest) => {
            negated = !negated;
            String::from(rest)
        }
        None => name,
    };
    let sign = if negated { 'P' } else { 'p' };
    if name == "Any" {
        let _ = write!(out, "\\{sign}{{Any}}");
    } else if CATEGORIES.contains(&name.as_str()) {
        let _ = write!(out, "\\{sign}{{{name}}}");
    } else if SCRIPTS.contains(&name.as_str()) {
        let _ = write!(out, "\\{sign}{{Script={name}}}");
    } else {
        return Err(());
    }
    Ok(())
}

/// Parses one escaped character (not a class) after the backslash at `s[*i - 1]`.
fn escaped_char(s: &[char], i: &mut usize, in_class: bool) -> R<char> {
    let c = *s.get(*i).ok_or(())?;
    *i += 1;
    match c {
        '1'..='7' | '0' => {
            if c != '0' && !s.get(*i).is_some_and(|d| ('0'..='7').contains(d)) {
                return Err(());
            }
            let mut v = c.to_digit(8).ok_or(())?;
            for _ in 0..2 {
                match s.get(*i).and_then(|d| d.to_digit(8)) {
                    Some(d) => {
                        v = v * 8 + d;
                        *i += 1;
                    }
                    None => break,
                }
            }
            char::from_u32(v).ok_or(())
        }
        'x' => {
            let (hex, used): (String, usize) = if s.get(*i) == Some(&'{') {
                let end = s[*i..].iter().position(|&c| c == '}').ok_or(())?;
                (s[*i + 1..*i + end].iter().collect(), end + 1)
            } else {
                (s.get(*i..*i + 2).ok_or(())?.iter().collect(), 2)
            };
            if hex.is_empty() || hex.len() > 8 || !hex.bytes().all(|c| c.is_ascii_hexdigit()) {
                return Err(());
            }
            *i += used;
            char::from_u32(u32::from_str_radix(&hex, 16).map_err(|_| ())?).ok_or(())
        }
        'a' => Ok('\x07'),
        'f' => Ok('\x0c'),
        'n' => Ok('\n'),
        'r' => Ok('\r'),
        't' => Ok('\t'),
        'v' => Ok('\x0b'),
        c if c.is_ascii() && !c.is_ascii_alphanumeric() => Ok(c),
        _ => {
            let _ = in_class;
            Err(())
        }
    }
}

/// Parses a class starting at `s[*i] == '['` with Go's rules and emits a normalised class.
fn class(s: &[char], i: &mut usize, out: &mut String) -> R<()> {
    out.push('[');
    *i += 1;
    if s.get(*i) == Some(&'^') {
        out.push('^');
        *i += 1;
    }
    let mut first = true;
    loop {
        let c = *s.get(*i).ok_or(())?;
        if c == ']' && !first {
            out.push(']');
            *i += 1;
            return Ok(());
        }
        first = false;
        if c == '[' && s.get(*i + 1) == Some(&':') {
            let rest = &s[*i + 2..];
            if let Some(end) = rest.windows(2).position(|w| w == [':', ']']) {
                let name: String = rest[..end].iter().collect();
                let bare = name.strip_prefix('^').unwrap_or(&name);
                if !POSIX.contains(&bare) {
                    return Err(());
                }
                let _ = write!(out, "[:{name}:]");
                *i += 2 + end + 2;
                continue;
            }
        }
        if c == '\\' {
            match s.get(*i + 1) {
                Some('p' | 'P') => {
                    unicode_class(s, i, out)?;
                    continue;
                }
                Some(&d) if perl_set(d).is_some() => {
                    let (set, neg) = perl_set(d).ok_or(())?;
                    if neg {
                        let _ = write!(out, "[^{set}]");
                    } else {
                        out.push_str(set);
                    }
                    *i += 2;
                    continue;
                }
                _ => {}
            }
        }
        let lo = class_char(s, i)?;
        let mut hi = lo;
        if s.get(*i) == Some(&'-') && s.get(*i + 1).is_some_and(|&n| n != ']') {
            *i += 1;
            hi = class_char(s, i)?;
            if hi < lo {
                return Err(());
            }
        }
        lit(out, lo);
        if hi != lo {
            out.push('-');
            lit(out, hi);
        }
    }
}

fn class_char(s: &[char], i: &mut usize) -> R<char> {
    let c = *s.get(*i).ok_or(())?;
    *i += 1;
    if c == '\\' {
        escaped_char(s, i, true)
    } else {
        Ok(c)
    }
}

/// Nesting bookkeeping for Go's repeat-product limit: `max` is the largest factor inside the
/// group, `last` the factor of the most recent atom.
#[derive(Clone, Copy)]
struct Frame {
    max: u32,
    last: u32,
}

fn atom(frames: &mut [Frame]) {
    if let Some(f) = frames.last_mut() {
        f.last = 1;
        f.max = f.max.max(1);
    }
}

/// Parses the flag group after `(?`; returns the normalised regex-crate text up to the opener.
fn flags(s: &[char], i: &mut usize) -> R<(String, bool)> {
    let (mut on, mut off) = (String::new(), String::new());
    let mut negative = false;
    let mut saw = false;
    loop {
        let c = *s.get(*i).ok_or(())?;
        *i += 1;
        match c {
            'i' | 'm' | 's' | 'U' => {
                saw = true;
                if negative {
                    off.push(c);
                    on.retain(|x| x != c);
                } else {
                    on.push(c);
                    off.retain(|x| x != c);
                }
            }
            '-' => {
                if negative {
                    return Err(());
                }
                negative = true;
                saw = false;
            }
            ':' | ')' => {
                if negative && !saw {
                    return Err(());
                }
                let mut text = String::from("(?");
                text.push_str(&on);
                if !off.is_empty() {
                    text.push('-');
                    text.push_str(&off);
                }
                if text == "(?" {
                    text.push(':');
                    return Ok((text, c == ':'));
                }
                text.push(c);
                return Ok((text, c == ':'));
            }
            _ => return Err(()),
        }
    }
}

pub fn translate(pattern: &str) -> R<String> {
    let s: Vec<char> = pattern.chars().collect();
    let mut out = String::new();
    // Go accepts repeated group names; the regex crate does not, so later ones stay unnamed.
    let mut names: alloc::vec::Vec<&[char]> = alloc::vec::Vec::new();
    let mut i = 0;
    let mut frames = alloc::vec![Frame { max: 1, last: 1 }];
    let mut after_repeat = false;
    while i < s.len() {
        let c = s[i];
        let was_repeat = core::mem::take(&mut after_repeat);
        match c {
            '\\' if s.get(i + 1) == Some(&'Q') => {
                i += 2;
                while i < s.len() && !(s[i] == '\\' && s.get(i + 1) == Some(&'E')) {
                    lit(&mut out, s[i]);
                    atom(&mut frames);
                    i += 1;
                }
                i = (i + 2).min(s.len());
            }
            '\\' => {
                let next = *s.get(i + 1).ok_or(())?;
                if matches!(next, 'p' | 'P') {
                    unicode_class(&s, &mut i, &mut out)?;
                } else if let Some((set, neg)) = perl_set(next) {
                    let _ = write!(out, "[{}{set}]", if neg { "^" } else { "" });
                    i += 2;
                } else if matches!(next, 'b' | 'B') {
                    let _ = write!(out, "(?-u:\\{next})");
                    i += 2;
                } else if matches!(next, 'A' | 'z') {
                    out.push('\\');
                    out.push(next);
                    i += 2;
                } else {
                    i += 1;
                    lit(&mut out, escaped_char(&s, &mut i, false)?);
                }
                atom(&mut frames);
            }
            '[' => {
                class(&s, &mut i, &mut out)?;
                atom(&mut frames);
            }
            '*' | '+' | '?' => {
                if was_repeat {
                    return Err(());
                }
                out.push(c);
                i += 1;
                if s.get(i) == Some(&'?') {
                    out.push('?');
                    i += 1;
                }
                after_repeat = true;
            }
            '{' => match repeat(&s, i) {
                Some((used, lo, hi)) => {
                    if was_repeat || lo > MAX_REPEAT || hi.is_some_and(|h| h > MAX_REPEAT || h < lo)
                    {
                        return Err(());
                    }
                    let count = hi.unwrap_or(lo);
                    if let Some(f) = frames.last_mut() {
                        if count > 0 {
                            f.last = f.last.saturating_mul(count);
                        }
                        if f.last > MAX_REPEAT {
                            return Err(());
                        }
                        f.max = f.max.max(f.last);
                    }
                    out.extend(&s[i..i + used]);
                    i += used;
                    if s.get(i) == Some(&'?') {
                        out.push('?');
                        i += 1;
                    }
                    after_repeat = true;
                }
                None => {
                    lit(&mut out, '{');
                    atom(&mut frames);
                    i += 1;
                }
            },
            '(' => {
                i += 1;
                if s.get(i) == Some(&'?') {
                    let named = match (s.get(i + 1), s.get(i + 2)) {
                        (Some('P'), Some('<')) => Some(i + 3),
                        (Some('<'), Some(n)) if *n != '=' && *n != '!' => Some(i + 2),
                        _ => None,
                    };
                    if let Some(start) = named {
                        let end = s[start..].iter().position(|&c| c == '>').ok_or(())?;
                        let name = &s[start..start + end];
                        if name.is_empty()
                            || !name.iter().all(|c| c.is_ascii_alphanumeric() || *c == '_')
                        {
                            return Err(());
                        }
                        if names.contains(&name) {
                            out.push('(');
                        } else {
                            names.push(name);
                            out.push_str("(?P<");
                            out.extend(name);
                            out.push('>');
                        }
                        i = start + end + 1;
                        frames.push(Frame { max: 1, last: 1 });
                    } else {
                        i += 1;
                        let (text, opens) = flags(&s, &mut i)?;
                        out.push_str(&text);
                        if opens {
                            frames.push(Frame { max: 1, last: 1 });
                        }
                    }
                } else {
                    out.push('(');
                    frames.push(Frame { max: 1, last: 1 });
                }
            }
            ')' => {
                if frames.len() < 2 {
                    return Err(());
                }
                let inner = frames.pop().ok_or(())?;
                if let Some(f) = frames.last_mut() {
                    f.last = inner.max;
                    f.max = f.max.max(inner.max);
                }
                out.push(')');
                i += 1;
            }
            c => {
                if c != '|' {
                    atom(&mut frames);
                }
                out.push(c);
                i += 1;
            }
        }
    }
    if frames.len() != 1 {
        return Err(());
    }
    Ok(out)
}
