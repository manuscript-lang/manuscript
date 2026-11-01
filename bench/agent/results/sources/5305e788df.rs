use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::io::{self, Read, Write};

type Tree = BTreeMap<String, String>;
type R = Result<(), String>;

#[derive(Clone)]
struct Commit {
    parents: Vec<String>,
    message: String,
    tree: Tree,
    num: u64,
}

#[derive(Clone, PartialEq)]
enum Head {
    Branch(String),
    Detached(String),
}

#[derive(Clone)]
struct MergeState {
    other: String,
    branch: String,
}

#[derive(Clone, Copy)]
enum Kind {
    Content,
    AddAdd,
    ModifyDelete,
}

struct Repo {
    commits: HashMap<String, Commit>,
    next_num: u64,
    branches: BTreeMap<String, Option<String>>,
    tags: BTreeMap<String, String>,
    head: Head,
    wt: Tree,
    index: Tree,
    conflicts: BTreeSet<String>,
    merge: Option<MergeState>,
    out: String,
}

fn fnv(data: &[u8]) -> u64 {
    let mut h: u64 = 14695981039346656037;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(1099511628211);
    }
    h
}

fn hex(h: u64) -> String {
    format!("{:016x}", h)
}

fn short(id: &str) -> String {
    id[..7].to_string()
}

fn tree_hash(t: &Tree) -> u64 {
    let mut s = String::new();
    for (n, c) in t {
        s.push_str(&format!("{} {}\n", n, hex(fnv(c.as_bytes()))));
    }
    fnv(s.as_bytes())
}

fn commit_id(tree: &Tree, parents: &[String], msg: &str) -> String {
    let mut s = format!("tree {}\n", hex(tree_hash(tree)));
    for p in parents {
        s.push_str(&format!("parent {}\n", p));
    }
    s.push('\n');
    s.push_str(msg);
    s.push('\n');
    hex(fnv(s.as_bytes()))
}

fn valid_name(s: &str) -> bool {
    let b = s.as_bytes();
    if b.is_empty() {
        return false;
    }
    let first_ok = |c: u8| c.is_ascii_alphanumeric() || c == b'.' || c == b'_' || c == b'/';
    first_ok(b[0]) && b[1..].iter().all(|&c| first_ok(c) || c == b'-')
}

fn lines_of(c: &str) -> Vec<&str> {
    if c.is_empty() {
        Vec::new()
    } else {
        c[..c.len() - 1].split('\n').collect()
    }
}

/// Matching pairs (i, j) of a against b, as specified by the LCS walk.
fn matches(a: &[&str], b: &[&str]) -> Vec<(usize, usize)> {
    let n = a.len();
    let m = b.len();
    let mut l = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            l[i][j] = if a[i] == b[j] {
                1 + l[i + 1][j + 1]
            } else {
                l[i + 1][j].max(l[i][j + 1])
            };
        }
    }
    let (mut i, mut j) = (0, 0);
    let mut pairs = Vec::new();
    while i < n && j < m {
        if a[i] == b[j] {
            pairs.push((i, j));
            i += 1;
            j += 1;
        } else if l[i + 1][j] >= l[i][j + 1] {
            i += 1;
        } else {
            j += 1;
        }
    }
    pairs
}

fn diff_lines(a: &[&str], b: &[&str]) -> String {
    let mut o = String::new();
    let (mut li, mut lj) = (0, 0);
    for (pi, pj) in matches(a, b) {
        for x in &a[li..pi] {
            o.push_str(&format!("- {}\n", x));
        }
        for y in &b[lj..pj] {
            o.push_str(&format!("+ {}\n", y));
        }
        o.push_str(&format!("  {}\n", a[pi]));
        li = pi + 1;
        lj = pj + 1;
    }
    for x in &a[li..] {
        o.push_str(&format!("- {}\n", x));
    }
    for y in &b[lj..] {
        o.push_str(&format!("+ {}\n", y));
    }
    o
}

