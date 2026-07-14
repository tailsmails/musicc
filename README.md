# Musicc

Musicc is a lightweight, high-performance command-line music compiler, modular
sound synthesizer, and DSP effects workstation written in V. It compiles
structured text-based score sheets (.mcc files) into studio-grade 16-bit 44.1kHz
Stereo WAV audio. Musicc is designed for rapid sound design, physical modeling,
multi-threaded track mixing, and sample-level DSP signal processing.

---

## Features

### 1. Custom Synthesizer & ADSR Engine (Multi-Voice Unison)

  - **Advanced Multi-Voice Unison & Stereo Detuning:** Musicc can generate thick,
    wide analog chorus and supersaw textures by stacking up to N unison
    oscillators.
      - *Constant-Power Stereo Widening:* Stacked oscillators are dynamically
        spread across the stereo field and detuned by a fractional offset
        $(1.0 \pm \text{offset} \times 0.006)$ to construct a rich, non-coincidive stereo
        image.
  - **Waveform Generators with PolyBLEP Anti-Aliasing:** Includes Sine, Triangle,
    and PolyBLEP-corrected Square and Sawtooth generators, alongside a
    hardware-emulating White Noise generator.
      - *Aliasing Suppression:* By employing Polynomial Band-Limited Step
        (PolyBLEP) phase-correction, the engine mitigates high-frequency digital
        aliasing artifacts, yielding a warmer, analog-like timbre.
      - *Hardware-Level Noise Emulation:* Noise is synthesized using an
        ultra-fast, inline Linear Congruential Generator (LCG) pseudo-random
        loop, bypassing standard heap-allocated random libraries to run at
        sample-rate speed.
  - **Proportional ADSR Envelope Auto-Scaling:** Features a complete Attack, Decay,
    Sustain, and Release (ADSR) envelope module.
      - *Anti-Click Phase Scaling:* If a note's total duration ($D$) is shorter than
        the sum of its defined ADSR phases $(A + D_{\text{decay}} + R)$, the engine
        mathematically compresses all phases proportionally
        $(\text{scale} = D / \sum \text{ADR})$, helping prevent click or pop artifacts of the
        volume curve under high-tempo conditions.
  - **Low-Frequency Oscillator (LFO) & Frequency Modulation (FM):** Custom synths
    can modulate their carrier phase with a secondary modulator oscillator
    (using adjustable FM ratios for glassy, metallic, or bell-like microtonal
    timbres) while a slow LFO modulates the global amplitude envelope.

### 2. Audio Shader DSP VM (Modular Zero-Allocation FX Pipeline)

  - **Sample-Level Modular Effects Shading:** Similar to OpenGL fragment shaders
    processing individual pixels, Musicc passes generated audio samples through
    a custom, sample-by-sample DSP effects pipeline (DEFINE_EFFECT).
  - **Zero-Allocation Audio VM:** Processing complex effects on 44,100 samples per
    second across multiple tracks can trigger millions of heap allocations. By
    pre-populating registers and variable lookup slots (vars_l, vars_r) at
    parse-time, the shader virtual machine executes with a Zero-Allocation heap
    footprint inside the hot audio loop, accelerating compilation speeds.
  - **Comprehensive Shader Instructions:**
      - `delay`: Stereo delay line with adjustable buffer sizes and feedback
        coefficients.
      - `reverse`: Real-time, double-buffered block-reversing processor. It slices
        incoming audio into rhythmic blocks of variable size (e.g., 250ms) and
        plays each segment backwards. Features integrated edge-windowing
        envelopes (~8ms linear fades) to suppress transient click and pop noises
        at block boundaries.
      - `vibrato`: Organic pitch modulation utilizing a micro-delay line modulated
        by a sweeping low-frequency oscillator.
      - `drift`: Subtle, chaotic low-frequency amplitude fluctuations based on
        deterministic LCG noise, simulating tape flutter and physical acoustic instability.
      - `mix`: Linear summation of signals with weighted constant values.
      - `saturate`: Non-linear waveshaping distortion utilizing hyperbolic tangent
        (tanh tape saturation), cubic (soft), limiter (hard), or wavefolding
        (fold) curves.
      - `filter`: Dynamic, sweeping 1-pole Low-pass and High-pass smoothing
        filters. Coefficients are automatically clamped within a stable
        `[0.001, 0.999]` range to ensure mathematical stability under extreme
        modulation or LFO sweeps.
      - `compressor`: Studio-grade feed-forward dynamic range compressor with
        DB-domain envelope detection, variable threshold, ratio, attack,
        release, and makeup gain.
      - `svf`: 2-pole resonant State Variable Filter offering Low-pass, High-pass,
        Band-pass, and Notch responses with adjustable Q-resonance factor.
      - `reverb`: High-density Schroeder reverberator utilizing 4 parallel
        feedback comb filters with high-frequency absorption (Damp),
        stereophonic delay-spread, and wet/dry blend controls.
      - `chorus`: Stereo pitch-chorus using fractional delay lines modulated by a
        slow LFO.
      - `exciter`: High-frequency harmonic exciter that isolates high-frequency
        bands, saturates them to generate fresh harmonics, and mixes them back
        to add "air" and presence.
      - `wavefolder`: West-coast wavefolder which reflects signal peaks exceeding
        clipping thresholds back inward to generate complex analog overtones.
      - `vowel`: Organic vocal formant filter utilizing 3 parallel bandpass SVF
        resonators tuned to human vowel frequencies ('a', 'e', 'i', 'o', 'u').
      - `phaser`: 4-stage cascaded modulated allpass filter sweep network with a
        feedback path and sweeping LFO.
      - `ms_width`: Mid-Side matrix processor allowing detailed width adjustment
        of the stereophonic field.
      - `modulate`: Tremolo and Ring modulation.
      - `bitcrush`: Variable bit-depth quantizer for retro 8-bit lofi styling.
      - `pan` / `autopan`: Static or LFO-driven constant-power stereo panning.

