# Musicc

Musicc is a lightweight, high-performance command-line music compiler, modular sound synthesizer, and DSP effects workstation written in V. It compiles structured text-based score sheets (`.mcc` files) into 16-bit 44.1kHz Stereo WAV audio. Musicc is designed for rapid sound design, physical modeling, multi-threaded track mixing, and sample-level DSP signal processing.

## Features

### 1. Custom Synthesizer & ADSR Engine (Multi-Voice Unison)
- **Advanced Multi-Voice Unison & Stereo Detuning**: Musicc can generate thick, wide analog chorus and supersaw textures by stacking up to $N$ unison oscillators.
    - *Constant-Power Stereo Widening*: Stacked oscillators are dynamically spread across the stereo field and detuned by a fractional offset ($1.0 \pm offset \times 0.006$) to construct a rich, non-coincidive stereo image.
- **Waveform Generators**: Includes Sine, Square, Sawtooth, Triangle, and a hardware-emulating White Noise generator.
    - *Hardware-Level Noise Emulation*: Noise is synthesized using an ultra-fast, inline Linear Congruential Generator (LCG) pseudo-random loop, bypassing standard heap-allocated random libraries to run at sample-rate speed.
- **Proportional ADSR Envelope Auto-Scaling**: Features a complete Attack, Decay, Sustain, and Release (ADSR) envelope module.
    - *Anti-Click Phase Scaling*: If a note's total duration ($D$) is shorter than the sum of its defined ADSR phases ($A + D_{decay} + R$), the engine mathematically compresses all phases proportionally ($scale = D / \sum_{ADR}$), guaranteeing a click-free execution of the volume curve under any high-tempo condition.
- **Low-Frequency Oscillator (LFO) & Frequency Modulation (FM)**: Custom synths can modulate their carrier phase with a secondary modulator oscillator (using adjustable FM ratios for glassy, metallic, or bell-like microtonal timbres) while a slow LFO modulates the global amplitude envelope.

### 2. Audio Shader DSP VM (Modular Zero-Allocation FX Pipeline)
- **Sample-Level Modular Effects Shading**: Similar to OpenGL fragment shaders processing individual pixels, Musicc passes generated audio samples through a custom, sample-by-sample DSP effects pipeline (`DEFINE_EFFECT`).
- **Zero-Allocation Audio VM**: Processing complex effects on $44,100$ samples per second across multiple tracks can trigger millions of heap allocations. By pre-populating registers and variable lookup slots (`vars_l`, `vars_r`) at parse-time, the shader virtual machine executes with a **Zero-Allocation** heap footprint inside the hot audio loop, accelerating compilation speeds.
- **Comprehensive Shader Instructions**:
    - `DELAY`: Stereo delay line with adjustable buffer sizes and feedback coefficients.
    - `MIX`: Linear summation of signals with weighted constant values.
    - `SATURATE`: Non-linear waveshaping distortion utilizing hyperbolic tangent (`tanh` tape saturation), cubic (`soft`), limiter (`hard`), or wavefolding (`fold`) curves.
    - `FILTER`: Dynamic, sweeping 1-pole Low-pass and High-pass filters.
    - `MODULATE`: Tremolo and Ring modulation.
    - `BITCRUSH`: Variable bit-depth quantizer for retro 8-bit lofi styling.
    - `PAN` / `AUTOPAN`: Static or LFO-driven constant-power stereo panning.

### 3. Resampling & Slicing Sampler (Multi-Sample Bank Engine)
- **Robust Audio File Decoding**: Supports mono/stereo, 8, 16, 24, and 32-bit IEEE float uncompressed PCM WAV files.
- **Linear Interpolation Resampling**: Shifts the playback pitch of samples using fractional index tracking combined with linear interpolation $(val_1 + frac \times (val_2 - val_1))$, preventing aliasing artifacts during high-ratio transposition.
- **Nearest-Semitone Multi-Sampling**: In multi-sampling mode, when a note is requested, the compiler searches the registered bank for the nearest defined semitone, calculates the distance, and automatically pitch-shifts the sample.
- **Millisecond-Precision Slicing**: Allows real-time sample cropping using the syntax `<start_ms>-<end_ms>`. Slicing is performed on the fly with zero memory copies by shifting the pointer's base offset.
- **One-Shot Auto-Duration**: Specifying a duration of `0` tells the engine to automatically calculate the sample's full duration (adjusted for its pitch ratio) and play it to the end without truncation.