/// Three-way line merge. Returns (merged content, clean?).
fn merge3(base: &[&str], ours: &[&str], theirs: &[&str], branch: &str) -> (String, bool) {
    let mut omap: Vec<Option<usize>> = vec![None; base.len()];
    for (bi, oi) in matches(base, ours) {
        omap[bi] = Some(oi);
    }
    let mut tmap: Vec<Option<usize>> = vec![None; base.len()];
    for (bi, ti) in matches(base, theirs) {
        tmap[bi] = Some(ti);
    }
    let mut stable: Vec<(usize, usize, usize)> = Vec::new();
    for bi in 0..base.len() {
        if let (Some(oi), Some(ti)) = (omap[bi], tmap[bi]) {
            stable.push((bi, oi, ti));
        }
    }
    let nstable = stable.len();
    stable.push((base.len(), ours.len(), theirs.len()));

    let mut res: Vec<String> = Vec::new();
    let mut clean = true;
    let (mut pb, mut po, mut pt) = (0usize, 0usize, 0usize);
    for (idx, &(sb, so, st)) in stable.iter().enumerate() {
        let bc = &base[pb..sb];
        let oc = &ours[po..so];
        let tc = &theirs[pt..st];
        if oc == bc {
            res.extend(tc.iter().map(|s| s.to_string()));
        } else if tc == bc {
            res.extend(oc.iter().map(|s| s.to_string()));
        } else if oc == tc {
            res.extend(oc.iter().map(|s| s.to_string()));
        } else {
            clean = false;
            res.push("<<<<<<< HEAD".to_string());
            res.extend(oc.iter().map(|s| s.to_string()));
            res.push("=======".to_string());
            res.extend(tc.iter().map(|s| s.to_string()));
            res.push(format!(">>>>>>> {}", branch));
        }
        if idx < nstable {
            res.push(base[sb].to_string());
        }
        pb = sb + 1;
        po = so + 1;
        pt = st + 1;
    }
    let mut s = String::new();
    for l in res {
        s.push_str(&l);
        s.push('\n');
    }
    (s, clean)
}

impl Repo {
    fn new() -> Repo {
        let mut branches = BTreeMap::new();
        branches.insert("main".to_string(), None);
        Repo {
            commits: HashMap::new(),
            next_num: 1,
            branches,
            tags: BTreeMap::new(),
            head: Head::Branch("main".to_string()),
            wt: Tree::new(),
            index: Tree::new(),
            conflicts: BTreeSet::new(),
            merge: None,
            out: String::new(),
        }
    }

    fn head_commit(&self) -> Option<String> {
        match &self.head {
            Head::Branch(b) => self.branches.get(b).cloned().flatten(),
            Head::Detached(c) => Some(c.clone()),
        }
    }

    fn head_id(&self) -> Result<String, String> {
        self.head_commit()
            .ok_or_else(|| "no commits yet".to_string())
    }

    fn head_tree(&self) -> Tree {
        match self.head_commit() {
            Some(c) => self.commits[&c].tree.clone(),
            None => Tree::new(),
        }
    }

    fn label(&self) -> String {
        match &self.head {
            Head::Branch(b) => b.clone(),
            Head::Detached(_) => "detached".to_string(),
        }
    }

    fn move_head(&mut self, id: &str) {
        match self.head.clone() {
            Head::Branch(b) => {
                self.branches.insert(b, Some(id.to_string()));
            }
            Head::Detached(_) => self.head = Head::Detached(id.to_string()),
        }
    }

    fn make_commit(&mut self, tree: Tree, parents: Vec<String>, msg: &str) -> String {
        let id = commit_id(&tree, &parents, msg);
        if !self.commits.contains_key(&id) {
            let num = self.next_num;
            self.next_num += 1;
            self.commits.insert(
                id.clone(),
                Commit {
                    parents,
                    message: msg.to_string(),
                    tree,
                    num,
                },
            );
        }
        id
    }

