"""Summarize successful measured trials; keep warm-ups and raw samples in the input."""
import argparse
import collections
import json
import pathlib
import statistics

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=pathlib.Path)
args = parser.parse_args()
groups = collections.defaultdict(list)
for path in sorted(args.directory.glob("*.jsonl")):
    if path.name.startswith("llvm-"):
        continue
    for line in path.read_text().splitlines():
        sample = json.loads(line)
        if "trial" not in sample or sample["trial"] < 0 or sample["phase"].startswith("validate"):
            continue
        assert sample["exit"] == 0 and sample.get("correct", True), sample
        groups[sample["phase"], sample["case"], sample["label"]].append(sample)


def stats(values):
    return dict(n=len(values), median=statistics.median(values), minimum=min(values), maximum=max(values))


result = []
for (phase, case, label), samples in sorted(groups.items()):
    entry = dict(phase=phase, case=case, label=label)
    for field in ["wall_s", "user_s", "system_s", "maxrss_kib"]:
        entry[field] = stats([s[field] for s in samples])
    entry["isolated_rss"] = all(s.get("isolated_rss", False) for s in samples)
    if phase == "stages":
        entry["stages"] = {stage["stage"]: stats([next(t["seconds"] for t in s["stages"] if t["stage"] == stage["stage"]) for s in samples])
                           for stage in samples[0]["stages"]}
        entry["llvm"] = {tool: {field: stats([next(t[field] for t in s["llvm"] if t["tool"] == tool) for s in samples])
                               for field in ["wall_s", "user_s", "system_s", "maxrss_kib"]}
                         for tool in ["opt", "llc"]}
    result.append(entry)
assert result, "empty measurement inventory"
print(json.dumps(result, indent=2))