### 4. Concurrency, Splicing & Master Bus Pipeline
- **Multi-Threaded Track Compilation**: Parallel tracks defined inside `PLAY_CONCURRENT` are compiled concurrently in separate OS threads using V's native `go` concurrency model.
- **Track Mixing Normalization**: Summed channels are mixed using the standard square-root headroom formula ($mixed = \sum track \times vol / \sqrt{N}$), protecting the dynamic range from digital clipping.
- **Track-Level & Master-Bus Inserts**: Effects can be loaded on individual track channels (allowing reverb/echo tails to ring out naturally over rests) or on the master output bus (`MASTER_EFFECT`).
- **Constant-Time $O(1)$ Splicing (Render Breakpoints)**: Slices and splices specific parts of the master float buffer using time ranges (`RENDER_RANGE 0.5-4.0`), allowing composers of fast, complex music (like Trashwave/Breakcore) to test and iterate specific segments.
- **Hard-Limiting Protection**: The master output stage applies a hard-limiter, clipping sample values at $[-32768, 32767]$ to prevent wrap-around integer overflow distortions.

---

## Quick Start (One-Liner)
```bash
pkg update -y && pkg install -y git clang make && if ! command -v v >/dev/null 2>&1; then git clone --depth=1 https://github.com/vlang/v && cd v && make && ./v symlink && cd ..; fi && git clone --depth=1 https://github.com/tailsmails/musicc && cd musicc && v -prod musicc.v -o musicc && ln -sf $(pwd)/musicc $PREFIX/bin/musicc
```

---

## Usage

### 1. Compiling .mcc Files
**Standard Compilation:**
```bash
musicc song.mcc output.wav
```

**Debug Mode (Verbose DSP Monitoring):**
```bash
musicc song.mcc output.wav --debug
```

### 2. MCC Language Syntax Example
Create a file named `melody.mcc` with the following modular script:
```text
DEBUG_MODE ON
MASTER_VOLUME 0.8
MASTER_EFFECT limiter

# 1. Custom Synthesizer with ADSR
DEFINE_SYNTH acid_bass sawtooth 5 0.1 0 0.15 10 120 0.5 150

# 2. Fragment Audio Shader
DEFINE_EFFECT space_echo
    DELAY d1 22050 0.5
    MIX y x 0.6 d1 0.4
    AUTOPAN y 1.5
    SATURATE y tanh
END

# 3. Track Channel with Insert Effects
DEFINE bass_line|space_echo
    LOOP 2
        C2 300 acid_bass
        Eb2 300 acid_bass
        REST 150
        F2 450 acid_bass
    END
END

# 4. Mix concurrently
PLAY_CONCURRENT bass_line:0.9
```

---

## DSP & Mixing Model
1. **Thread Isolation**: Spawning parallel tracks generates local copies of all shaders and delay line buffers (`clone_shaders`), completely preventing signal bleeding or memory race conditions between threads.
2. **Signal Flow**:
   $$\text{Synth/Sample Oscillator} \rightarrow \text{ADSR/LFO} \rightarrow \text{Track-level Insert Shaders} \rightarrow \text{Thread Mixing} \rightarrow \text{Master-bus Shaders} \rightarrow \text{Hard Limiter} \rightarrow \text{Stereo WAV}$$
3. **Memory Safety**: Memory-hard operations like real-time resamplers and delay lines utilize pre-allocated ring buffers to guarantee $O(1)$ sample-rate read/write times without GC overhead.

## License
![License](https://img.shields.io/badge/License-MIT-green.svg)