    fn resolve(&self, r: &str) -> Result<String, String> {
        let unknown = || format!("unknown revision '{}'", r);
        let (base, steps) = match r.find('~') {
            None => (r, 0usize),
            Some(p) => {
                let n = &r[p + 1..];
                if n.is_empty() || !n.bytes().all(|c| c.is_ascii_digit()) {
                    return Err(unknown());
                }
                match n.parse::<usize>() {
                    Ok(v) => (&r[..p], v),
                    Err(_) => return Err(unknown()),
                }
            }
        };
        let mut id = if base == "HEAD" {
            self.head_id()?
        } else if let Some(Some(c)) = self.branches.get(base) {
            c.clone()
        } else if let Some(c) = self.tags.get(base) {
            c.clone()
        } else if base.len() >= 4
            && base
                .bytes()
                .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        {
            let m: Vec<&String> = self.commits.keys().filter(|k| k.starts_with(base)).collect();
            match m.len() {
                0 => return Err(unknown()),
                1 => m[0].clone(),
                _ => return Err(format!("ambiguous revision '{}'", r)),
            }
        } else {
            return Err(unknown());
        };
        for _ in 0..steps {
            match self.commits[&id].parents.first() {
                Some(p) => id = p.clone(),
                None => return Err(unknown()),
            }
        }
        Ok(id)
    }

    fn tree_at(&self, r: &str) -> Result<Tree, String> {
        let id = self.resolve(r)?;
        Ok(self.commits[&id].tree.clone())
    }

    fn ancestors(&self, id: &str) -> HashSet<String> {
        let mut seen = HashSet::new();
        let mut stack = vec![id.to_string()];
        while let Some(c) = stack.pop() {
            if seen.insert(c.clone()) {
                for p in &self.commits[&c].parents {
                    stack.push(p.clone());
                }
            }
        }
        seen
    }

    fn merge_base(&self, a: &str, b: &str) -> Option<String> {
        let aa = self.ancestors(a);
        let ab = self.ancestors(b);
        aa.iter()
            .filter(|c| ab.contains(*c))
            .max_by_key(|c| self.commits[*c].num)
            .cloned()
    }

    fn is_dirty(&self) -> bool {
        if self.index != self.head_tree() {
            return true;
        }
        self.index
            .iter()
            .any(|(n, c)| self.wt.get(n) != Some(c))
    }

    fn check_dirty(&self) -> R {
        if self.is_dirty() {
            Err("local changes would be overwritten".to_string())
        } else {
            Ok(())
        }
    }

    fn check_untracked(&self, names: &BTreeSet<String>) -> R {
        for n in names {
            if !self.index.contains_key(n) && self.wt.contains_key(n) {
                return Err(format!("untracked file would be overwritten: {}", n));
            }
        }
        Ok(())
    }

    fn check_switch(&self, target: &Tree) -> R {
        self.check_dirty()?;
        let names: BTreeSet<String> = target.keys().cloned().collect();
        self.check_untracked(&names)
    }

    fn switch_tree(&mut self, target: Tree) {
        let old: Vec<String> = self.index.keys().cloned().collect();
        for n in old {
            self.wt.remove(&n);
        }
        for (n, c) in &target {
            self.wt.insert(n.clone(), c.clone());
        }
        self.index = target;
    }

    fn hard_reset(&mut self, id: &str) {
        let new_tree = self.commits[id].tree.clone();
        let old: BTreeSet<String> = self
            .index
            .keys()
            .cloned()
            .chain(self.head_tree().into_keys())
            .collect();
        for n in old {
            self.wt.remove(&n);
        }
        for (n, c) in &new_tree {
            self.wt.insert(n.clone(), c.clone());
        }
        self.index = new_tree;
        self.move_head(id);
        self.merge = None;
        self.conflicts.clear();
    }

    fn write_file(&mut self, append: bool, name: &str, content: String) -> R {
        if append {
            self.wt.entry(name.to_string()).or_default().push_str(&content);
        } else {
            self.wt.insert(name.to_string(), content);
        }
        Ok(())
    }

    fn cmd_rm(&mut self, args: &[&str]) -> R {
        if args.is_empty() {
            return Err("usage: rm FILE...".into());
        }
        for f in args {
            if !self.wt.contains_key(*f) {
                return Err(format!("no such file: {}", f));
            }
            self.wt.remove(*f);
        }
        Ok(())
    }

