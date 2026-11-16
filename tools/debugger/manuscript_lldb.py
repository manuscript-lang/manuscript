"""LLDB data formatters for Manuscript values.

Load with `command script import tools/debugger/manuscript_lldb.py` (or from ~/.lldbinit).
Programs built by `ms build` describe String, List[T], T?, records and enums as DWARF structs;
this prints them as the language shows them, in `frame variable`, `expression` and
`memory read --type`. The decoding rules are in `manuscript_values.py`.
"""
import os
import sys

import lldb

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manuscript_values as values  # noqa: E402

MODULE = "manuscript_lldb"


def _word(value, name):
    return value.GetNonSyntheticValue().GetChildMemberWithName(name).GetValueAsUnsigned()


def _reader(value):
    process = value.GetProcess()

    def read(address, count):
        error = lldb.SBError()
        data = process.ReadMemory(address, count, error)
        if error.Fail():
            raise RuntimeError(error.GetCString())
        return data

    return read



def string_summary(value, _internal):
    optional = value.GetNonSyntheticValue().GetType().GetName().endswith("?")
    try:
        return values.string_text(
            _word(value, "ptr"), _word(value, "tagged"), _reader(value), optional
        )
    except RuntimeError as error:
        return "<unreadable: %s>" % error


def bytes_summary(value, _internal):
    length = _word(value, "len")
    count = values.shown(length)
    try:
        raw = bytes(_reader(value)(_word(value, "ptr"), count)) if count else b""
    except RuntimeError as error:
        return "<unreadable: %s>" % error
    return "b%s%s" % (values.quote(raw), "..." if length > count else "")


def list_summary(value, _internal):
    name = value.GetNonSyntheticValue().GetType().GetName()
    return values.list_summary(name, _word(value, "len"))


class ListChildren:
    """The elements of a `List[T]`, so `frame variable` expands them."""

    def __init__(self, value, _internal):
        self.value = value.GetNonSyntheticValue()

    def update(self):
        data = self.value.GetChildMemberWithName("ptr")
        self.element = data.GetType().GetPointeeType()
        self.start = data.GetValueAsUnsigned()
        self.count = values.shown(self.value.GetChildMemberWithName("len").GetValueAsUnsigned())
        return False

    def num_children(self):
        return self.count

    def get_child_at_index(self, index):
        if not 0 <= index < self.count:
            return None
        size = self.element.GetByteSize()
        return self.value.CreateValueFromAddress("[%d]" % index, self.start + index * size, self.element)

    def has_children(self):
        return self.count > 0


def optional_summary(value, _internal):
    return "some" if _word(value, "present") else "none"


class OptionalChildren:
    def __init__(self, value, _internal):
        self.value = value.GetNonSyntheticValue()

    def update(self):
        self.present = self.value.GetChildMemberWithName("present").GetValueAsUnsigned() != 0
        return False

    def num_children(self):
        return 1 if self.present else 0

    def get_child_at_index(self, index):
        return self.value.GetChildMemberWithName("value") if self.present and index == 0 else None

    def has_children(self):
        return self.present


def _case(value):
    payload = value.GetNonSyntheticValue().GetChildMemberWithName("payload")
    kind = payload.GetType()
    cases = [kind.GetFieldAtIndex(i).GetName() for i in range(kind.GetNumberOfFields())]
    tag = _word(value, "tag")
    name = values.enum_case(tag, cases)
    return payload, name if 0 <= tag < len(cases) else None, name


def enum_summary(value, _internal):
    return _case(value)[2]


class EnumChildren:
    """The fields of the case the tag selects."""

    def __init__(self, value, _internal):
        self.value = value

    def update(self):
        payload, case, _ = _case(self.value)
        self.fields = payload.GetChildMemberWithName(case) if case else None
        return False

    def num_children(self):
        return self.fields.GetNumChildren() if self.fields else 0

    def get_child_at_index(self, index):
        return self.fields.GetChildAtIndex(index) if self.fields else None

    def has_children(self):
        return self.num_children() > 0


def _shape(kind):
    return [kind.GetFieldAtIndex(i).GetName() for i in range(kind.GetNumberOfFields())]


def register_shapes(debugger):
    """Formatters for the enums and optionals of the loaded programs.

    LLDB selects a formatter by type name, and an enum has the name its source gives it, so the
    types are found by their shape (`tag` and `payload`; `present` and `value`) in each module.
    """
    done = set()
    for target in debugger:
        for module in target.module_iter():
            for entry in module.GetTypes(lldb.eTypeClassStruct):
                name, shape = entry.GetName(), _shape(entry)
                if not name or name in done:
                    continue
                if shape == ["tag", "payload"]:
                    debugger.HandleCommand(
                        'type summary add "%s" -F %s.enum_summary' % (name, MODULE)
                    )
                    debugger.HandleCommand(
                        'type synthetic add "%s" -l %s.EnumChildren' % (name, MODULE)
                    )
                elif shape in (["present", "value"], ["present"]):
                    debugger.HandleCommand(
                        'type summary add "%s" -F %s.optional_summary' % (name, MODULE)
                    )
                    debugger.HandleCommand(
                        'type synthetic add "%s" -l %s.OptionalChildren' % (name, MODULE)
                    )
                else:
                    continue
                done.add(name)


class RefreshCommand:
    """`manuscript refresh`: register formatters after loading a program."""

    def __init__(self, debugger, _internal):
        self.debugger = debugger

    def __call__(self, debugger, _command, _context, result):
        register_shapes(debugger)
        result.AppendMessage("manuscript formatters registered")

    def get_short_help(self):
        return "Register Manuscript formatters for the enums and optionals of the loaded programs"


def __lldb_init_module(debugger, _internal):
    add = debugger.HandleCommand
    add('type summary add -x "^String\\??$" -F %s.string_summary' % MODULE)
    add('type summary add "Bytes" -F %s.bytes_summary' % MODULE)
    add('type summary add -x "^List\\[.*\\]$" -F %s.list_summary' % MODULE)
    add('type synthetic add -x "^List\\[.*\\]$" -l %s.ListChildren' % MODULE)
    add("command script add -c %s.RefreshCommand manuscript-refresh" % MODULE)
    register_shapes(debugger)
