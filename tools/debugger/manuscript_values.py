"""Decoding of Manuscript values shared by the gdb and lldb display helpers.

Pure Python, no debugger types: the adapters read memory and members and pass plain integers
and callables, so the rules can be tested without a debugger (`test_values.py`). Layouts:
`ms_rt_abi::StrVal` (strings) and `ms_mir::layout` (lists, optionals, enums).
"""

STR_BORROWED = 1 << 63
LEN_MASK = (1 << 31) - 1
MAX_SHOWN = 200
MAX_BYTES = 1 << 20


def quote(raw):
    """A string literal as Manuscript source writes it."""
    text = raw.decode("utf-8", "replace")
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + escaped + '"'


def is_inline(tagged):
    return tagged >> 62 == 1


def is_none(ptr, tagged):
    """`String?` none: a null pointer with the static tag and length zero."""
    return ptr == 0 and bool(tagged & STR_BORROWED) and (tagged & LEN_MASK) == 0


def string_bytes(ptr, tagged, read):
    """The bytes of a String given its two words; `read(address, count)` reads memory."""
    if is_inline(tagged):
        length = (tagged >> 56) & 15
        bits = ptr | ((tagged & ((1 << 56) - 1)) << 64)
        return bits.to_bytes(16, "little")[:length]
    length = tagged & LEN_MASK
    if ptr == 0 or length == 0:
        return b""
    return bytes(read(ptr, min(length, MAX_BYTES)))


def string_text(ptr, tagged, read, optional=False):
    if optional and is_none(ptr, tagged):
        return "none"
    return quote(string_bytes(ptr, tagged, read))


def list_summary(name, length):
    return "%s of length %d" % (name, length)


def shown(length):
    """How many elements to show."""
    return min(length, MAX_SHOWN)


def enum_case(tag, case_names):
    return case_names[tag] if 0 <= tag < len(case_names) else "<bad tag %d>" % tag