    fn cmd_mv(&mut self, args: &[&str]) -> R {
        let [old, new] = args else {
            return Err("usage: mv OLD NEW".into());
        };
        let c = match self.wt.remove(*old) {
            Some(c) => c,
            None => return Err(format!("no such file: {}", old)),
        };
        self.wt.insert(new.to_string(), c);
        Ok(())
    }

    fn cmd_cat(&mut self, args: &[&str]) -> R {
        let [f] = args else {
            return Err("usage: cat FILE".into());
        };
        match self.wt.get(*f) {
            Some(c) => {
                let c = c.clone();
                self.out.push_str(&c);
                Ok(())
            }
            None => Err(format!("no such file: {}", f)),
        }
    }

    fn cmd_ls(&mut self) -> R {
        if self.wt.is_empty() {
            self.out.push_str("(empty)\n");
        } else {
            let mut o = String::new();
            for n in self.wt.keys() {
                o.push_str(n);
                o.push('\n');
            }
            self.out.push_str(&o);
        }
        Ok(())
    }

    fn cmd_add(&mut self, paths: &[&str]) -> R {
        if paths.is_empty() {
            return Err("usage: add PATH...".into());
        }
        for &p in paths {
            if p == "." {
                for (n, c) in self.wt.clone() {
                    self.conflicts.remove(&n);
                    self.index.insert(n, c);
                }
                let gone: Vec<String> = self
                    .index
                    .keys()
                    .filter(|n| !self.wt.contains_key(*n))
                    .cloned()
                    .collect();
                for n in gone {
                    self.index.remove(&n);
                    self.conflicts.remove(&n);
                }
            } else if let Some(c) = self.wt.get(p) {
                let c = c.clone();
                self.conflicts.remove(p);
                self.index.insert(p.to_string(), c);
            } else if self.index.contains_key(p) {
                self.index.remove(p);
                self.conflicts.remove(p);
            } else if self.conflicts.contains(p) {
                self.conflicts.remove(p);
            } else {
                return Err(format!("pathspec '{}' did not match any files", p));
            }
        }
        Ok(())
    }

    fn cmd_status(&mut self) -> R {
        let mut o = String::new();
        match &self.head {
            Head::Branch(b) => o.push_str(&format!("On branch {}\n", b)),
            Head::Detached(c) => o.push_str(&format!("HEAD detached at {}\n", short(c))),
        }
        if let Some(m) = &self.merge {
            o.push_str(&format!("merging: {}\n", m.branch));
        }
        let head_tree = self.head_tree();

        let mut staged = Vec::new();
        let names: BTreeSet<&String> = head_tree.keys().chain(self.index.keys()).collect();
        for n in names {
            if self.conflicts.contains(n) {
                continue;
            }
            match (head_tree.get(n), self.index.get(n)) {
                (None, Some(_)) => staged.push(format!("new file: {}", n)),
                (Some(_), None) => staged.push(format!("deleted: {}", n)),
                (Some(a), Some(b)) if a != b => staged.push(format!("modified: {}", n)),
                _ => {}
            }
        }

        let mut unstaged = Vec::new();
        for (n, c) in &self.index {
            if self.conflicts.contains(n) {
                continue;
            }
            match self.wt.get(n) {
                None => unstaged.push(format!("deleted: {}", n)),
                Some(w) if w != c => unstaged.push(format!("modified: {}", n)),
                _ => {}
            }
        }

        let conflicted: Vec<String> = self
            .conflicts
            .iter()
            .map(|n| format!("unmerged: {}", n))
            .collect();

        let untracked: Vec<String> = self
            .wt
            .keys()
            .filter(|n| !self.index.contains_key(*n) && !self.conflicts.contains(*n))
            .cloned()
            .collect();

        let sections = [
            ("staged", staged),
            ("unstaged", unstaged),
            ("conflicts", conflicted),
            ("untracked", untracked),
        ];
        let mut any = false;
        for (h, items) in sections {
            if items.is_empty() {
                continue;
            }
            any = true;
            o.push_str(&format!("{}:\n", h));
            for i in items {
                o.push_str(&format!("  {}\n", i));
            }
        }
        if !any {
            o.push_str("nothing to commit, working tree clean\n");
        }
        self.out.push_str(&o);
        Ok(())
    }

