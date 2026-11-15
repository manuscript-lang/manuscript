"""GDB pretty-printers for Manuscript values.

Load with `source tools/debugger/manuscript_gdb.py` (or from ~/.gdbinit). Programs built by
`ms build` describe String, List[T], T?, records and enums as DWARF structs, so any value of
those types, found through `print *(String*)$addr`, a struct member or a frame's memory, prints
as the language shows it. Layout rules: `ms_rt_abi::StrVal` (strings), `ms_mir::layout`.
"""
import gdb
import gdb.printing

STR_BORROWED = 1 << 63
STR_INLINE = 1 << 62
LEN_MASK = (1 << 61) - 1
MAX_SHOWN = 200


def _u(value):
    return int(value) & 0xFFFFFFFFFFFFFFFF


def _quote(raw):
    text = raw.decode("utf-8", "replace")
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + escaped + '"'


def string_bytes(ptr_word, tagged):
    """The bytes of a String value given its two words."""
    if tagged >> 62 == 1:
        length = (tagged >> 56) & 15
        bits = ptr_word | ((tagged & ((1 << 56) - 1)) << 64)
        return bits.to_bytes(16, "little")[:length]
    length = tagged & LEN_MASK
    if ptr_word == 0 or length == 0:
        return b""
    inferior = gdb.selected_inferior()
    return bytes(inferior.read_memory(ptr_word, min(length, 1 << 20)))


class StringPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        ptr, tagged = _u(self.value["ptr"]), _u(self.value["tagged"])
        # `String?`: none is a null pointer with the static tag and length zero.
        optional = (self.value.type.strip_typedefs().tag or "").endswith("?")
        if optional and ptr == 0 and tagged & STR_BORROWED:
            return "none"
        return _quote(string_bytes(ptr, tagged))


class ListPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        return "%s of length %d" % (self.value.type.strip_typedefs().tag, _u(self.value["len"]))

    def children(self):
        count = min(_u(self.value["len"]), MAX_SHOWN)
        data = self.value["ptr"]
        for i in range(count):
            yield "[%d]" % i, data[i]

    def display_hint(self):
        return "array"


class BytesPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        length = _u(self.value["len"])
        raw = bytes(gdb.selected_inferior().read_memory(_u(self.value["ptr"]), min(length, MAX_SHOWN))) if length else b""
        return "b%s%s" % (_quote(raw), "..." if length > MAX_SHOWN else "")


class OptionalPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        return "some" if _u(self.value["present"]) else "none"

    def children(self):
        if _u(self.value["present"]):
            yield "value", self.value["value"]


class EnumPrinter:
    """An enum: `tag` picks the case whose payload struct is shown."""

    def __init__(self, value):
        self.value = value
        cases = value["payload"].type.strip_typedefs().fields()
        tag = _u(value["tag"])
        self.case = cases[tag] if tag < len(cases) else None

    def to_string(self):
        return self.case.name if self.case else "<bad tag %d>" % _u(self.value["tag"])

    def children(self):
        if self.case is None:
            return
        payload = self.value["payload"][self.case.name]
        for field in payload.type.strip_typedefs().fields():
            yield field.name, payload[field.name]


def lookup(value):
    kind = value.type.strip_typedefs()
    if kind.code != gdb.TYPE_CODE_STRUCT or kind.tag is None:
        return None
    names = [f.name for f in kind.fields()]
    tag = kind.tag
    # Match the shape as well as the name: a user record may be called `String`.
    if tag in ("String", "String?") and names == ["ptr", "tagged"]:
        return StringPrinter(value)
    if tag == "Bytes" and names == ["ptr", "len", "cap"]:
        return BytesPrinter(value)
    if tag.startswith("List[") and not tag.endswith("?") and names == ["ptr", "len", "cap"]:
        return ListPrinter(value)
    if names == ["present", "value"] or names == ["present"]:
        return OptionalPrinter(value)
    if names == ["tag", "payload"]:
        return EnumPrinter(value)
    return None


def register(objfile=None):
    gdb.pretty_printers.append(lookup)


register()
