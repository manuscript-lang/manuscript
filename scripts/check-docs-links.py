"""Check generated HTML links and assets without requesting external websites."""

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.ids = set()
        self.links = []
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name == "id" or (tag == "a" and name == "name"):
                self.ids.add(value)
            if name in ("href", "src") and value:
                self.links.append(value)


def main():
    root = Path(sys.argv[1]).resolve()
    base = urlsplit(sys.argv[2].rstrip("/") + "/")
    pages = {path: Page(path) for path in root.rglob("*.html")}
    errors = []
    checked = 0
    if not (root / "index.html").is_file():
        errors.append("Missing generated index.html")
    for path, page in pages.items():
        source = urljoin(base.geturl(), path.relative_to(root).as_posix())
        for link in page.links:
            target = urlsplit(urljoin(source, link))
            if target.hostname in ("localhost", "127.0.0.1"):
                errors.append(f"{path.relative_to(root)}: preview URL {link}")
                continue
            if (target.scheme, target.netloc) != (base.scheme, base.netloc):
                continue
            checked += 1
            if not target.path.startswith(base.path):
                errors.append(f"{path.relative_to(root)}: outside site base path: {link}")
                continue
            dest = (root / unquote(target.path[len(base.path):])).resolve()
            if not dest.is_relative_to(root):
                errors.append(f"{path.relative_to(root)}: outside output directory: {link}")
                continue
            if dest.is_dir():
                dest /= "index.html"
            if not dest.is_file():
                errors.append(f"{path.relative_to(root)}: missing target: {link}")
            elif target.fragment and dest in pages:
                if unquote(target.fragment) not in pages[dest].ids:
                    errors.append(f"{path.relative_to(root)}: missing anchor: {link}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Checked {checked} local links/assets across {len(pages)} HTML pages.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