    fn cmd_commit(&mut self, msg: &str) -> R {
        if msg.is_empty() {
            return Err("empty commit message".into());
        }
        if !self.conflicts.is_empty() {
            let list: Vec<&str> = self.conflicts.iter().map(|s| s.as_str()).collect();
            return Err(format!("unresolved conflicts: {}", list.join(" ")));
        }
        if let Some(m) = self.merge.clone() {
            let head = self.head_id()?;
            let tree = self.index.clone();
            let id = self.make_commit(tree, vec![head, m.other], msg);
            self.merge = None;
            self.move_head(&id);
            let line = format!("[{} {}] {}\n", self.label(), short(&id), msg);
            self.out.push_str(&line);
            return Ok(());
        }
        let head = self.head_commit();
        let head_tree = self.head_tree();
        if self.index == head_tree {
            return Err("nothing to commit".into());
        }
        let parents: Vec<String> = head.into_iter().collect();
        let root = parents.is_empty();
        let tree = self.index.clone();
        let id = self.make_commit(tree, parents, msg);
        self.move_head(&id);
        let line = format!(
            "[{} {}{}] {}\n",
            self.label(),
            if root { "(root-commit) " } else { "" },
            short(&id),
            msg
        );
        self.out.push_str(&line);
        Ok(())
    }

    fn cmd_log(&mut self, args: &[&str]) -> R {
        let limit = match args {
            [] => usize::MAX,
            ["-n", n] => {
                if !n.is_empty() && n.bytes().all(|c| c.is_ascii_digit()) {
                    n.parse::<usize>().unwrap_or(usize::MAX)
                } else {
                    return Err("usage: log [-n N]".into());
                }
            }
            _ => return Err("usage: log [-n N]".into()),
        };
        let head = self.head_id()?;
        let mut ids: Vec<String> = self.ancestors(&head).into_iter().collect();
        ids.sort_by(|a, b| self.commits[b].num.cmp(&self.commits[a].num));
        let mut o = String::new();
        for id in ids.iter().take(limit) {
            let c = &self.commits[id];
            o.push_str(&format!("{} {}", short(id), c.message));
            if c.parents.len() == 2 {
                o.push_str(&format!(
                    " (merge {} {})",
                    short(&c.parents[0]),
                    short(&c.parents[1])
                ));
            }
            o.push('\n');
        }
        self.out.push_str(&o);
        Ok(())
    }

    fn cmd_diff(&mut self, args: &[&str]) -> R {
        let (left, right): (Tree, Tree) = match args {
            [] => (self.index.clone(), self.wt.clone()),
            [a] => (self.tree_at(a)?, self.wt.clone()),
            [a, b] => (self.tree_at(a)?, self.tree_at(b)?),
            _ => return Err("usage: diff [REF [REF]]".into()),
        };
        let names: BTreeSet<&String> = left.keys().chain(right.keys()).collect();
        let mut o = String::new();
        let mut any = false;
        for n in names {
            let l = left.get(n);
            let r = right.get(n);
            if l == r {
                continue;
            }
            any = true;
            o.push_str(&format!("diff {}\n", n));
            if l.is_none() {
                o.push_str("new file\n");
            }
            if r.is_none() {
                o.push_str("deleted file\n");
            }
            let la = l.map(|s| lines_of(s)).unwrap_or_default();
            let ra = r.map(|s| lines_of(s)).unwrap_or_default();
            o.push_str(&diff_lines(&la, &ra));
        }
        if !any {
            o.push_str("(no differences)\n");
        }
        self.out.push_str(&o);
        Ok(())
    }

    fn create_branch(&mut self, name: &str) -> R {
        if !valid_name(name) {
            return Err(format!("invalid branch name '{}'", name));
        }
        if self.branches.contains_key(name) {
            return Err(format!("branch '{}' already exists", name));
        }
        let id = self.head_id()?;
        self.branches.insert(name.to_string(), Some(id));
        Ok(())
    }

