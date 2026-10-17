# mini-vcs

Implement an in-memory, git-like version control system driven by a script of commands on stdin. There is one repository, a working tree of text files, a staging area (the index), commits, branches, tags, three-way merges with conflicts, and diffs. The program always exits with status 0; every error is reported on stdout as a line `error: MESSAGE`.

All hashes are specified exactly, so commit ids must match the expected output byte for byte.

## Script format

Each line of stdin is a command. Blank lines and lines whose first non-blank character is `#` are ignored. For each command, first print `> ` followed by the command line with trailing whitespace removed, then run it. The command word is the first whitespace-separated token and the arguments are the remaining tokens. File names, branch names and refs contain no spaces.

`write FILE` and `append FILE` (with exactly one argument) are followed by a *content block*: the raw lines after the command, up to and not including a line that is exactly `.` (or up to the end of input). Those lines are consumed (not interpreted as commands, not echoed; they may be blank or start with `#`). If the arguments are wrong, an error is printed and nothing is consumed.

## Repository model

- **Working tree**: a set of files, each a sequence of lines (a file may have zero lines and still exist). A file's *content* is its lines each followed by `\n` (so an empty file has the empty content). Contents are compared as strings.
- **Index**: the staged tree, a mapping from file name to content. It starts empty.
- **Commits**: each has an id, parent ids (zero, one, or two), a message, and a full tree (name -> content). Commits are immutable.
- **Branches**: names pointing at commits. The repository starts with the branch `main` *unborn* (it exists, points to nothing) and HEAD attached to it. HEAD is either attached to a branch or *detached* at a commit.
- **Tags**: names pointing at commits; they never move.
- **Merge state**: when a merge stops with conflicts, the repository records the other commit, the merged branch name, and a set of conflicted paths.

### Hashes

FNV-1a, 64 bit: start with `h = 14695981039346656037`; for each byte `b` of the input: `h = h XOR b`, then `h = h * 1099511628211` (mod 2^64). A hash is printed as exactly 16 lowercase hex digits (`%016x`). The *short* form is its first 7 hex digits.

- The *tree hash* of a tree is the hash of the text made of one line per file, sorted by name in byte order: `NAME HASH\n` where HASH is the hash of the file's content.
- The *commit id* is the hash of the text `tree TREEHASH\n`, then `parent PARENTID\n` for each parent in order, then `\n`, then the message, then `\n`.

If a commit with the computed id already exists (same tree, parents, message), that existing commit is reused. Each commit gets a creation number (1, 2, 3, ... in order of creation) when it is first created; this decides the order in `log` and the choice of merge base.

### Refs

Wherever a command takes a REF, it may be `BASE` or `BASE~N` (N a non-negative integer, meaning N first-parent steps back; a malformed N, or stepping past a root commit, is an error). BASE is, tried in this order: `HEAD` (the commit HEAD points to; unborn is an error); a branch name that points at a commit; a tag name; a commit id given by a prefix of at least 4 lowercase hex digits (an ambiguous prefix is `ambiguous revision 'REF'`). If nothing matches: `unknown revision 'REF'` (REF as written).

## Commands

Errors never change state except where stated.

