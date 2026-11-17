(() => {
const color = /^#[0-9a-f]{6}$/i.test(window.MIU_BOOT_COLOR || '') ? window.MIU_BOOT_COLOR : '#48AAFF';
window.__DSH_STARTUP__ = {enabled:true,mode:'always',theme:'dark',glass:false,speed:1,requireInteraction:false,allowSkip:false,sound:false,voice:false,voiceLang:'en',voiceRate:.92,voiceLead:120,voiceSource:'tts',sfx:'synth',identity:'MIU',identityId:'MIU',brand1:'MIU AI',brand2:'DESKTOP INTELLIGENCE',brand3a:'MIU',brand3b:'AI',orgZh:'',orgEn:'Miu AI',orgSub:'YOUR DESKTOP COMPANION',welcomeBox:'MIU AI',footer:'POWERED BY MIU AI',accent:color,glitchA:color,glitchB:'#58CFFF'};
const send = message => { if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(message); };
document.addEventListener('DOMContentLoaded', () => send('started'));
window.addEventListener('dsh-startup:done', () => { send('handoff'); setTimeout(() => send('finished'), 1700); });
})();