    fn delete_branch(&mut self, name: &str) -> R {
        let bc = match self.branches.get(name) {
            None => return Err(format!("branch '{}' not found", name)),
            Some(c) => c.clone(),
        };
        if matches!(&self.head, Head::Branch(b) if b == name) {
            return Err(format!("cannot delete the current branch '{}'", name));
        }
        if let Some(c) = &bc {
            let merged = match self.head_commit() {
                Some(h) => *c == h || self.ancestors(&h).contains(c),
                None => false,
            };
            if !merged {
                return Err(format!("branch '{}' is not fully merged", name));
            }
        }
        self.branches.remove(name);
        if let Some(c) = bc {
            let line = format!("Deleted branch {} (was {}).\n", name, short(&c));
            self.out.push_str(&line);
        }
        Ok(())
    }

    fn cmd_branch(&mut self, args: &[&str]) -> R {
        match args {
            [] => {
                let mut o = String::new();
                if let Head::Detached(c) = &self.head {
                    o.push_str(&format!("* (HEAD detached at {})\n", short(c)));
                }
                for name in self.branches.keys() {
                    let cur = matches!(&self.head, Head::Branch(b) if b == name);
                    o.push_str(&format!("{} {}\n", if cur { "*" } else { " " }, name));
                }
                self.out.push_str(&o);
                Ok(())
            }
            [name] => self.create_branch(name),
            ["-d", name] => self.delete_branch(name),
            _ => Err("usage: branch [NAME | -d NAME]".into()),
        }
    }

    fn cmd_tag(&mut self, args: &[&str]) -> R {
        if args.is_empty() {
            let mut o = String::new();
            for n in self.tags.keys() {
                o.push_str(n);
                o.push('\n');
            }
            self.out.push_str(&o);
            return Ok(());
        }
        if args.len() > 2 {
            return Err("usage: tag [NAME [REF]]".into());
        }
        let name = args[0];
        if !valid_name(name) {
            return Err(format!("invalid tag name '{}'", name));
        }
        if self.tags.contains_key(name) {
            return Err(format!("tag '{}' already exists", name));
        }
        let r = args.get(1).copied().unwrap_or("HEAD");
        if r == "HEAD" && self.head_commit().is_none() {
            return Err("no commits yet".into());
        }
        let id = self.resolve(r)?;
        self.tags.insert(name.to_string(), id);
        Ok(())
    }

    fn cmd_show(&mut self, args: &[&str]) -> R {
        let [r] = args else {
            return Err("usage: show REF".into());
        };
        let id = self.resolve(r)?;
        let c = self.commits[&id].clone();
        let mut o = format!("commit {}\ntree {}\n", id, hex(tree_hash(&c.tree)));
        for p in &c.parents {
            o.push_str(&format!("parent {}\n", p));
        }
        o.push_str(&format!("message: {}\nfiles:\n", c.message));
        for (n, content) in &c.tree {
            o.push_str(&format!("  {} {}\n", n, &hex(fnv(content.as_bytes()))[..7]));
        }
        self.out.push_str(&o);
        Ok(())
    }

    fn cmd_checkout(&mut self, args: &[&str]) -> R {
        match args {
            ["-b", name] => {
                self.create_branch(name)?;
                let tree = self.head_tree();
                self.check_switch(&tree)?;
                self.switch_tree(tree);
                self.head = Head::Branch(name.to_string());
                self.out
                    .push_str(&format!("Switched to a new branch '{}'\n", name));
                Ok(())
            }
            [t] => self.checkout_target(t),
            _ => Err("usage: checkout REF | checkout -b NAME".into()),
        }
    }

