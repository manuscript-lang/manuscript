#!/usr/bin/env python3
"""Compare formatter binaries, retaining all output-checked paired samples."""
import argparse
import csv
import math
import statistics
import subprocess
from pathlib import Path


def run(binary, count, shape, rounds, cpu):
    command = [str(binary), str(count), str(rounds), shape]
    if cpu is not None:
        command = ["taskset", "--cpu-list", str(cpu), *command]
    fields = subprocess.check_output(command, text=True).strip().split(",")
    assert len(fields) == 8 and fields[:3] == [str(count), str(rounds), shape], fields
    return tuple(map(int, fields[3:]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--cpu", type=int)
    args = parser.parse_args()
    assert args.samples >= 5
    binaries = {"before": args.before.resolve(), "after": args.after.resolve()}
    cases = [(n, shape) for n in (1, 8, 28, 29, 30, 31, 32, 128, 512, 2048)
             for shape in ("flow", "pipe", "member")]
    cases += [(n, shape) for n in (1, 32, 512)
              for shape in ("nonempty", "clause", "inline", "unicode", "crlf", "comments")]
    cases += [(n, "functions") for n in (1, 100, 1000)]
    cases += [(n, shape) for n in (1, 32, 512, 8192)
              for shape in ("list-flat", "list-lines")]
    with args.out.open("w") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(("count", "shape", "sample", "binary", "rounds", "elapsed_ns",
                         "checksum_per_query", "source_bytes", "output_bytes", "peak_rss_kib", "cpu"))
        for count, shape in cases:
            rounds, observations, expected = {}, {"before": [], "after": []}, None
            for name, binary in binaries.items():
                elapsed, checksum, size, output_size, _ = run(binary, count, shape, 1, args.cpu)
                identity = (checksum, size, output_size)
                if expected is None:
                    expected = identity
                assert identity == expected
                rounds[name] = min(100_000, max(1, math.ceil(30_000_000 / elapsed)))
            for sample in range(args.samples):
                order = ("before", "after") if sample % 2 == 0 else ("after", "before")
                for name in order:
                    elapsed, checksum, size, output_size, rss = run(
                        binaries[name], count, shape, rounds[name], args.cpu
                    )
                    assert (checksum, size, output_size) == expected
                    observations[name].append(elapsed / rounds[name])
                    writer.writerow((count, shape, sample, name, rounds[name], elapsed,
                                     checksum, size, output_size, rss, args.cpu))
                    stream.flush()
            old, new = (statistics.median(observations[key]) for key in ("before", "after"))
            print(f"{count},{shape},before={old:.0f}ns,after={new:.0f}ns,ratio={new / old:.3f}", flush=True)


if __name__ == "__main__":
    main()
