import importlib.util
import json
import statistics
import unittest
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).parent
spec = importlib.util.spec_from_file_location("priority_measure", ROOT / "measure.py")
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class PriorityEvidence(unittest.TestCase):
    def test_oracle_matches_independent_collection_models(self):
        for operation, size, shape, repeats in measure.cases():
            values = measure.values_for(size, shape)
            if operation == "deque":
                model = deque()
                for index, value in enumerate(values):
                    (model.appendleft if index % 2 == 0 else model.append)(value)
                result = list(model)
            elif operation == "priority":
                result = [value for value, _ in sorted((value, index) for index, value in enumerate(values))]
            else:
                result = list(deque(values))
            checksum = sum((value + 1) * (index + 1) for index, value in enumerate(result)) * repeats
            self.assertEqual(measure.expected(operation, size, shape, repeats), checksum)
            self.assertLess(checksum, 2**63)

    def test_recorded_trials_are_complete_and_correct(self):
        full = {(operation, size, shape, repeats) for operation, size, shape, repeats in measure.cases()}
        self.assertEqual(len(full), 36)
        total_samples = 0
        for name in ("extra-branch-samples.json", "grouped-samples.json", "focused-samples.json", "aa-samples.json", "fresh-main-samples.json"):
            evidence = json.loads((ROOT / name).read_text())
            identities = set()
            for case in evidence["cases"]:
                identity = (case["operation"], case["size"], case["shape"], case["repeats"])
                self.assertNotIn(identity, identities)
                identities.add(identity)
                self.assertEqual(case["checksum"], measure.expected(*identity))
                self.assertEqual(Counter((sample["version"], sample["trial"]) for sample in case["samples"]),
                                 Counter({(version, trial): 1 for version in ("ms", "candidate", "rust")
                                          for trial in range(evidence["trials"])}))
                self.assertTrue(all(sample["nanoseconds"] > 0 for sample in case["samples"]))
                for version in ("ms", "candidate", "rust"):
                    median = statistics.median(sample["nanoseconds"] / case["repeats"]
                                               for sample in case["samples"] if sample["version"] == version)
                    self.assertEqual(case["median_ns_per_iteration"][version], median)
                total_samples += len(case["samples"])
            if name in ("extra-branch-samples.json", "grouped-samples.json", "fresh-main-samples.json"):
                self.assertEqual(identities, full)
            else:
                self.assertEqual(len(identities), 6)
            if name in ("aa-samples.json", "fresh-main-samples.json"):
                self.assertEqual(evidence["binaries"]["ms"], evidence["binaries"]["candidate"])
        self.assertEqual(total_samples, 2520)


if __name__ == "__main__":
    unittest.main()