    fn checkout_target(&mut self, t: &str) -> R {
        if self.merge.is_some() {
            return Err("merge in progress".into());
        }
        if self.branches.contains_key(t) {
            if matches!(&self.head, Head::Branch(b) if b == t) {
                self.out.push_str(&format!("Already on '{}'\n", t));
                return Ok(());
            }
            let tree = match &self.branches[t] {
                Some(c) => self.commits[c].tree.clone(),
                None => Tree::new(),
            };
            self.check_switch(&tree)?;
            self.switch_tree(tree);
            self.head = Head::Branch(t.to_string());
            self.out
                .push_str(&format!("Switched to branch '{}'\n", t));
            Ok(())
        } else {
            let id = self.resolve(t)?;
            let tree = self.commits[&id].tree.clone();
            self.check_switch(&tree)?;
            let msg = self.commits[&id].message.clone();
            self.switch_tree(tree);
            self.head = Head::Detached(id.clone());
            self.out
                .push_str(&format!("HEAD is now at {} {}\n", short(&id), msg));
            Ok(())
        }
    }

    fn cmd_reset(&mut self, args: &[&str]) -> R {
        let r = match args {
            ["--hard"] => None,
            ["--hard", r] => Some(*r),
            _ => return Err("usage: reset --hard [REF]".into()),
        };
        let id = match r {
            None => self.head_id()?,
            Some(r) => self.resolve(r)?,
        };
        self.hard_reset(&id);
        let line = format!("HEAD is now at {} {}\n", short(&id), self.commits[&id].message);
        self.out.push_str(&line);
        Ok(())
    }

    fn cmd_merge(&mut self, args: &[&str]) -> R {
        if args == ["--abort"] {
            if self.merge.is_none() {
                return Err("no merge in progress".into());
            }
            let cur = self.head_id()?;
            self.hard_reset(&cur);
            self.out.push_str("Merge aborted.\n");
            return Ok(());
        }
        let [name] = args else {
            return Err("usage: merge BRANCH".into());
        };
        let name: &str = name;
        if self.merge.is_some() {
            return Err("merge in progress".into());
        }
        let cur = self.head_id()?;
        let other = match self.branches.get(name) {
            Some(Some(c)) => c.clone(),
            _ => return Err(format!("unknown branch '{}'", name)),
        };
        self.check_dirty()?;

        if self.ancestors(&cur).contains(&other) {
            self.out.push_str("Already up to date.\n");
            return Ok(());
        }
        if self.ancestors(&other).contains(&cur) {
            let tree = self.commits[&other].tree.clone();
            let names: BTreeSet<String> = tree.keys().cloned().collect();
            self.check_untracked(&names)?;
            self.switch_tree(tree);
            self.move_head(&other);
            self.out.push_str("Fast-forward\n");
            return Ok(());
        }

        // Three-way merge.
        let base = self.merge_base(&cur, &other);
        let base_tree = match &base {
            Some(b) => self.commits[b].tree.clone(),
            None => Tree::new(),
        };
        let o_tree = self.commits[&cur].tree.clone();
        let t_tree = self.commits[&other].tree.clone();
        let names: BTreeSet<&String> = base_tree
            .keys()
            .chain(o_tree.keys())
            .chain(t_tree.keys())
            .collect();

        let mut result = Tree::new();
        let mut overrides = Tree::new();
        let mut conflicts: BTreeMap<String, Kind> = BTreeMap::new();
        for n in names {
            let b = base_tree.get(n);
            let o = o_tree.get(n);
            let t = t_tree.get(n);
            if o == t {
                if let Some(c) = o {
                    result.insert(n.clone(), c.clone());
                }
            } else if o == b {
                if let Some(c) = t {
                    result.insert(n.clone(), c.clone());
                }
            } else if t == b {
                if let Some(c) = o {
                    result.insert(n.clone(), c.clone());
                }
            } else {
                match (o, t) {
                    (Some(oc), Some(tc)) => {
                        let bl = b.map(|s| s.as_str()).unwrap_or("");
                        let (merged, clean) =
                            merge3(&lines_of(bl), &lines_of(oc), &lines_of(tc), name);
                        if clean {
                            result.insert(n.clone(), merged);
                        } else {
                            result.insert(n.clone(), oc.clone());
                            overrides.insert(n.clone(), merged);
                            let k = if b.is_some() { Kind::Content } else { Kind::AddAdd };
                            conflicts.insert(n.clone(), k);
                        }
                    }
                    (Some(oc), None) => {
                        result.insert(n.clone(), oc.clone());
                        overrides.insert(n.clone(), oc.clone());
                        conflicts.insert(n.clone(), Kind::ModifyDelete);
                    }
                    (None, Some(tc)) => {
                        overrides.insert(n.clone(), tc.clone());
                        conflicts.insert(n.clone(), Kind::ModifyDelete);
                    }
                    (None, None) => {}
                }
            }
        }

        let check: BTreeSet<String> = result.keys().chain(overrides.keys()).cloned().collect();
        self.check_untracked(&check)?;

        let old: Vec<String> = self.index.keys().cloned().collect();
        for n in old {
            if !result.contains_key(&n) {
                self.wt.remove(&n);
            }
        }
        for (n, c) in &result {
            self.wt.insert(n.clone(), c.clone());
        }
        for (n, c) in &overrides {
            self.wt.insert(n.clone(), c.clone());
        }
        self.index = result.clone();

        if conflicts.is_empty() {
            let msg = format!("Merge branch '{}'", name);
            let id = self.make_commit(result, vec![cur, other], &msg);
            self.move_head(&id);
            let line = format!(
                "Merge made by the 'three-way' strategy.\n[{} {}] {}\n",
                self.label(),
                short(&id),
                msg
            );
            self.out.push_str(&line);
        } else {
            self.merge = Some(MergeState {
                other: other.clone(),
                branch: name.to_string(),
            });
            self.conflicts = conflicts.keys().cloned().collect();
            let mut o = String::new();
            for (n, k) in &conflicts {
                match k {
                    Kind::Content => {
                        o.push_str(&format!("CONFLICT (content): Merge conflict in {}\n", n))
                    }
                    Kind::AddAdd => {
                        o.push_str(&format!("CONFLICT (add/add): Merge conflict in {}\n", n))
                    }
                    Kind::ModifyDelete => {
                        o.push_str(&format!("CONFLICT (modify/delete): {}\n", n))
                    }
                }
            }
            o.push_str("Automatic merge failed; fix conflicts and then commit the result.\n");
            self.out.push_str(&o);
        }
        Ok(())
    }

