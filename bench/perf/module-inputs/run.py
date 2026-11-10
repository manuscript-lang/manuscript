#!/usr/bin/env python3
"""Prepare identical inputs, then alternate two release loader binaries."""
import csv
from pathlib import Path
import resource
import subprocess
import sys
import tempfile

before, after, output = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix="ms-module-inputs-") as temporary:
    root = Path(temporary).resolve()
    with output.open("w", newline="") as out:
        writer = csv.writer(out)
        writer.writerow(["modules", "round", "variant", "load_ms", "process_user_s", "process_system_s", "minor_faults", "major_faults"])
        for count in [1, 16, 128, 2000, 4000, 8000, 16000]:
            directory = root / str(count)
            directory.mkdir()
            source = []
            for i in range(count):
                (directory / f"f{i}.ms").write_text(f"export fn f{i}() Int: {i}\n")
                source.append(f'import f{i} from "./f{i}.ms"\n')
            entry = directory / "main.ms"
            entry.write_text("".join(source) + "export fn main() Int: 0\n")
            for round_number in range(10):
                variants = [("before", before), ("after", after)]
                if round_number % 2:
                    variants.reverse()
                for variant, binary in variants:
                    prior = resource.getrusage(resource.RUSAGE_CHILDREN)
                    result = subprocess.run([str(binary.resolve()), str(entry), str(count), "50" if count < 200 else "1"], check=True, capture_output=True, text=True)
                    current = resource.getrusage(resource.RUSAGE_CHILDREN)
                    if round_number:  # First pair warms each data set and executable.
                        writer.writerow([count, round_number, variant, result.stdout.strip(), current.ru_utime-prior.ru_utime, current.ru_stime-prior.ru_stime, current.ru_minflt-prior.ru_minflt, current.ru_majflt-prior.ru_majflt])
                        out.flush()