- `write FILE` / `append FILE`: set or extend the file with the content block (`append` to a missing file creates it).
- `rm FILE...`: remove working tree files; a missing file is `no such file: NAME` (earlier names are already removed). `mv OLD NEW`: rename (overwrites NEW). `cat FILE`: print the file's lines (nothing for an empty file; missing: `no such file: NAME`). `ls` (extra arguments ignored): working tree file names sorted by byte order, or `(empty)`. Wrong argument counts: `usage: rm FILE...`, `usage: mv OLD NEW`, `usage: cat FILE`, `usage: write FILE` / `usage: append FILE`.
- `add PATH...`: for each PATH in order: `.` stages every working file and stages the deletion of every index entry whose working file is missing; any other PATH stages the working file if it exists, or the deletion if it is missing from the working tree but present in the index, or (if the path is currently marked conflicted, see Merge) simply resolves that conflict; otherwise `pathspec 'PATH' did not match any files` (paths before it stay staged). Staging a path clears its conflict mark. No arguments: `usage: add PATH...`.
- `status` (extra arguments ignored): see Status.
- `commit MESSAGE...`: the message is the rest of the line after `commit`, trimmed. Checks in order: empty message -> `empty commit message`; conflicted paths remain -> `unresolved conflicts: a b c` (names sorted, space separated); if a merge is in progress, create a merge commit (below); otherwise if the index equals the tree of HEAD (an unborn HEAD counts as the empty tree) -> `nothing to commit`. Otherwise a commit with the index as its tree and HEAD's commit as its parent (none when unborn) is created, the current branch (or the detached HEAD) moves to it, and the output is `[BRANCH SHORT] MESSAGE`, or `[BRANCH (root-commit) SHORT] MESSAGE` for the first commit, where BRANCH is the branch name or the word `detached`.
- `log [-n N]`: lists the commits reachable from HEAD (the commit and all its ancestors via all parents), newest creation number first, one per line `SHORT MESSAGE`; a commit with two parents is `SHORT MESSAGE (merge SHORT1 SHORT2)`. `-n N` limits to the first N (N a non-negative integer). Other arguments: `usage: log [-n N]`. With no commits: `no commits yet`.
- `diff`, `diff REF`, `diff REF1 REF2`: see Diff.
- `branch` with no arguments lists branches sorted by name, one per line, `* NAME` for the current one and `  NAME` for the others (an unborn `main` is listed too); when HEAD is detached, a first line `* (HEAD detached at SHORT)`. `branch NAME` creates a branch at HEAD's commit: errors, in order: `invalid branch name 'NAME'` (names must match `[A-Za-z0-9._/][A-Za-z0-9._/-]*`), `branch 'NAME' already exists`, `no commits yet`. `branch -d NAME`: errors in order `branch 'NAME' not found`, `cannot delete the current branch 'NAME'`, `branch 'NAME' is not fully merged` (its commit is not HEAD's commit or an ancestor of it); otherwise it deletes it and prints `Deleted branch NAME (was SHORT).`. The form is chosen purely by the argument list: exactly two arguments with the first being `-d` is the delete form; exactly one argument (whatever it is) is the create form; anything else (zero arguments lists; three or more, or two arguments whose first is not `-d`) is `usage: branch [NAME | -d NAME]`. So a lone `branch -d` is the create form with NAME `-d` and prints `error: invalid branch name '-d'` (not the usage line), while `branch a b c` and `branch x y` print the usage line.
- `tag` with no arguments lists tag names sorted. `tag NAME [REF]` (REF defaults to HEAD) creates a tag; prints nothing. Errors in order: more than two arguments `usage: tag [NAME [REF]]`; `invalid tag name 'NAME'` (same rule as branches); `tag 'NAME' already exists`; if the REF is omitted or is exactly `HEAD` and HEAD is unborn `no commits yet`; then ref resolution errors.
- `show REF`: prints `commit FULLID`, `tree TREEHASH`, a `parent FULLID` line per parent, `message: MESSAGE`, `files:` and one line `  NAME SHORTHASH` per file (sorted), where SHORTHASH is the first 7 hex digits of the file content's hash. Wrong argument count: `usage: show REF`.
- `checkout -b NAME`: like `branch NAME` (same errors) followed by switching to it; prints `Switched to a new branch 'NAME'`.
- `checkout TARGET` (exactly one argument): errors in order: a merge is in progress -> `merge in progress`. If TARGET names a branch: if it is the current branch print `Already on 'NAME'` and stop; then the dirty check and untracked check below; then switch: print `Switched to branch 'NAME'`. Otherwise TARGET is resolved as a REF (errors as above, before the dirty check), the same checks run, and HEAD becomes detached at that commit: `HEAD is now at SHORT MESSAGE`. Switching sets the index to the target commit's tree and updates the working tree: first delete every working file whose name is in the *old index*, then write every file of the target tree. Other arguments: `usage: checkout REF | checkout -b NAME`. Again the form is chosen purely by the argument list: exactly two arguments with the first being `-b` is the `-b` form; exactly one argument (whatever it is) is the TARGET form; anything else (zero arguments, three or more, or two arguments whose first is not `-b`) is the usage line. So a lone `checkout -b` is a TARGET named `-b`: it is not a branch, so it is resolved as a REF and prints `error: unknown revision '-b'` (not the usage line). The `-b` form does not check for a merge in progress.
  - Dirty check (`local changes would be overwritten`): the index differs from HEAD's tree (unborn counts as empty), or some index entry's working file is missing or has different content.
  - Untracked check (`untracked file would be overwritten: NAME`, first such name in sorted order): a file in the target tree that is not in the index but exists in the working tree.
