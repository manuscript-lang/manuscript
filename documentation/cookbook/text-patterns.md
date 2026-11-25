+++
title = "Patterns and URLs"
weight = 8
+++

# Patterns and URLs

Pull fields out of text with a regular expression, and take a URL apart.

## Count lines by a field

Save as `levels.ms`. `compile` returns an error for a bad pattern, so a typo shows up at startup. `capture_named` returns the named groups of the first match, or an empty map when the line does not match, which makes skipping a bad line one check.

A value read from the map is borrowed from it, so `.clone()` it before using it as a key in `counts`.

<!-- manuscript-example: {"mode":"run","stdout":"INFO: 2\nWARN: 1\n"} -->
```manuscript
import compile from "@std/regex.ms"

fn main() Void! {
    line := compile("(?P<level>[A-Z]+) (?P<path>/\\S*) (?P<ms>[0-9]+)ms")?
    log := ["INFO /home 12ms", "WARN /search 340ms", "INFO /home 9ms", "not a log line"]
    var counts = Map[String, Int]()

    for entry in log {
        found := line.capture_named(entry)
        if found.is_empty() { continue }

        level := found["level"].clone()
        seen := counts.get_or(level, 0)
        counts[level] = seen + 1
    }

    for level in counts.keys().sorted() {
        print(f"{level}: {counts[level]}")
    }
}
```

- `matches` tests, `find_all` lists every match, `capture` returns `[whole, group1, ...]` by position, and `capture_all` does that for every match.
- `replace_all(text, replacement, null)` writes the replacement literally: `$1` is not expanded. The last argument bounds the output size when the input is untrusted.
- Matching is linear in the input, so a hostile pattern or text cannot hang the program.

## Take a URL apart

Save as `link.ms`. `parse` accepts an absolute URL and returns an error for anything else. The query stays encoded in the `Url`; `parse_query` decodes it into key and value entries, and `encode_component` escapes a value you are about to put in a URL.

<!-- manuscript-example: {"mode":"run","stdout":"example.com 8443 /search top\nq=a b\npage=2\na%20b%26c\n"} -->
```manuscript
import encode_component, parse, parse_query from "@std/net/url.ms"

fn main() Void! {
    link := parse("https://example.com:8443/search?q=a%20b&page=2#top")?
    print(f"{link.host} {link.port or 443} {link.path} {link.fragment}")
    for entry in parse_query((link.query or ""), null)? {
        print(f"{entry.key}={entry.value}")
    }
    print(encode_component("a b&c"))
}
```

- `port` is `null` when the URL names none, so `get_or` supplies the scheme's default.
- `resolve(base, reference)` turns a relative link into an absolute one, and `format` writes a `Url` back to text.
- For the module API, run `ms search_symbol url`.
