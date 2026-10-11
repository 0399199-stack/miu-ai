(() => {
  const play = document.getElementById('play');
  const ready = new MutationObserver(() => {
    if (!play.disabled) {
      ready.disconnect();
      play.click();
    }
  });
  new MutationObserver(() => {
    const state = document.body.dataset.state;
    if (state === 'playing') window.chrome.webview.postMessage('started');
    if (state === 'finished') window.chrome.webview.postMessage('finished');
  }).observe(document.body, { attributes: true, attributeFilter: ['data-state'] });
  if (play.disabled) ready.observe(play, { attributes: true, attributeFilter: ['disabled'] });
  else play.click();
})();
