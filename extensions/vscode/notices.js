const fs = require('node:fs');
const path = require('node:path');

// esbuild's input graph, rather than every installed dev dependency, defines the bundle.
function thirdPartyNotices(root, inputs) {
  const packages = new Set();
  for (const input of inputs) {
    const parts = input.split(/[\\/]/);
    const start = parts.lastIndexOf('node_modules');
    if (start < 0) continue;
    const count = parts[start + 1].startsWith('@') ? 2 : 1;
    packages.add(parts.slice(0, start + 1 + count).join('/'));
  }
  const sections = ['Third-party notices for the bundled Manuscript VS Code extension.\nGenerated from the build input graph. Do not edit.\n'];
  for (const relative of [...packages].sort()) {
    const directory = path.resolve(root, relative);
    const metadata = JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
    const files = fs.readdirSync(directory, { withFileTypes: true })
      .filter(file => file.isFile() && /^(licen[sc]es?|copying|notices?|copyright(?:notices?)?|authors|patents|third[-_ ]?party[-_ ]?(?:notices?|licen[sc]es?))(?:[._-]|$)/i.test(file.name))
      .map(file => file.name).sort();
    if (!files.length) throw new Error(`No third-party notice files for ${relative}`);
    sections.push(`Package: ${metadata.name}@${metadata.version}\nDeclared license: ${metadata.license || 'not specified'}\n`);
    for (const name of files) {
      const text = fs.readFileSync(path.join(directory, name), 'utf8');
      if (!text.trim()) throw new Error(`Empty third-party notice: ${relative}/${name}`);
      sections.push(`--- ${relative}/${name} ---\n${text}`);
    }
  }
  return sections.join('\n') + '\n';
}

module.exports = { thirdPartyNotices };