    fn dispatch(&mut self, word: &str, line: &str, args: &[&str]) -> R {
        match word {
            "add" => self.cmd_add(args),
            "status" => self.cmd_status(),
            "commit" => {
                let t = line.trim_start();
                let msg = t["commit".len()..].trim();
                self.cmd_commit(msg)
            }
            "log" => self.cmd_log(args),
            "diff" => self.cmd_diff(args),
            "branch" => self.cmd_branch(args),
            "tag" => self.cmd_tag(args),
            "show" => self.cmd_show(args),
            "checkout" => self.cmd_checkout(args),
            "merge" => self.cmd_merge(args),
            "reset" => self.cmd_reset(args),
            "rm" => self.cmd_rm(args),
            "mv" => self.cmd_mv(args),
            "cat" => self.cmd_cat(args),
            "ls" => self.cmd_ls(),
            _ => Err(format!("unknown command '{}'", word)),
        }
    }
}

fn main() {
    let mut input = String::new();
    let _ = io::stdin().read_to_string(&mut input);
    let lines: Vec<&str> = input.lines().collect();
    let mut repo = Repo::new();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        i += 1;
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        repo.out.push_str("> ");
        repo.out.push_str(line.trim_end());
        repo.out.push('\n');

        let toks: Vec<&str> = line.split_whitespace().collect();
        let word = toks[0];
        let args = &toks[1..];
        let res: R = if word == "write" || word == "append" {
            if args.len() != 1 {
                Err(format!("usage: {} FILE", word))
            } else {
                let mut content = String::new();
                while i < lines.len() && lines[i] != "." {
                    content.push_str(lines[i]);
                    content.push('\n');
                    i += 1;
                }
                if i < lines.len() {
                    i += 1;
                }
                repo.write_file(word == "append", args[0], content)
            }
        } else {
            repo.dispatch(word, line, args)
        };
        if let Err(e) = res {
            repo.out.push_str(&format!("error: {}\n", e));
        }
    }
    let stdout = io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(repo.out.as_bytes());
    let _ = lock.flush();
}