### 3. Resampling & Slicing Sampler (Multi-Sample Bank Engine)

  - **Robust Audio File Decoding:** Supports mono/stereo, 8, 16, 24, and 32-bit IEEE
    float uncompressed PCM WAV files.
  - **Linear Interpolation Resampling:** Shifts the playback pitch of samples using
    fractional index tracking combined with linear interpolation
    $(val_1 + \text{frac} \times (val_2 - val_1))$, preventing aliasing artifacts during
    high-ratio transposition.
  - **Nearest-Semitone Multi-Sampling:** In multi-sampling mode, when a note is
    requested, the compiler searches the registered bank for the nearest defined
    semitone, calculates the distance, and automatically pitch-shifts the
    sample.
  - **Millisecond-Precision Slicing:** Allows real-time sample cropping using the
    syntax `<start_ms>-<end_ms>`. Slicing is performed on the fly with zero memory
    copies by shifting the pointer's base offset.
  - **One-Shot Auto-Duration:** Specifying a duration of 0 tells the engine to
    automatically calculate the sample's full duration (adjusted for its pitch
    ratio) and play it to the end without truncation.

### 4. Deterministic Engine & Seed Control

  - **Reproducible LCG Pseudo-Randomization:** To ensure compiles are mathematically
    identical across any runtime, operating system, or machine, the entire
    synthesis, noise-generation, and humanization engine bypasses runtime-entropy
    system calls. Instead, it utilizes a custom, deterministic Linear Congruential
    Generator (LCG).
  - **User-Defined Music Seed (`SEED <value>`):** Composers can specify a starting
    seed at the top of their score sheets (e.g., `SEED 950302`). If omitted, the
    compiler falls back to a default seed (`123456789`).

### 5. Granular & Optional Humanization Engine

  - **Dynamic Inline Toggling (`HUMANIZE ON/OFF`):** Humanization is completely
    optional and disabled by default. Composers can explicitly toggle humanization
    on a track-by-track, section-by-section, or even note-by-note basis within
    their timelines.
  - **Micro-Timing & Velocity Jitter:** When humanization is toggled `ON`, the LCG
    pseudo-randomly shifts note start times/durations (by a subtle +/- 4ms margin)
    and adjusts velocities (by a +/- 5% margin) to approximate organic performance
    deviations.
  - **Deterministic Round-Robin Sample Cycling:** When a multi-sampled instrument is
    played with humanization active, the engine cycles through multiple registered
    WAV takes mapped to the requested note, helping avoid the sterile "machine gun"
    effect.

