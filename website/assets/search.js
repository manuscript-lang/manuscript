'use strict';
{{ $data := resources.Get "search-data.json" | resources.ExecuteAsTemplate "en.search-data.json" . | resources.Minify | resources.Fingerprint }}
(() => {
  const input = document.getElementById('book-search-input');
  const results = document.getElementById('book-search-results');
  if (!input || !results) return;
  input.placeholder = 'Search docs…';
  input.setAttribute('aria-label', 'Search documentation');
  results.setAttribute('aria-live', 'polite');
  let index;
  let loading;
  const message = text => {
    results.replaceChildren();
    const item = document.createElement('li');
    item.className = 'search-message';
    item.textContent = text;
    results.append(item);
  };
  async function search() {
    if (!input.value.trim()) { results.replaceChildren(); return; }
    if (!index) {
      message('Loading search…');
      try { await init(); } catch (_) { message('Search is unavailable. Try again.'); return; }
    }
    if (!input.value.trim()) { results.replaceChildren(); return; }
    results.replaceChildren();
    const hits = index.search(input.value.trim()).slice(0, 10);
    if (!hits.length) { message('No results. Try another term.'); return; }
    hits.forEach(({ item }) => {
      const li = document.createElement('li');
      const link = document.createElement('a');
      const section = document.createElement('small');
      link.href = item.href;
      link.textContent = item.title;
      section.textContent = item.section;
      li.append(link, section);
      results.append(li);
    });
  }
  function init() {
    if (index) return Promise.resolve();
    if (loading) return loading;
    input.required = true;
    loading = fetch('{{ partial "docs/links/resource-precache" $data }}')
      .then(response => { if (!response.ok) throw new Error('Search unavailable'); return response.json(); })
      .then(pages => { index = new Fuse(pages, { threshold: .25, ignoreLocation: true, keys: [{ name: 'title', weight: .7 }, { name: 'content', weight: .3 }] }); })
      .finally(() => { input.required = false; loading = undefined; });
    return loading;
  }
  input.addEventListener('focus', () => { init().catch(() => {}); });
  input.addEventListener('input', search);
  document.addEventListener('keydown', event => {
    const editing = event.target.closest('input, textarea, select, [contenteditable="true"]');
    if (editing) return;
    if ((event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey) || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k')) {
      event.preventDefault();
      const menu = document.getElementById('menu-control');
      if (window.matchMedia('(max-width: 62rem)').matches && menu) { menu.checked = true; menu.dispatchEvent(new Event('change')); }
      input.focus();
    }
  });
})();
