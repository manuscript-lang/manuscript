"""Count lexical tokens in the source an agent produced (language-neutral, dependency-free).

A token is an identifier or keyword, a number, a string literal, or one punctuation/operator character. Comments are
excluded. This is a size measure of the final program, not any model's tokenizer count.
"""
import re
from pathlib import Path

SKIP_DIRS = {"target", "node_modules", ".bench", "docs", "examples", ".git", "vendor", ".ms-cache"}
_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/|#[^\n]*" , re.S)
_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`[^`]*`|[A-Za-z_]\w*|\d[\w.]*|[^\s\w]')


def count_text(text: str, hash_comments: bool = False) -> int:
    if not hash_comments:
        text = re.sub(r"//[^\n]*|/\*.*?\*/", " ", text, flags=re.S)
    else:
        text = _COMMENT.sub(" ", text)
    return len(_TOKEN.findall(text))


def count_workspace(root: Path, suffix: str) -> int:
    total = 0
    for p in Path(root).rglob(f"*{suffix}"):
        if p.is_file() and not (set(p.relative_to(root).parts[:-1]) & SKIP_DIRS):
            total += count_text(p.read_text(errors="replace"))
    return total
