import unittest

from compare_stdlib import parse_sample


class LibrarySamples(unittest.TestCase):
    def test_requires_consumed_checksum(self):
        with self.assertRaises(ValueError):
            parse_sample("operation\t10\t20\n", case_count=1)

    def test_rejects_wrong_work_even_when_faster(self):
        _, expected = parse_sample("operation\t10\t20\n# checksum operation 45\n", case_count=1)
        for output in ("operation\t10\t1\n# checksum operation 0\n",
                       "operation\t1\t1\n# checksum operation 45\n"):
            with self.assertRaises(ValueError):
                parse_sample(output, expected, case_count=1)

    def test_requires_complete_unique_measurements(self):
        for output in ("operation\t10\t20\n# checksum other 45\n",
                       "operation\t10\t20\noperation\t10\t20\n# checksum operation 45\n",
                       "operation\t10\t20\n# checksum operation 45\n# checksum operation 45\n"):
            with self.assertRaises(ValueError):
                parse_sample(output, case_count=1)

    def test_accepts_negative_and_zero_checksums(self):
        rows, identity = parse_sample("a\t10\t20\n# checksum a -45\nb\t1\t0\n# checksum b 0\n", case_count=2)
        self.assertEqual(rows, {"a": (10, 20), "b": (1, 0)})
        self.assertEqual(identity, {"a": (10, -45), "b": (1, 0)})

    def test_uses_raw_elapsed_time_without_integer_rounding(self):
        output = "operation\t100\t0\n# checksum operation 45\n# elapsed operation 37\n"
        rows, _ = parse_sample(output, case_count=1, require_elapsed=True)
        self.assertEqual(rows["operation"], (100, 0.37))

    def test_rejects_missing_duplicate_or_inconsistent_elapsed_time(self):
        prefix = "operation\t10\t20\n# checksum operation 45\n"
        for suffix in ("", "# elapsed operation -1\n", "# elapsed operation 199\n",
                       "# elapsed operation 200\n# elapsed operation 200\n",
                       "# elapsed other 200\n"):
            with self.assertRaises(ValueError):
                parse_sample(prefix + suffix, case_count=1, require_elapsed=True)


if __name__ == "__main__":
    unittest.main()
