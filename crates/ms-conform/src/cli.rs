//! Argument parsing shared by the subcommands (no external crates).

use crate::fixture::Phase;
use crate::runner::Filter;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// Flags that take no value.
const SWITCHES: &[&str] = &[
    "quiet",
    "no-stable-check",
    "prune",
    "only-missing",
    "help",
    "strict",
    "keep",
];

#[derive(Debug, Default)]
pub struct Args {
    values: BTreeMap<String, Vec<String>>,
    pub positional: Vec<String>,
}

impl Args {
    pub fn parse(items: &[String]) -> Result<Args, String> {
        let mut args = Args::default();
        let mut i = 0;
        while i < items.len() {
            let item = &items[i];
            if let Some(flag) = item.strip_prefix("--") {
                if let Some((k, v)) = flag.split_once('=') {
                    args.values
                        .entry(k.to_string())
                        .or_default()
                        .push(v.to_string());
                } else if SWITCHES.contains(&flag) {
                    args.values
                        .entry(flag.to_string())
                        .or_default()
                        .push(String::new());
                } else {
                    i += 1;
                    let value = items
                        .get(i)
                        .ok_or_else(|| format!("--{flag} needs a value"))?;
                    args.values
                        .entry(flag.to_string())
                        .or_default()
                        .push(value.clone());
                }
            } else {
                args.positional.push(item.clone());
            }
            i += 1;
        }
        Ok(args)
    }

    pub fn has(&self, flag: &str) -> bool {
        self.values.contains_key(flag)
    }

    pub fn one(&self, flag: &str) -> Option<&str> {
        self.values
            .get(flag)
            .and_then(|v| v.last())
            .map(String::as_str)
    }

    /// All values of a repeatable flag; each value may also be comma separated.
    pub fn many(&self, flag: &str) -> Vec<String> {
        self.values
            .get(flag)
            .map(|vs| {
                vs.iter()
                    .flat_map(|v| v.split(',').map(str::trim).filter(|s| !s.is_empty()))
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn number<T: std::str::FromStr>(&self, flag: &str) -> Result<Option<T>, String> {
        match self.one(flag) {
            None => Ok(None),
            Some(v) => v
                .parse()
                .map(Some)
                .map_err(|_| format!("--{flag}: bad number {v}")),
        }
    }

    pub fn jobs(&self) -> Result<usize, String> {
        if let Some(n) = self.number::<usize>("jobs")? {
            return Ok(n.max(1));
        }
        let cores = std::thread::available_parallelism().map_or(2, |n| n.get());
        Ok((cores / 2).max(1))
    }

    pub fn filter(&self) -> Result<Filter, String> {
        let phases = self
            .many("phase")
            .iter()
            .map(|p| Phase::from_name(p).ok_or(format!("unknown phase {p}")))
            .collect::<Result<_, _>>()?;
        let shard = match self.one("shard") {
            None => None,
            Some(s) => {
                let (i, n) = s.split_once('/').ok_or("--shard wants i/n")?;
                let (i, n): (usize, usize) = (
                    i.parse().map_err(|_| "--shard wants i/n")?,
                    n.parse().map_err(|_| "--shard wants i/n")?,
                );
                if n == 0 || i >= n {
                    return Err("--shard i/n needs 0 <= i < n".into());
                }
                Some((i, n))
            }
        };
        Ok(Filter {
            tags: self.many("tag"),
            exclude_tags: self.many("exclude-tag"),
            phases,
            ids: self.many("id"),
            shard,
        })
    }

    /// The corpus directory: `--corpus`, `$MS_CONFORM_CORPUS`, or `tests/conformance/fixtures`
    /// found by walking up from the current directory.
    pub fn corpus(&self) -> Result<PathBuf, String> {
        if let Some(c) = self.one("corpus") {
            return Ok(PathBuf::from(c));
        }
        if let Ok(c) = std::env::var("MS_CONFORM_CORPUS") {
            return Ok(PathBuf::from(c));
        }
        let mut dir = std::env::current_dir().map_err(|e| e.to_string())?;
        loop {
            let candidate = dir.join("tests/conformance/fixtures");
            if candidate.is_dir() {
                return Ok(candidate);
            }
            if !dir.pop() {
                return Err("cannot find tests/conformance/fixtures; pass --corpus".into());
            }
        }
    }

    /// The `ms` binary: `flag`, `$MS`, `./ms`, or `ms` on `PATH`.
    pub fn ms(&self, flag: &str) -> PathBuf {
        if let Some(p) = self.one(flag) {
            return absolute(PathBuf::from(p));
        }
        if let Ok(p) = std::env::var("MS") {
            return absolute(PathBuf::from(p));
        }
        let local = PathBuf::from("./ms");
        if local.is_file() {
            return absolute(local);
        }
        PathBuf::from("ms")
    }
}

/// Make a relative path with directory components absolute (bare names stay for `PATH` lookup).
pub fn absolute(path: PathBuf) -> PathBuf {
    if path.is_absolute() || path.components().count() < 2 {
        return path;
    }
    std::env::current_dir().map_or(path.clone(), |cwd| cwd.join(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(items: &[&str]) -> Args {
        Args::parse(&items.iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap()
    }

    #[test]
    fn flags_values_and_switches() {
        let a = parse(&[
            "--tag",
            "lists,maps",
            "--tag=sets",
            "--quiet",
            "pos",
            "--jobs",
            "3",
        ]);
        assert_eq!(a.many("tag"), ["lists", "maps", "sets"]);
        assert!(a.has("quiet"));
        assert_eq!(a.jobs().unwrap(), 3);
        assert_eq!(a.positional, ["pos"]);
    }

    #[test]
    fn shard_validation() {
        assert_eq!(
            parse(&["--shard", "1/4"]).filter().unwrap().shard,
            Some((1, 4))
        );
        assert!(parse(&["--shard", "4/4"]).filter().is_err());
        assert!(parse(&["--phase", "bogus"]).filter().is_err());
    }

    #[test]
    fn missing_value_is_an_error() {
        assert!(Args::parse(&["--tag".to_string()]).is_err());
    }
}
