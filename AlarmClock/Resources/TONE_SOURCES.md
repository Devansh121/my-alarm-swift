# Bundled Tone Sources

All eight bundled alarm tones are sourced from providers whose licenses permit
redistribution inside a shipped app with **no attribution requirement**
(public domain / CC0, or the Mixkit Free License). Each source file was
loudness-normalized (EBU R128, target -16 LUFS), converted to mono 44.1 kHz,
and encoded as CAF (LEI16). Short clips were seamlessly looped and given a
short trailing fade so every tone runs ~20-28 s (iOS caps notification sounds
at 30 s).

| File | Display Name | Character | Source | License | Duration |
|------|--------------|-----------|--------|---------|----------|
| `tone_radial.caf` | Classic Bell | Classic alarm-clock bell ring | Mixkit SFX #998 — https://assets.mixkit.co/active_storage/sfx/998/998-preview.mp3 | Mixkit Free License (no attribution required) | 25.0 s |
| `tone_ascent.caf` | Rise & Shine | Energetic melodic ringtone | Mixkit SFX #1359 — https://assets.mixkit.co/active_storage/sfx/1359/1359-preview.mp3 | Mixkit Free License (no attribution required) | 25.9 s |
| `tone_pulse.caf` | Digital Pulse | Urgent digital beep pattern | Mixkit SFX #988 — https://assets.mixkit.co/active_storage/sfx/988/988-preview.mp3 | Mixkit Free License (no attribution required) | 23.9 s (looped) |
| `tone_chimes.caf` | Gentle Chimes | Gentle chime/bell melody | Mixkit SFX #1360 — https://assets.mixkit.co/active_storage/sfx/1360/1360-preview.mp3 | Mixkit Free License (no attribution required) | 25.0 s |
| `tone_cosmic.caf` | Cosmic Drift | Airy ambient ringtone (author's choice) | Mixkit SFX #1361 — https://assets.mixkit.co/active_storage/sfx/1361/1361-preview.mp3 | Mixkit Free License (no attribution required) | 23.9 s (looped) |
| `tone_beacon.caf` | Marimba | Marimba/mallet melodic riff | Mixkit SFX #1354 — https://assets.mixkit.co/active_storage/sfx/1354/1354-preview.mp3 | Mixkit Free License (no attribution required) | 23.0 s (looped) |
| `tone_signal.caf` | Music Box | Soft music-box melody | Mixkit SFX #2985 — https://assets.mixkit.co/active_storage/sfx/2985/2985-preview.mp3 | Mixkit Free License (no attribution required) | 19.9 s (looped) |
| `tone_waves.caf` | Morning Birds | Morning birdsong / nature | Wikimedia Commons — "Birdsong mild sunny day" by Stephan — https://upload.wikimedia.org/wikipedia/commons/7/75/Birdsong_mild_sunny_day.ogg | Public Domain (released by the author) | 28.0 s (trimmed from 37 s) |

## License references

- **Mixkit Free License** — https://mixkit.co/license/ — Sound effects are
  free to use in commercial and non-commercial projects, including apps, with
  no attribution required. Redistribution as part of a larger work (the app) is
  permitted; reselling the sound files standalone is not (not applicable here).
- **Public Domain (Wikimedia Commons)** — the birdsong recording was released
  into the public domain by its author, imposing no usage or attribution
  restrictions.

## Reproducing / replacing a tone

1. Download the source (see URL above).
2. Normalize + loop/trim + downmix, e.g.:
   `ffmpeg -stream_loop N -i SRC -t SECONDS -af "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=..." -ar 44100 -ac 1 -c:a pcm_s16le out.wav`
3. Encode to CAF: `afconvert -f caff -d LEI16 out.wav tone_NAME.caf`
4. Keep the existing filename — ids and fileNames are load-bearing for
   persistence and tests; only `displayName` in `Alarm.swift` may change.
