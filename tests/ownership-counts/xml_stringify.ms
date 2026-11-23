// expect-debug: allocs=26 alloc_bytes=82480
// expect-release: allocs=26 alloc_bytes=82480
// Compact output skips the text-classification copy; mixed content stops inspecting
// later siblings.
import XmlNode, stringify from "@std/data/xml.ms"

export fn main() Int:
	text := "x".repeat(4096)
	root := XmlNode.XmlElement("root", [], [XmlNode.XmlText(text.clone())])
	if stringify(root) != f"<root>{text}</root>": return 1

	mixed := XmlNode.XmlElement("root", [], [XmlNode.XmlText("text"), root])
	if stringify(mixed, "  ") != f"<root>text<root>{text}</root></root>\n": return 2

	return 0
