import unittest

from table import OPS, SINK, summarize


def sample(version):
    return [f"{version} {name} {count} {count * 2}\n" for name, count in OPS.items()] + [
        f"{version} # sink {' '.join(map(str, SINK))}\n"
    ]


class TableTests(unittest.TestCase):
    def test_complete_equivalent_work(self):
        result = summarize(sample("ms") + sample("go"), 1)
        self.assertIn("1.00x", result)
        self.assertIn("Checksums and operation counts verified", result)

    def test_extra_versions_add_columns(self):
        result = summarize(sample("ms") + sample("go") + sample("rust") + sample("rust-checked"), 1)
        self.assertIn("| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |", result)
        self.assertEqual(result.count("1.00x"), 3 * len(OPS))

    def test_rejects_invalid_evidence(self):
        valid = sample("ms") + sample("go")
        cases = [
            valid[:-1],  # A process stopped before its checksum.
            valid + sample("ms"),
            [valid[0].replace("50000 100000", "1 100000")] + valid[1:],
            [valid[0].replace("100000", "0")] + valid[1:],
            valid[:-1] + [valid[-1].replace("50000", "49999")],
            [valid[0]] + valid,
            ["unrecognized output\n"] + valid,
        ]
        for lines in cases:
            with self.subTest(lines=lines):
                with self.assertRaises(ValueError):
                    summarize(lines, 1)


if __name__ == "__main__":
    unittest.main()
