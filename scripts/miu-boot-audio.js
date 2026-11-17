// Generate the original, local PCM music and cue used by MiuBoot.
const fs = require('fs');
const path = require('path');
const output = path.resolve(__dirname, '../res/miu/boot-player/web');
const sampleRate = 22050;

function writeWave(name, seconds, sample) {
  const count = Math.floor(seconds * sampleRate);
  const data = Buffer.alloc(44 + count * 2);
  data.write('RIFF', 0); data.writeUInt32LE(36 + count * 2, 4);
  data.write('WAVEfmt ', 8); data.writeUInt32LE(16, 16);
  data.writeUInt16LE(1, 20); data.writeUInt16LE(1, 22);
  data.writeUInt32LE(sampleRate, 24); data.writeUInt32LE(sampleRate * 2, 28);
  data.writeUInt16LE(2, 32); data.writeUInt16LE(16, 34);
  data.write('data', 36); data.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) {
    const value = Math.max(-1, Math.min(1, sample(i / sampleRate)));
    data.writeInt16LE(Math.round(value * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(output, name), data);
}

const chords = [[110, 164.81, 220], [130.81, 164.81, 196],
  [98, 146.83, 196], [110, 164.81, 220]];
writeWave('music.wav', 32, t => {
  const chord = chords[Math.floor(t / 8) % chords.length];
  const swell = .6 + .4 * Math.sin(Math.PI * (t % 8) / 8);
  const fade = Math.min(1, t / 1.8, (32 - t) / 2);
  const pad = chord.reduce((sum, f) => sum + Math.sin(2 * Math.PI * f * t) * .034, 0);
  const bellTime = t % .8;
  const f = chord[Math.floor(t / .8) % chord.length] * 2;
  const bell = Math.sin(2 * Math.PI * f * t) * Math.exp(-bellTime * 5) * .045;
  return (pad * swell + bell) * Math.max(0, fade);
});
writeWave('cue.wav', .5, t => {
  const envelope = Math.exp(-t * 8) * Math.min(1, t * 80);
  return envelope * (.25 * Math.sin(2 * Math.PI * 880 * t) +
    .12 * Math.sin(2 * Math.PI * 1320 * t));
});
