#!/usr/bin/env python3
"""Compare complete LSP results and error/revert diagnostics on identical input."""
import argparse
import hashlib
import json
import pathlib

from wire_bench import Session, fixture


def capture(binary, root, files):
    s = Session(binary, root)
    results = {}
    try:
        s.initialize(root)
        for file in files[:10]:
            s.open(file)
        uri = files[0].as_uri()
        text = files[0].read_text()
        line = text[:text.index("f_0_0(1)")].count("\n")
        params = {"textDocument": {"uri": uri}, "position": {"line": line, "character": 20}}
        for method in ["hover", "definition", "completion", "signatureHelp", "semanticTokens/full",
                       "documentSymbol", "typeDefinition", "documentHighlight", "foldingRange",
                       "inlayHint", "formatting"]:
            request = {**params}
            if method == "signatureHelp":
                request["position"] = {"line": line, "character": 24}
            if method == "inlayHint":
                request["range"] = {"start": {"line": 0, "character": 0},
                                    "end": {"line": line + 2, "character": 0}}
            if method == "formatting":
                request["options"] = {"tabSize": 4, "insertSpaces": True}
            _, result, _ = s.request("textDocument/" + method, request)
            results[method] = result
        for method, request in [
            ("textDocument/references", {**params, "context": {"includeDeclaration": True}}),
            ("workspace/symbol", {"query": "f_0_0"}),
            ("textDocument/rename", {**params, "newName": "renamed_function"}),
        ]:
            _, result, _ = s.request(method, request)
            assert result, (method, result)
            results[method] = result
        assert results["hover"] and results["definition"] and results["completion"]
        assert results["semanticTokens/full"]["data"] and results["documentSymbol"]
        assert len(results["textDocument/references"]) == 3

        # Explicit request barriers require the malformed version to be visible;
        # a legitimate coalesced burst may omit an obsolete intermediate version.
        for version, source in [(2, text.replace("f_0_0(1)", "missing(1)")), (3, text)]:
            s.send("textDocument/didChange", {"textDocument": {"uri": uri, "version": version},
                                            "contentChanges": [{"text": source}]})
            s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
            notices = [n[1]["params"] for n in s.notifications]
            s.notifications = []
            assert len(notices) == 10, notices
            own = next(n for n in notices if n["uri"] == uri)
            assert own["version"] == version
            errors = [d for d in own["diagnostics"] if d["severity"] == 1]
            assert bool(errors) == (version == 2), own
            results[f"diagnostics_v{version}"] = notices
        return results
    finally:
        s.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--before", type=pathlib.Path, required=True)
    p.add_argument("--after", type=pathlib.Path, required=True)
    p.add_argument("--out", type=pathlib.Path, required=True)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    root, files = fixture(args.out / "fixtures", "equivalence", 40, 20)
    before = capture(args.before.resolve(), root, files)
    after = capture(args.after.resolve(), root, files)
    (args.out / "before.json").write_text(json.dumps(before, indent=2) + "\n")
    (args.out / "after.json").write_text(json.dumps(after, indent=2) + "\n")
    mismatches = [key for key in before if before[key] != after[key]]
    evidence = {"equal": not mismatches, "mismatches": mismatches,
                "methods": {key: {"sha256": hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest(),
                                  "json_bytes": len(json.dumps(value).encode())}
                            for key, value in before.items()}}
    (args.out / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))
    assert not mismatches, mismatches


if __name__ == "__main__":
    main()