### 6. Concurrency, Splicing & CLI Post-Processing

  - **Multi-Threaded Track Compilation:** Parallel tracks defined inside
    `PLAY_CONCURRENT` are compiled concurrently in separate OS threads using V's
    native go concurrency model.
  - **Track Mixing Normalization:** Summed channels are mixed using the standard
    square-root headroom formula:
    
    $$\text{mixed} = \frac{\sum (\text{track} \times \text{vol})}{\sqrt{N}}$$
    
    protecting the dynamic range from digital clipping.
  - **Track-Level & Master-Bus Inserts:** Effects can be loaded on individual track
    channels (allowing reverb/echo tails to ring out naturally over rests) or on
    the master output bus (`MASTER_EFFECT`).
  - **Constant-Time $O(1)$ Splicing (Render Breakpoints):** Slices and splices
    specific parts of the master float buffer using time ranges
    (`RENDER_RANGE 0.5-4.0`), allowing composers of fast, complex music (like
    Trashwave/Breakcore) to test and iterate specific segments.
  - **CLI Truncation Flags:** Supports quick previewing through CLI parameters
    (`--first <seconds>` / `-f` and `--last <seconds>` / `-l`) to slice the final output
    buffer instantly from the command line without editing the project files.
  - **Hard-Limiting Protection:** The master output stage applies a hard-limiter,
    clipping sample values at `[-32768, 32767]` to prevent wrap-around integer
    overflow distortions.
    
---
    
## Quick Start (One-Liner)

```bash
pkg update -y && pkg install -y git clang make && if ! command -v v >/dev/null 2>&1; then git clone --depth=1 https://github.com/vlang/v && cd v && make && ./v symlink && cd ..; fi && git clone --depth=1 https://github.com/tailsmails/musicc && cd musicc && v -prod musicc.v -o musicc && ln -sf $(pwd)/musicc $PREFIX/bin/musicc
```

---

## Usage

### 1. Compiling .mcc Files

Standard Compilation:
```bash
musicc song.mcc output.wav
```

Debug Mode (Verbose DSP Monitoring):
```bash
musicc song.mcc output.wav --debug
```

First N-Seconds Rendering (CLI Truncation):
```bash
musicc song.mcc output.wav --first 10
```

Last N-Seconds Rendering (CLI Truncation):
```bash
musicc song.mcc output.wav -l 5
```

### 2. MCC Language Syntax Example

Create a file named `melody.mcc` with the following modular script:

```text
SEED 950302
MASTER_VOLUME 0.8
MASTER_EFFECT space_echo

# 1. Custom Synthesizer with ADSR & PolyBLEP Antialiasing
DEFINE_SYNTH acid_bass sawtooth 5 0.1 0 0.15 10 120 0.5 150

# 2. Fragment Audio Shader with Advanced Processing & Block Reverse
DEFINE_EFFECT space_echo
    svf y lowpass 800.0 1.2
    compressor y -16.0 3.5 10.0 150.0 3.0
    vibrato y 5.5 1.2       # Subtle organic pitch vibrato (5.5Hz, 1.2ms delay depth)
    drift y 0.02            # 2% subtle amplitude drift
    reverse y 11025         # Glitchy 250ms block reverse with anti-click windowing
    reverb y 0.7 0.3 0.25 0.85
    ms_width y 1.5
END

---

# 3. Track Channel with Dynamic Humanization and Insert Effects
DEFINE bass_line|space_echo
    LOOP 2
        HUMANIZE OFF
        C2 300 acid_bass     # Perfectly quantized synthesizer note
        Eb2 300 acid_bass
        
        HUMANIZE ON
        REST 150
        F2 450 acid_bass     # Humanized timing and velocity dynamics
    END
END

# 4. Mix concurrently
PLAY_CONCURRENT bass_line:0.9
```

---

## DSP & Mixing Model

1.  **Thread Isolation:** Spawning parallel tracks generates local copies of all
    shaders and delay line buffers (`clone_shaders`), preventing signal
    bleeding or memory race conditions between threads.
2.  **Signal Flow:**
    
    $$\text{Synth/Sample Oscillator} \rightarrow \text{ADSR/LFO} \rightarrow \text{Track-level Insert Shaders} \rightarrow \text{Thread Mixing} \rightarrow \text{Master-bus Shaders} \rightarrow \text{CLI Truncator} \rightarrow \text{Hard Limiter} \rightarrow \text{Stereo WAV}$$
    
3.  **Memory Safety:** Memory-hard operations like real-time resamplers and delay
    lines utilize pre-allocated ring buffers to guarantee $O(1)$ sample-rate
    read/write times without Garbage Collection overhead.
  
---

## License
![License](https://img.shields.io/badge/License-MIT-green.svg)
