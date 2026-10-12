(() => {
  const versions = document.querySelector('.docs-versions');
  document.addEventListener('click', event => {
    if (versions?.open && !versions.contains(event.target)) versions.open = false;
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && versions?.open) {
      versions.open = false;
      versions.querySelector('summary').focus();
    }
  });

  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-toggle');
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
  try {
    const saved = localStorage.getItem('manuscript-theme');
    if (saved === 'light' || saved === 'dark') root.dataset.theme = saved;
  } catch (_) { /* Storage is optional. */ }
  if (themeButton) {
    themeButton.hidden = false;
    const updateLabel = () => {
      const dark = root.dataset.theme ? root.dataset.theme === 'dark' : systemTheme.matches;
      themeButton.setAttribute('aria-label', `Switch to ${dark ? 'light' : 'dark'} theme`);
    };
    updateLabel();
    systemTheme.addEventListener('change', updateLabel);
    themeButton.addEventListener('click', () => {
      const dark = root.dataset.theme ? root.dataset.theme === 'dark' : systemTheme.matches;
      root.dataset.theme = dark ? 'light' : 'dark';
      try { localStorage.setItem('manuscript-theme', root.dataset.theme); } catch (_) {}
      updateLabel();
    });
  }

  document.querySelectorAll('.docs-code').forEach(block => {
    if (!navigator.clipboard) return;
    const code = block.querySelector('pre code');
    const heading = block.querySelector('.docs-code-heading');
    if (!code || !heading) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy-code';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy code');
    button.setAttribute('aria-live', 'polite');
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = 'Copied!';
      } catch (_) {
        button.textContent = 'Select to copy';
      }
      setTimeout(() => { button.textContent = 'Copy'; }, 2000);
    });
    heading.append(button);
  });

  // Keep the theme's CSS-only drawers usable with the keyboard, too.
  document.querySelectorAll('.book-header label[for]').forEach(label => {
    const control = document.getElementById(label.htmlFor);
    if (!control || !label.querySelector('img')) return;
    label.tabIndex = 0;
    label.setAttribute('role', 'button');
    label.setAttribute('aria-label', label.querySelector('img').alt);
    const update = () => label.setAttribute('aria-expanded', String(control.checked));
    update();
    control.addEventListener('change', update);
    label.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        control.checked = !control.checked;
        update();
      }
    });
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      ['menu-control', 'toc-control'].forEach(id => {
        const control = document.getElementById(id);
        if (control?.checked) {
          control.checked = false;
          control.dispatchEvent(new Event('change'));
        }
      });
    }
  });

  const tocLinks = [...document.querySelectorAll('.book-toc #TableOfContents a')];
  if ('IntersectionObserver' in window && tocLinks.length) {
    const observer = new IntersectionObserver(entries => {
      const visible = entries.filter(entry => entry.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (!visible.length) return;
      tocLinks.forEach(link => {
        const active = decodeURIComponent(link.hash.slice(1)) === visible[0].target.id;
        link.classList.toggle('active', active);
        if (active) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }, { rootMargin: '-100px 0px -60% 0px' });
    tocLinks.forEach(link => {
      const heading = document.getElementById(decodeURIComponent(link.hash.slice(1)));
      if (heading) observer.observe(heading);
    });
  }
})();
