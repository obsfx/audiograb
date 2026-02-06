# audiograb

A macOS command-line tool that records system audio to a WAV file. Built on Apple's Core Audio Taps API. No external dependencies.

Designed to run standalone or as a child process spawned by other applications.

Requires macOS 14.2 or later.

## Install

### Prebuilt binary

Download the latest build from the [releases page](https://github.com/obsfx/audiograb/releases/tag/latest).

```
tar -xzf audiograb-macos-arm64.tar.gz
./audiograb --version
```

### Build from source

```
git clone https://github.com/obsfx/audiograb.git
cd audiograb
swift build -c release
```

The binary is at `.build/release/audiograb`.

## Usage

```
audiograb --output <path> [options]
```

### Options

```
-o, --output <path>       Output WAV file path (required)
-d, --duration <seconds>  Recording duration in seconds (0 = until stopped, default: 0)
-r, --sample-rate <rate>  Sample rate: 16000, 44100, 48000 (default: 48000)
-c, --channels <count>    Channels: 1 or 2 (default: 2)
-s, --source <mode>       Audio source: system, mic (default: system)
    --mute                Mute system audio during capture (system source only)
    --json-stdout         Output newline-delimited JSON to stdout
-v, --verbose             Verbose logging to stderr
-h, --help                Show help
    --version             Show version
```

### Examples

Record 10 seconds of system audio.

```
audiograb -o recording.wav -d 10
```

Record until you press Ctrl+C.

```
audiograb -o recording.wav
```

Record mono audio. The tool captures stereo from the system tap and downmixes to a single channel.

```
audiograb -o recording.wav -d 10 -c 1
```

Record with system speakers muted. The WAV file still contains audio.

```
audiograb -o recording.wav -d 10 --mute
```

Record from the default microphone instead of system audio.

```
audiograb -o recording.wav -d 10 --source mic
```

## JSON output

Use `--json-stdout` when spawning as a child process. All output goes to stdout as newline-delimited JSON. Each line has a `type` field.

A started event fires once when the capture begins.

```json
{"type":"started","timestamp":1706184000.0}
```

Log events carry the log level and message.

```json
{"type":"log","level":"info","message":"Capture session started"}
```

Duration events fire every second with the elapsed time.

```json
{"type":"duration","elapsed":5,"formatted":"00:05"}
```

A result event fires on completion with the output path and total duration.

```json
{"type":"result","path":"/tmp/recording.wav","duration":10.0}
```

## Permissions

**System audio** (`--source system`, the default) uses Apple's Core Audio Taps API, which requires the System Audio Recording permission. On the first run, macOS may prompt you to grant this permission. Some terminal emulators like iTerm and VS Code do not trigger the prompt automatically. If you get silence, open System Settings, go to Privacy and Security, then Screen and System Audio Recording, and scroll down to the System Audio Recording Only section. Add your terminal application there.

**Microphone** (`--source mic`) uses the default input device and requires the Microphone permission. macOS will prompt on first use. You can manage this in System Settings under Privacy and Security, then Microphone.

If the tool runs but the WAV file contains silence, a missing permission is the most likely cause.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Permission denied |
| 2 | Device or audio error |
| 3 | File I/O error |
| 4 | Invalid arguments |
| 5 | Unexpected error |

## How it works

The tool creates a Core Audio process tap that captures all system audio output. It attaches this tap to a private aggregate device and registers an IOProc callback on the device. The callback runs on a real-time audio thread and writes raw Float32 PCM data into a lock-free ring buffer.

A background writer thread drains the ring buffer every 10ms, converts Float32 samples to 16-bit PCM integers, and appends them to the WAV file. When recording stops, the tool seeks back to the WAV header and writes the correct file size.

The tool outputs at the tap's native sample rate, which is typically 48kHz. If you request a different sample rate, it logs the actual rate being used.

## Code signing

For local use, the binary works without code signing. If you distribute it or bundle it with another application, sign it with entitlements.

```
codesign --sign "Developer ID Application: Your Name" \
  --entitlements entitlements.plist \
  --options runtime \
  .build/release/audiograb
```

The included `entitlements.plist` declares `com.apple.security.device.audio-input`.

## License

MIT. See [LICENSE](LICENSE) for details.
