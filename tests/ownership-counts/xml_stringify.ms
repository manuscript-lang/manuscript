// expect-debug: allocs=24 alloc_bytes=82379
// expect-release: allocs=24 alloc_bytes=82401
// Compact output skips the text-classification copy; mixed content stops inspecting
// later siblings.
import XmlNode, stringify from "@std/data/xml.ms"

export fn main() Int:
	text := "x".repeat(4096).get()
	root := XmlNode.XmlElement("root", [], [XmlNode.XmlText(text.clone())])
	if stringify(root) != "<root>{text}</root>": return 1

	mixed := XmlNode.XmlElement("root", [], [XmlNode.XmlText("text"), root])
	if stringify(mixed, "  ") != "<root>text<root>{text}</root></root>\n": return 2

	return 0
