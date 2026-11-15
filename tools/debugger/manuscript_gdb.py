"""GDB pretty-printers for Manuscript values.

Load with `source tools/debugger/manuscript_gdb.py` (or from ~/.gdbinit). Programs built by
`ms build` describe String, List[T], T?, records and enums as DWARF structs, so any value of
those types, found through `print *(String*)$addr`, a struct member or a frame's memory, prints
as the language shows it. Layout rules: `ms_rt_abi::StrVal` (strings), `ms_mir::layout`.
"""
import gdb
import gdb.printing

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manuscript_values as values  # noqa: E402


def _u(value):
    return int(value) & 0xFFFFFFFFFFFFFFFF


def _read(address, count):
    return gdb.selected_inferior().read_memory(address, count)


class StringPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        ptr, tagged = _u(self.value["ptr"]), _u(self.value["tagged"])
        optional = (self.value.type.strip_typedefs().tag or "").endswith("?")
        return values.string_text(ptr, tagged, _read, optional)


class ListPrinter:
    def __init__(self, value):
        self.value = value

    def to_string(self):
        return values.list_summary(self.value.type.strip_typedefs().tag, _u(self.value["len"]))

    def children(self):
        count = values.shown(_u(self.value["len"]))
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
        count = values.shown(length)
        raw = bytes(_read(_u(self.value["ptr"]), count)) if count else b""
        return "b%s%s" % (values.quote(raw), "..." if length > count else "")


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
        names = [f.name for f in self.value["payload"].type.strip_typedefs().fields()]
        return values.enum_case(_u(self.value["tag"]), names)

    def children(self):
        if self.case is None:
            return
        payload = self.value["payload"][self.case.name]
        for field in payload.type.strip_typedefs().fields():
            yield field.name, payload[field.name]


class Guarded:
    """Shows `<optimized out>` where a part of the value has no location at this pc."""

    def __init__(self, printer):
        self.printer = printer

    def to_string(self):
        try:
            return self.printer.to_string()
        except gdb.error:
            return "<optimized out>"

    def display_hint(self):
        hint = getattr(self.printer, "display_hint", None)
        return hint() if hint else None


class GuardedChildren(Guarded):
    def children(self):
        try:
            yield from self.printer.children()
        except gdb.error:
            return


def guard(printer):
    if printer is None:
        return None
    return (GuardedChildren if hasattr(printer, "children") else Guarded)(printer)


def lookup(value):
    try:
        return guard(find(value))
    except gdb.error:
        return None


def find(value):
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
