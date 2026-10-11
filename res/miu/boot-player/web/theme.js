/* Native player receives a validated color from B; no network access. */
(() => {
  const presets = [...document.querySelectorAll('[data-color]')];
  const picker = document.getElementById('themeColor');
  const surfaces = ['boot', 'ready', 'lightSweep', 'edgeGlow'].map(id => document.getElementById(id));

  function apply(color) {
    if (!/^#[0-9a-f]{6}$/i.test(color)) color = '#48AAFF';
    color = color.toUpperCase();
    const [r, g, b] = [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16) / 255);
    const high = Math.max(r, g, b), low = Math.min(r, g, b), delta = high - low;
    const lightness = (high + low) / 2;
    let hue = 0;
    if (delta) {
      hue = high === r ? ((g - b) / delta) % 6 : high === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
      hue = (hue * 60 + 360) % 360;
    }
    const saturation = delta ? delta / (1 - Math.abs(2 * lightness - 1)) : 0;
    // Tint only animation layers; neutral highlights and the mock wallpaper stay readable.
    const filter = color === '#48AAFF' ? 'none'
      : color === '#FF0000' ? 'url(#bootRedTint)'
      : `hue-rotate(${hue - 207.87}deg) saturate(${saturation}) brightness(${.7 + .3 * Math.min(1, lightness * 2)})`;
    for (const surface of surfaces) surface.style.filter = filter;
    let name = '自定义';
    for (const button of presets) {
      const selected = button.dataset.color === color;
      button.setAttribute('aria-pressed', String(selected));
      if (selected) name = button.dataset.name;
    }
    picker.value = color;
    document.getElementById('themeName').textContent = name;
    document.getElementById('themeHex').textContent = color;
  }

  for (const button of presets) button.addEventListener('click', () => apply(button.dataset.color));
  picker.addEventListener('input', () => apply(picker.value));
  apply(window.MIU_BOOT_COLOR || '#48AAFF');
})();