- `merge BRANCH` and `merge --abort`: see Merge.
- `reset --hard [REF]`: REF defaults to HEAD (unborn: `no commits yet`). Moves the current branch (or the detached HEAD) to that commit, sets the index to its tree, deletes from the working tree every file named in the old index or in the old HEAD tree, writes all files of the new tree, and clears any merge state and conflict marks. Untracked files are left alone. Prints `HEAD is now at SHORT MESSAGE`. Other forms: `usage: reset --hard [REF]`.
- Any other command word: `unknown command 'WORD'`.

## Status

`status` prints, in this order: `On branch NAME` (or `HEAD detached at SHORT`); if a merge is in progress `merging: BRANCH`; then up to four sections, each omitted if empty, formatted as the heading line `staged:` / `unstaged:` / `conflicts:` / `untracked:` followed by indented lines `  TEXT`; if all four sections are empty, the line `nothing to commit, working tree clean`.

- `staged`: for each name in the union of HEAD's tree and the index that is not conflicted, sorted: `new file: NAME` (in the index only), `deleted: NAME` (in HEAD only), `modified: NAME` (in both with different content).
- `unstaged`: for each index name that is not conflicted, sorted: `deleted: NAME` if the working file is missing, `modified: NAME` if its content differs from the index.
- `conflicts`: `unmerged: NAME` for each conflicted path, sorted.
- `untracked`: working files not in the index and not conflicted, sorted (listed by plain name).

## Diff

Line diffs use this exact algorithm. For sequences A and B of lines, define `L[i][j]` as the length of the longest common subsequence of `A[i:]` and `B[j:]` (the usual recurrence: if `A[i] == B[j]` then `1 + L[i+1][j+1]`, otherwise the maximum of `L[i+1][j]` and `L[i][j+1]`). The *matching pairs* are found by walking from `i = j = 0`: if `A[i] == B[j]`, record the pair and advance both; otherwise if `L[i+1][j] >= L[i][j+1]` advance `i` only, else advance `j` only; stop when either sequence is exhausted. A line diff walks the matching pairs: before each pair, all unmatched lines of A (prefixed `- `) and then all unmatched lines of B (prefixed `+ `); the matched line is printed with prefix two spaces; after the last pair, the remaining A lines then the remaining B lines.

`diff` compares two trees over the union of their file names, sorted: the index versus the working tree (no argument); the tree of REF versus the working tree; or the tree of REF1 versus the tree of REF2. For each name whose content differs print `diff NAME`, then `new file` (absent on the left) or `deleted file` (absent on the right), then the whole-file line diff (a missing file counts as no lines). If nothing differs print `(no differences)`. More than two arguments: `usage: diff [REF [REF]]`.

## Merge

`merge --abort`: without a merge in progress `no merge in progress`; otherwise perform `reset --hard` to HEAD's commit (without the `HEAD is now at` line) and print `Merge aborted.`.

