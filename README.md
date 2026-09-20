# parrot

A minimal macOS dictation daemon. Push-to-talk or double-tap toggle, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://digimata.github.io/parrot/install.sh | sh
parrot setup                       # grants mic + accessibility, asks model/language, downloads
parrot install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/parrot`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## How to use

1. **Run it.** Either `parrot install --launch-at-login` (daemonized, runs forever, lives in the menu bar), or `parrot` in any terminal tab.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **The transcript types itself in at the cursor** when you release. Usually within 200-300ms.

That's it. There is no record button, no stop button, no "send" — `fn` is the whole interface.

### Toggle mode

If you'd rather not hold `fn` the whole time, start with `parrot --toggle`:

1. **Double-tap `fn`** to turn recording **ON**. Speak freely.
2. **Tap `fn` once** to turn it **OFF**. The transcript types itself in at the cursor.

A single tap while idle does nothing — that way accidental `fn` presses don't start the mic. The double-tap window follows your macOS double-click speed (System Settings → Desktop & Dock → Double-click speed).

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `parrot setup` will tell you how to flip it back to plain `fn`.

## CLI

```sh
parrot                                 # run in the foreground (^C to quit)
parrot setup                           # first run: permissions + model/language + download
parrot install --launch-at-login       # register a LaunchAgent (background daemon)
parrot install --launch-at-login --toggle  # same, with double-tap toggle mode
parrot install --uninstall             # remove the LaunchAgent
parrot doctor                          # check permissions + fn key setting
parrot models list                     # list available models
parrot models download <id>            # pre-download a model
parrot config                          # show model + language
parrot config set model whisper-large-v3-turbo
parrot config set language es
parrot config get language
parrot --model whisper-large-v3-turbo  # one-shot override (does not write config)
parrot --language es                   # one-shot override
parrot --toggle                        # double-tap fn to start, tap once to stop
parrot --hotkey right-option           # change the push-to-talk key
parrot --no-overlay                    # disable the bottom-of-screen pill
```

Config lives at `~/.config/parrot/config.toml`. Flags override the file; the file overrides the built-in defaults (`whisper-base.en`, `en`). English-only models (`whisper-base.en`, `whisper-small.en`) cannot be paired with a non-English language — `parrot config set language es` will switch you to `whisper-large-v3-turbo`.

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/parrot --help
```
