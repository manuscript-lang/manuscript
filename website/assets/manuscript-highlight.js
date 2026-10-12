// Apply the VS Code extension's shared lexical grammar to documentation fences.
// The adapter supports its match and quoted-string rules; no source is evaluated.
(() => {
  function tokenClass(scope) {
    if (scope.startsWith('comment.')) return 'c1';
    if (scope.startsWith('string.')) return 's';
    if (scope.startsWith('keyword.')) return 'k';
    if (scope.startsWith('constant.language.')) return 'kc';
    if (scope.startsWith('constant.numeric.')) return 'mi';
    if (scope.startsWith('entity.name.type.')) return 'nc';
    if (scope.startsWith('entity.name.function.')) return 'nf';
    return '';
  }

  function stringEnd(source, start) {
    const stack = [{ string: true }];
    let cursor = start + 1;
    while (cursor < source.length && stack.length) {
      const context = stack[stack.length - 1];
      const character = source[cursor++];
      if (context.string) {
        if (character === '\\') {
          if (source[cursor] === 'u' && source[cursor + 1] === '{') {
            const end = source.indexOf('}', cursor + 2);
            cursor = end < 0 ? source.length : end + 1;
          } else cursor = Math.min(cursor + 1, source.length);
        } else if (character === '"') stack.pop();
        else if (character === '{') stack.push({ depth: 1 });
      } else {
        if (character === '"') stack.push({ string: true });
        else if (character === '{') context.depth++;
        else if (character === '}' && --context.depth === 0) stack.pop();
      }
    }
    return cursor;
  }

  function tokenize(source, grammar) {
    const rules = grammar.patterns.map(rule => ({
      expression: new RegExp(rule.match || rule.begin, 'muy'),
      kind: tokenClass(rule.name),
      quoted: rule.begin === '"' && rule.end === '"'
    }));
    const tokens = [];
    let cursor = 0;
    const add = (text, kind = '') => {
      const previous = tokens[tokens.length - 1];
      if (previous?.kind === kind) previous.text += text;
      else tokens.push({ text, kind });
    };
    while (cursor < source.length) {
      let matched = false;
      for (const rule of rules) {
        rule.expression.lastIndex = cursor;
        const match = rule.expression.exec(source);
        if (!match || !match[0].length) continue;
        // TextMate word boundaries are Unicode-aware; JavaScript's \b is not.
        if (['k', 'kc', 'mi', 'nc', 'nf'].includes(rule.kind) &&
            (/[\p{ID_Continue}]/u.test(source[cursor - 1] || '') ||
             /[\p{ID_Continue}]/u.test(source[rule.expression.lastIndex] || ''))) continue;
        const end = rule.quoted ? stringEnd(source, cursor) : rule.expression.lastIndex;
        add(source.slice(cursor, end), rule.kind);
        cursor = end;
        matched = true;
        break;
      }
      if (!matched) add(source[cursor++]);
    }
    return tokens;
  }

  if (typeof document !== 'undefined') {
    document.querySelectorAll('.docs-code[data-language="manuscript"] pre code, .docs-code[data-language="ms"] pre code').forEach(code => {
      const fragment = document.createDocumentFragment();
      tokenize(code.textContent, manuscriptGrammar).forEach(({ text, kind }) => {
        if (!kind) fragment.append(document.createTextNode(text));
        else {
          const span = document.createElement('span');
          span.className = kind;
          span.textContent = text;
          fragment.append(span);
        }
      });
      code.classList.add('chroma');
      code.replaceChildren(fragment);
    });
  }
  if (typeof module !== 'undefined') module.exports = { tokenize };
})();
