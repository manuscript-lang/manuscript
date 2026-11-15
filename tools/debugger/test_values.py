"""Tests of the display helpers' decoding (`python3 test_values.py`); no debugger needed.

Words below are what `ms_rt_abi::StrVal` and `ms_mir::layout` store; a change to those layouts
must change `manuscript_values.py` and these cases together.
"""
import ast
import os
import unittest

import manuscript_values as values

HERE = os.path.dirname(os.path.abspath(__file__))
INLINE = 1 << 62
STATIC = 1 << 63
VIEW = 3 << 62


def inline_words(raw):
    """The two words of an inline string holding `raw` (at most 15 bytes)."""
    bits = int.from_bytes(raw.ljust(16, b"\0"), "little")
    ptr = bits & ((1 << 64) - 1)
    tagged = (bits >> 64) | INLINE | (len(raw) << 56)
    return ptr, tagged


def memory(address, data):
    def read(at, count):
        assert address <= at and at + count <= address + len(data), "read outside the block"
        return data[at - address : at - address + count]

    return read


class StringTests(unittest.TestCase):
    def test_inline(self):
        ptr, tagged = inline_words(b"pt")
        self.assertEqual(values.string_text(ptr, tagged, None), '"pt"')

    def test_longest_inline(self):
        ptr, tagged = inline_words(b"fifteen bytes!!")
        self.assertEqual(values.string_bytes(ptr, tagged, None), b"fifteen bytes!!")

    def test_owned_static_and_view_read_memory(self):
        text = b"hello, world, longer than fifteen"
        read = memory(0x1000, text)
        for tag in (0, STATIC, VIEW):
            self.assertEqual(
                values.string_bytes(0x1000, len(text) | tag, read), text, hex(tag)
            )

    def test_ascii_flag_is_not_part_of_the_length(self):
        text = b"abcdefghijklmnopqrstu"
        read = memory(0x2000, text)
        tagged = len(text) | (1 << 61)
        self.assertEqual(values.string_bytes(0x2000, tagged, read), text)

    def test_empty_and_null(self):
        self.assertEqual(values.string_bytes(0, STATIC, None), b"")
        self.assertEqual(values.string_text(0, STATIC, None), '""')

    def test_optional_none_is_a_null_static_string(self):
        self.assertEqual(values.string_text(0, STATIC, None, optional=True), "none")
        ptr, tagged = inline_words(b"")
        self.assertEqual(values.string_text(ptr, tagged, None, optional=True), '""')

    def test_quoting(self):
        ptr, tagged = inline_words(b'a"b\\\n')
        self.assertEqual(values.string_text(ptr, tagged, None), '"a\\"b\\\\\\n"')

    def test_long_strings_are_capped(self):
        length = values.MAX_BYTES + 5
        calls = []

        def read(at, count):
            calls.append(count)
            return b"x" * count

        values.string_bytes(0x10, length, read)
        self.assertEqual(calls, [values.MAX_BYTES])


class ShapeTests(unittest.TestCase):
    def test_enum_case(self):
        self.assertEqual(values.enum_case(1, ["Circle", "Rect", "Empty"]), "Rect")
        self.assertEqual(values.enum_case(7, ["Circle"]), "<bad tag 7>")
        self.assertEqual(values.enum_case(-1, ["Circle"]), "<bad tag -1>")

    def test_list(self):
        self.assertEqual(values.list_summary("List[Int]", 3), "List[Int] of length 3")
        self.assertEqual(values.shown(5), 5)
        self.assertEqual(values.shown(10**9), values.MAX_SHOWN)


class AdapterTests(unittest.TestCase):
    def test_adapters_parse(self):
        # The adapters import gdb or lldb, so only their syntax can be checked here.
        for name in ("manuscript_gdb.py", "manuscript_lldb.py"):
            with open(os.path.join(HERE, name), encoding="utf-8") as source:
                ast.parse(source.read(), name)


if __name__ == "__main__":
    unittest.main()
