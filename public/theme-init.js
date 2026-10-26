try {
  const saved = localStorage.getItem('ritm.theme.v1');
  const theme = ['light', 'dark', 'system'].includes(saved) ? saved : 'light';
  document.documentElement.dataset.theme =
    theme === 'dark' || (theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches)
      ? 'dark'
      : 'light';
} catch {
  document.documentElement.dataset.theme = 'light';
}