`merge BRANCH` (exactly one argument, otherwise `usage: merge BRANCH`). Checks in order: `merge in progress` if one is running; `no commits yet` if HEAD is unborn; `unknown branch 'BRANCH'` (the branch must exist and point to a commit); `local changes would be overwritten` (the dirty check from `checkout`). Let `cur` be HEAD's commit and `other` the branch's commit.

1. If `other` is `cur` or an ancestor of `cur`: print `Already up to date.` and stop.
2. If `cur` is an ancestor of `other`: fast-forward. Run the untracked check against `other`'s tree, set the index and working tree as `checkout` does, move the current branch (or detached HEAD) to `other`, print `Fast-forward`.
3. Otherwise a three-way merge. The *merge base* is the common ancestor (a commit that is `cur` or an ancestor of `cur` and also `other` or an ancestor of `other`) with the greatest creation number; if there is none, the base tree is empty. Let B, O, T be the base, `cur` and `other` trees. For every file name in the union of the three, sorted, with `present?` meaning that the file exists in that tree:
   - if O and T are the same (both absent, or both present with equal content): the result is O;
   - else if O equals B (same presence and content): the result is T (possibly absent = deleted);
   - else if T equals B: the result is O;
   - else (both sides changed it differently):
     - if the file is absent on exactly one side (O or T): a *modify/delete* conflict. The working file becomes the surviving side's content; the index keeps O's version (absent if O is absent);
     - otherwise merge the line sequences with the three-way algorithm below. If it merges cleanly the result is the merged content. If not: the index keeps O's content, the working file is the merged text with conflict markers, and the conflict kind is `content` if the file exists in B, `add/add` if it does not.

   Before changing anything, run the untracked check for every name that appears in the result tree or in the working-file overrides (an untracked working file with that name, first in sorted order: `untracked file would be overwritten: NAME`).

   Then apply: working files of names in the old index that are not in the result tree are deleted; result files are written; conflicted files are written with their conflict text or surviving side; the index becomes the result tree (conflicted names as described).

   - No conflicts: create a merge commit with parents `[cur, other]`, message `Merge branch 'BRANCH'` and the result tree; move the branch or detached HEAD; print `Merge made by the 'three-way' strategy.` then `[BRANCH SHORT] Merge branch 'BRANCH'`.
   - With conflicts: record the merge state (other commit, branch name, conflicted names). Print, for each conflicted name sorted: `CONFLICT (content): Merge conflict in NAME`, `CONFLICT (add/add): Merge conflict in NAME`, or `CONFLICT (modify/delete): NAME`; then `Automatic merge failed; fix conflicts and then commit the result.` No commit is made.

After a conflicted merge the user edits files and runs `add PATH` for each conflicted path (which clears the mark); `commit MESSAGE` with no remaining conflicts creates the merge commit with parents `[HEAD commit, merged commit]`, the index as its tree and the given message (even if the tree equals HEAD's), clears the merge state, and prints `[BRANCH SHORT] MESSAGE`.

### Three-way line merge

Given line sequences `base`, `ours`, `theirs`: compute the matching pairs (as in Diff) of `base` against `ours` and of `base` against `theirs`. A base line index is *stable* if it has a pair in both. Walk the stable lines in increasing order; between consecutive stable lines (with virtual stable lines before the start and after the end) take the three *chunks*: the base lines, ours lines, theirs lines strictly between the surrounding stable positions. Resolve each chunk: if ours chunk equals base chunk, output theirs chunk; else if theirs equals base, output ours; else if ours equals theirs, output ours; else it is a conflict and the output is the lines `<<<<<<< HEAD`, the ours chunk, `=======`, the theirs chunk, `>>>>>>> BRANCH` (BRANCH is the merged branch name). After each chunk, output the stable base line itself (except after the final chunk). The merged file content is the output lines each followed by `\n` (zero lines = empty content).

## Errors summary

Unless stated, errors have the shape `error: MESSAGE` on its own line after the echoed command. The exit status is always 0.
