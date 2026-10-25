// Apply the VS Code extension's shared lexical grammar to documentation fences.
// Interpret its match, capture, begin/end, and local include rules; no source is evaluated.
(() => {
  function tokenClass(scope) {
    if (scope.startsWith('comment.')) return 'c1';
    if (scope.startsWith('string.')) return 's';
    if (scope.startsWith('keyword.operator.')) return 'o';
    if (scope.startsWith('keyword.')) return 'k';
    if (scope.startsWith('constant.character.escape.')) return 'se';
    if (scope.startsWith('constant.language.')) return 'kc';
    if (scope.startsWith('constant.numeric.')) return 'mi';
    if (scope.startsWith('entity.name.type.')) return 'nc';
    if (scope.startsWith('entity.name.function.')) return 'nf';
    if (scope.startsWith('punctuation.section.interpolation.')) return 'si';
    if (scope.startsWith('punctuation.')) return 'p';
    return '';
  }

  function tokenize(source, grammar) {
    const cache = new Map();
    const captures = scopes => Object.entries(scopes || {}).map(([group, { name }]) => [Number(group), tokenClass(name)]);
    function patterns(rules) {
      return rules.flatMap(rule => rule.include === '$self' ? patterns(grammar.patterns) :
        compile(rule.include ? grammar.repository[rule.include.slice(1)] : rule));
    }
    function compile(rule) {
      if (cache.has(rule)) return cache.get(rule);
      const compiled = {};
      cache.set(rule, compiled); // Interpolation includes the root grammar recursively.
      Object.assign(compiled, {
        expression: new RegExp(rule.match || rule.begin, 'muyd'),
        end: rule.end && new RegExp(rule.end, 'muyd'),
        kind: rule.name === undefined ? undefined : tokenClass(rule.name),
        captures: captures(rule.captures || rule.beginCaptures),
        endCaptures: captures(rule.endCaptures),
        patterns: patterns(rule.patterns || [])
      });
      return compiled;
    }
    const stack = [{ patterns: patterns(grammar.patterns), kind: '' }];
    const tokens = [];
    let cursor = 0;
    const add = (text, kind = '') => {
      if (!text) return;
      const previous = tokens[tokens.length - 1];
      if (previous?.kind === kind) previous.text += text;
      else tokens.push({ text, kind });
    };
    const matchAt = expression => {
      if (!expression) return null;
      expression.lastIndex = cursor;
      const match = expression.exec(source);
      return match?.[0].length ? match : null;
    };
    const emit = (match, kind, captures) => {
      let at = cursor;
      for (const [group, capturedKind] of captures) {
        if (!match.indices[group]) continue;
        const [from, to] = match.indices[group];
        add(source.slice(at, from), kind);
        add(source.slice(from, to), capturedKind);
        at = to;
      }
      cursor += match[0].length;
      add(source.slice(at, cursor), kind);
    };
    while (cursor < source.length) {
      const context = stack[stack.length - 1];
      const end = matchAt(context.end);
      if (end) {
        emit(end, context.kind, context.endCaptures);
        stack.pop();
        continue;
      }
      let matched = false;
      for (const rule of context.patterns) {
        const match = matchAt(rule.expression);
        if (!match) continue;
        // TextMate word boundaries are Unicode-aware; JavaScript's \b is not.
        if (['k', 'kc', 'mi', 'nc', 'nf'].includes(rule.kind) &&
            (/[\p{ID_Continue}]/u.test(source[cursor - 1] || '') ||
             /[\p{ID_Continue}]/u.test(source[rule.expression.lastIndex] || ''))) continue;
        const kind = rule.kind ?? context.kind;
        emit(match, kind, rule.captures);
        if (rule.end) stack.push({ ...rule, kind });
        matched = true;
        break;
      }
      if (!matched) add(source[cursor++], context.kind);
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
