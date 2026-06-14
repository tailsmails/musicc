import os
import math

struct WavSample {
	samples     []f64
	sample_rate u32
	success     bool
}

struct SingleSampleInstrument {
	name      string
	sample    WavSample
	base_note string
}

struct MultiSampleInstrument {
	name    string
mut:
	samples map[string]WavSample
}

struct CustomSynth {
	name          string
	osc_type      string
	detune_voices int
	lfo_freq      f64
	fm_ratio      f64
	filter_cutoff f64
	attack_ms     int
	decay_ms      int
	sustain_level f64
	release_ms    int
}

struct DelayLine {
mut:
	buffer_l  []f64
	buffer_r  []f64
	write_idx int
	feedback  f64
}

struct ShaderInstruction {
	op      string
	out_var string
	args    []string
}

struct AudioShader {
	name string
mut:
	instructions     []ShaderInstruction
	delays           map[string]DelayLine
	prev_filter_l    map[string]f64
	prev_filter_r    map[string]f64
	vars_l           map[string]f64
	vars_r           map[string]f64
	comp_env_l       map[string]f64
	comp_env_r       map[string]f64
	svf_ic1_l        map[string]f64
	svf_ic2_l        map[string]f64
	svf_ic1_r        map[string]f64
	svf_ic2_r        map[string]f64
	reverb_buf_l     map[string][][]f64
	reverb_buf_r     map[string][][]f64
	reverb_idx_l     map[string][]int
	reverb_idx_r     map[string][]int
	chorus_buf_l     map[string][]f64
	chorus_buf_r     map[string][]f64
	chorus_idx       map[string]int
}

struct RenderRange {
	start_sec f64
	end_sec   f64
}

struct Command {
	line_num      int
	cmd_type      string
	note          string
	duration_ms   int
	wave_type     string
	loop_count    int
mut:
	start_ms      int
	end_ms        int
	is_slice      bool
	effects_chain []string
}

struct LoopState {
	start_ip    int
	total_count int
mut:
	current_iter int
}

fn note_to_freq(note string) f64 {
	if note == 'REST' || note == 'P' {
		return 0.0
	}
	if note.len < 2 {
		return 0.0
	}

	note_names := ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

	mut name := note[0..1]
	mut octave_str := note[1..]

	if note.len > 2 && (note[1] == `#` || note[1] == `b`) {
		name = note[0..2]
		octave_str = note[2..]
	}

	if name == 'Db' { name = 'C#' }
	else if name == 'Eb' { name = 'D#' }
	else if name == 'Gb' { name = 'F#' }
	else if name == 'Ab' { name = 'G#' }
	else if name == 'Bb' { name = 'A#' }

	note_idx := note_names.index(name)
	if note_idx == -1 {
		return 0.0
	}

	octave := octave_str.int()

	semitones := (octave - 4) * 12 + (note_idx - 9)
	return 440.0 * math.pow(2.0, f64(semitones) / 12.0)
}

fn note_to_semitone(note string) int {
	if note.len < 2 {
		return 0
	}
	note_names := ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
	mut name := note[0..1]
	mut octave_str := note[1..]
	if note.len > 2 && (note[1] == `#` || note[1] == `b`) {
		name = note[0..2]
		octave_str = note[2..]
	}
	if name == 'Db' { name = 'C#' }
	else if name == 'Eb' { name = 'D#' }
	else if name == 'Gb' { name = 'F#' }
	else if name == 'Ab' { name = 'G#' }
	else if name == 'Bb' { name = 'A#' }
	note_idx := note_names.index(name)
	if note_idx == -1 {
		return 0
	}
	octave := octave_str.int()
	return (octave - 4) * 12 + (note_idx - 9)
}

fn make_wav_header(data_len u32, sample_rate u32) []u8 {
	mut header := []u8{cap: 44}

	header << 'RIFF'.bytes()
	chunk_size := 36 + data_len
	header << u8(chunk_size)
	header << u8(chunk_size >> 8)
	header << u8(chunk_size >> 16)
	header << u8(chunk_size >> 24)

	header << 'WAVEfmt '.bytes()

	header << [u8(16), 0, 0, 0]
	header << [u8(1), 0, 2, 0]

	header << u8(sample_rate)
	header << u8(sample_rate >> 8)
	header << u8(sample_rate >> 16)
	header << u8(sample_rate >> 24)

	byte_rate := sample_rate * 4
	header << u8(byte_rate)
	header << u8(byte_rate >> 8)
	header << u8(byte_rate >> 16)
	header << u8(byte_rate >> 24)

	header << [u8(4), 0, 16, 0]

	header << 'data'.bytes()
	header << u8(data_len)
	header << u8(data_len >> 8)
	header << u8(data_len >> 16)
	header << u8(data_len >> 24)

	return header
}

fn load_wav(path string) WavSample {
	data := os.read_bytes(path) or {
		println('[!] Error: File not found at: ${path}')
		return WavSample{ success: false }
	}
	if data.len < 44 {
		println('[!] Error: File ${path} is too small to be a valid WAV.')
		return WavSample{ success: false }
	}
	if data[0] != `R` || data[1] != `I` || data[2] != `F` || data[3] != `F` {
		println('[!] Error: File ${path} is not a valid RIFF/WAV.')
		return WavSample{ success: false }
	}
	if data[8] != `W` || data[9] != `A` || data[10] != `V` || data[11] != `E` {
		println('[!] Error: File ${path} is not a valid WAVE file.')
		return WavSample{ success: false }
	}

	audio_format := u16(data[20]) | (u16(data[21]) << 8)
	channels := u16(data[22]) | (u16(data[23]) << 8)
	sample_rate := u32(data[24]) | (u32(data[25]) << 8) | (u32(data[26]) << 16) | (u32(data[27]) << 24)
	bits_per_sample := u16(data[34]) | (u16(data[35]) << 8)

	mut data_idx := -1
	for i := 12; i < data.len - 4; i++ {
		if data[i] == `d` && data[i + 1] == `a` && data[i + 2] == `t` && data[i + 3] == `a` {
			data_idx = i
			break
		}
	}
	if data_idx == -1 {
		println('[!] Error: Could not find "data" chunk in WAV file: ${path}')
		return WavSample{ success: false }
	}

	start_offset := data_idx + 8
	mut samples := []f64{}

	if bits_per_sample == 16 && audio_format == 1 {
		mut i := start_offset
		for i < data.len - 1 {
			val_16 := i16(u16(data[i]) | (u16(data[i + 1]) << 8))
			val_f64 := f64(val_16) / 32768.0
			samples << val_f64
			i += 2 * int(channels)
		}
	} else if bits_per_sample == 24 && audio_format == 1 {
		mut i := start_offset
		for i < data.len - 2 {
			val_24 := u32(data[i]) | (u32(data[i + 1]) << 8) | (u32(data[i + 2]) << 16)
			mut signed_val := int(val_24)
			if signed_val >= 0x800000 {
				signed_val -= 0x1000000
			}
			val_f64 := f64(signed_val) / 8388608.0
			samples << val_f64
			i += 3 * int(channels)
		}
	} else if bits_per_sample == 32 && audio_format == 3 {
		mut i := start_offset
		for i < data.len - 3 {
			bits := u32(data[i]) | (u32(data[i + 1]) << 8) | (u32(data[i + 2]) << 16) | (u32(data[i + 3]) << 24)
			val_f32 := unsafe { *(&f32(&bits)) }
			samples << f64(val_f32)
			i += 4 * int(channels)
		}
	} else if bits_per_sample == 8 && audio_format == 1 {
		mut i := start_offset
		for i < data.len {
			val_8 := data[i]
			val_f64 := (f64(val_8) - 128.0) / 128.0
			samples << val_f64
			i += int(channels)
		}
	} else {
		println('[!] Error: Unsupported WAV format in ${path}')
		return WavSample{ success: false }
	}

	return WavSample{
		samples: samples
		sample_rate: sample_rate
		success: true
	}
}

fn clone_shaders(shaders map[string]AudioShader) map[string]AudioShader {
	mut cloned := map[string]AudioShader{}
	for name, sh in shaders {
		mut cloned_delays := map[string]DelayLine{}
		for d_name, dl in sh.delays {
			cloned_delays[d_name] = DelayLine{
				buffer_l: dl.buffer_l.clone()
				buffer_r: dl.buffer_r.clone()
				write_idx: dl.write_idx
				feedback: dl.feedback
			}
		}
		mut cloned_filters_l := map[string]f64{}
		for k, v in sh.prev_filter_l {
			cloned_filters_l[k] = v
		}
		mut cloned_filters_r := map[string]f64{}
		for k, v in sh.prev_filter_r {
			cloned_filters_r[k] = v
		}
		cloned[name] = AudioShader{
			name: sh.name
			instructions: sh.instructions.clone()
			delays: cloned_delays
			prev_filter_l: cloned_filters_l
			prev_filter_r: cloned_filters_r
			vars_l: sh.vars_l.clone()
			vars_r: sh.vars_r.clone()
			comp_env_l: sh.comp_env_l.clone()
			comp_env_r: sh.comp_env_r.clone()
			svf_ic1_l: sh.svf_ic1_l.clone()
			svf_ic2_l: sh.svf_ic2_l.clone()
			svf_ic1_r: sh.svf_ic1_r.clone()
			svf_ic2_r: sh.svf_ic2_r.clone()
			reverb_buf_l: sh.reverb_buf_l.clone()
			reverb_buf_r: sh.reverb_buf_r.clone()
			reverb_idx_l: sh.reverb_idx_l.clone()
			reverb_idx_r: sh.reverb_idx_r.clone()
			chorus_buf_l: sh.chorus_buf_l.clone()
			chorus_buf_r: sh.chorus_buf_r.clone()
			chorus_idx: sh.chorus_idx.clone()
		}
	}
	return cloned
}

fn apply_shader(mut shader AudioShader, input_l f64, input_r f64, t f64) (f64, f64) {
	shader.vars_l['x'] = input_l
	shader.vars_r['x'] = input_r
	shader.vars_l['y'] = input_l
	shader.vars_r['y'] = input_r

	sample_rate := 44100.0

	for inst in shader.instructions {
		match inst.op {
			'delay' {
				name := inst.out_var
				mut dl := shader.delays[name] or { continue }
				delay_l := dl.buffer_l[dl.write_idx]
				delay_r := dl.buffer_r[dl.write_idx]
				shader.vars_l[name] = delay_l
				shader.vars_r[name] = delay_r

				input_to_delay_l := shader.vars_l['x']
				input_to_delay_r := shader.vars_r['x']
				dl.buffer_l[dl.write_idx] = input_to_delay_l + delay_l * dl.feedback
				dl.buffer_r[dl.write_idx] = input_to_delay_r + delay_r * dl.feedback
				dl.write_idx = (dl.write_idx + 1) % dl.buffer_l.len
				shader.delays[name] = dl
			}
			'mix' {
				mut sum_l := 0.0
				mut sum_r := 0.0
				mut i := 0
				for i < inst.args.len - 1 {
					var_name := inst.args[i]
					weight := inst.args[i + 1].f64()
					is_var_l := (var_name[0] >= `a` && var_name[0] <= `z`) || (var_name[0] >= `A` && var_name[0] <= `Z`)
					val_l := if is_var_l { shader.vars_l[var_name] } else { var_name.f64() }
					val_r := if is_var_l { shader.vars_r[var_name] } else { var_name.f64() }
					sum_l += val_l * weight
					sum_r += val_r * weight
					i += 2
				}
				shader.vars_l[inst.out_var] = sum_l
				shader.vars_r[inst.out_var] = sum_r
			}
			'saturate' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				sat_type := inst.args[0]
				mut sat_l := val_l
				mut sat_r := val_r
				match sat_type {
					'tanh' {
						sat_l = math.tanh(val_l)
						sat_r = math.tanh(val_r)
					}
					'hard' {
						if val_l > 1.0 { sat_l = 1.0 } else if val_l < -1.0 { sat_l = -1.0 }
						if val_r > 1.0 { sat_r = 1.0 } else if val_r < -1.0 { sat_r = -1.0 }
					}
					'soft' {
						if val_l > 1.0 { sat_l = 2.0 / 3.0 } else if val_l < -1.0 { sat_l = -2.0 / 3.0 } else { sat_l = val_l - (val_l * val_l * val_l) / 3.0 }
						if val_r > 1.0 { sat_r = 2.0 / 3.0 } else if val_r < -1.0 { sat_r = -2.0 / 3.0 } else { sat_r = val_r - (val_r * val_r * val_r) / 3.0 }
					}
					'fold' {
						sat_l = math.sin(val_l * math.pi * 0.5)
						sat_r = math.sin(val_r * math.pi * 0.5)
					}
					else {}
				}
				shader.vars_l[inst.out_var] = sat_l
				shader.vars_r[inst.out_var] = sat_r
			}
			'filter' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				filter_type := inst.args[0]
				cutoff := inst.args[1].f64()

				mut prev_l := shader.prev_filter_l[inst.out_var]
				mut prev_r := shader.prev_filter_r[inst.out_var]
				if filter_type == 'lowpass' {
					prev_l = prev_l + cutoff * (val_l - prev_l)
					prev_r = prev_r + cutoff * (val_r - prev_r)
					shader.vars_l[inst.out_var] = prev_l
					shader.vars_r[inst.out_var] = prev_r
				} else if filter_type == 'highpass' {
					prev_l = prev_l + cutoff * (val_l - prev_l)
					prev_r = prev_r + cutoff * (val_r - prev_r)
					shader.vars_l[inst.out_var] = val_l - prev_l
					shader.vars_r[inst.out_var] = val_r - prev_r
				}
				shader.prev_filter_l[inst.out_var] = prev_l
				shader.prev_filter_r[inst.out_var] = prev_r
			}
			'compressor' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				threshold_db := inst.args[0].f64()
				ratio := inst.args[1].f64()
				attack_ms := inst.args[2].f64()
				release_ms := inst.args[3].f64()
				makeup_db := inst.args[4].f64()

				t_att := math.exp(-1.0 / (sample_rate * (attack_ms / 1000.0)))
				t_rel := math.exp(-1.0 / (sample_rate * (release_ms / 1000.0)))

				mut env_l := shader.comp_env_l[inst.out_var]
				mut env_r := shader.comp_env_r[inst.out_var]

				abs_l := math.abs(val_l)
				abs_r := math.abs(val_r)

				env_l = if abs_l > env_l { t_att * env_l + (1.0 - t_att) * abs_l } else { t_rel * env_l + (1.0 - t_rel) * abs_l }
				env_r = if abs_r > env_r { t_att * env_r + (1.0 - t_att) * abs_r } else { t_rel * env_r + (1.0 - t_rel) * abs_r }

				shader.comp_env_l[inst.out_var] = env_l
				shader.comp_env_r[inst.out_var] = env_r

				env_db_l := 20.0 * math.log10(env_l + 1e-6)
				env_db_r := 20.0 * math.log10(env_r + 1e-6)

				mut gain_db_l := 0.0
				mut gain_db_r := 0.0

				if env_db_l > threshold_db {
					gain_db_l = (threshold_db - env_db_l) * (1.0 - 1.0 / ratio)
				}
				if env_db_r > threshold_db {
					gain_db_r = (threshold_db - env_db_r) * (1.0 - 1.0 / ratio)
				}

				total_gain_l := math.pow(10.0, (gain_db_l + makeup_db) / 20.0)
				total_gain_r := math.pow(10.0, (gain_db_r + makeup_db) / 20.0)

				shader.vars_l[inst.out_var] = val_l * total_gain_l
				shader.vars_r[inst.out_var] = val_r * total_gain_r
			}
			'svf' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				f_type := inst.args[0]
				cutoff := inst.args[1].f64()
				q := inst.args[2].f64()

				mut f := 2.0 * math.sin(math.pi * cutoff / sample_rate)
				if f < 0.001 { f = 0.001 }
				if f > 0.99 { f = 0.99 }
				d := 1.0 / q

				mut ic1_l := shader.svf_ic1_l[inst.out_var]
				mut ic2_l := shader.svf_ic2_l[inst.out_var]
				mut ic1_r := shader.svf_ic1_r[inst.out_var]
				mut ic2_r := shader.svf_ic2_r[inst.out_var]

				hp_l := val_l - ic2_l - d * ic1_l
				bp_l := ic1_l + f * hp_l
				lp_l := ic2_l + f * bp_l
				ic1_l = bp_l + f * hp_l
				ic2_l = lp_l + f * bp_l

				hp_r := val_r - ic2_r - d * ic1_r
				bp_r := ic1_r + f * hp_r
				lp_r := ic2_r + f * bp_r
				ic1_r = bp_r + f * hp_r
				ic2_r = lp_r + f * bp_r

				shader.svf_ic1_l[inst.out_var] = ic1_l
				shader.svf_ic2_l[inst.out_var] = ic2_l
				shader.svf_ic1_r[inst.out_var] = ic1_r
				shader.svf_ic2_r[inst.out_var] = ic2_r

				mut out_l := val_l
				mut out_r := val_r

				match f_type {
					'lowpass'  { out_l, out_r = lp_l, lp_r }
					'highpass' { out_l, out_r = hp_l, hp_r }
					'bandpass' { out_l, out_r = bp_l, bp_r }
					'notch'    { out_l, out_r = hp_l + lp_l, hp_r + lp_r }
					else {}
				}

				shader.vars_l[inst.out_var] = out_l
				shader.vars_r[inst.out_var] = out_r
			}
			'reverb' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				size := inst.args[0].f64()
				damp := inst.args[1].f64()
				wet := inst.args[2].f64()
				dry := inst.args[3].f64()

				comb_lens_l := [1116, 1188, 1277, 1356]
				comb_lens_r := [1213, 1134, 1301, 1267]

				if inst.out_var !in shader.reverb_buf_l {
					mut bl := [][]f64{}
					mut br := [][]f64{}
					for sz in comb_lens_l { bl << []f64{len: sz, init: 0.0} }
					for sz in comb_lens_r { br << []f64{len: sz, init: 0.0} }
					shader.reverb_buf_l[inst.out_var] = bl
					shader.reverb_buf_r[inst.out_var] = br
					shader.reverb_idx_l[inst.out_var] = [0, 0, 0, 0]
					shader.reverb_idx_r[inst.out_var] = [0, 0, 0, 0]
				}

				mut bufs_l := shader.reverb_buf_l[inst.out_var]
				mut bufs_r := shader.reverb_buf_r[inst.out_var]
				mut idxs_l := shader.reverb_idx_l[inst.out_var]
				mut idxs_r := shader.reverb_idx_r[inst.out_var]

				feedback := 0.7 * size
				mut comb_sum_l := 0.0
				mut comb_sum_r := 0.0

				for k in 0 .. 4 {
					out_comb_l := bufs_l[k][idxs_l[k]]
					out_comb_r := bufs_r[k][idxs_r[k]]

					comb_sum_l += out_comb_l
					comb_sum_r += out_comb_r

					bufs_l[k][idxs_l[k]] = val_l + out_comb_l * feedback * (1.0 - damp)
					bufs_r[k][idxs_r[k]] = val_r + out_comb_r * feedback * (1.0 - damp)

					idxs_l[k] = (idxs_l[k] + 1) % comb_lens_l[k]
					idxs_r[k] = (idxs_r[k] + 1) % comb_lens_r[k]
				}

				shader.reverb_buf_l[inst.out_var] = bufs_l
				shader.reverb_buf_r[inst.out_var] = bufs_r
				shader.reverb_idx_l[inst.out_var] = idxs_l
				shader.reverb_idx_r[inst.out_var] = idxs_r

				mixed_l := val_l * dry + (comb_sum_l * 0.25) * wet
				mixed_r := val_r * dry + (comb_sum_r * 0.25) * wet

				shader.vars_l[inst.out_var] = mixed_l
				shader.vars_r[inst.out_var] = mixed_r
			}
			'chorus' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				rate := inst.args[0].f64()
				depth := inst.args[1].f64()
				fb := inst.args[2].f64()
				mix := inst.args[3].f64()

				buf_size := 4410

				if inst.out_var !in shader.chorus_buf_l {
					shader.chorus_buf_l[inst.out_var] = []f64{len: buf_size, init: 0.0}
					shader.chorus_buf_r[inst.out_var] = []f64{len: buf_size, init: 0.0}
					shader.chorus_idx[inst.out_var] = 0
				}

				mut c_buf_l := shader.chorus_buf_l[inst.out_var]
				mut c_buf_r := shader.chorus_buf_r[inst.out_var]
				mut c_idx := shader.chorus_idx[inst.out_var]

				lfo := math.sin(2.0 * math.pi * rate * t)
				delay_samples := 220.0 + lfo * (depth * 44.1)

				mut read_ptr := math.fmod(f64(c_idx) - delay_samples + f64(buf_size), f64(buf_size))
				if read_ptr < 0.0 {
					read_ptr += f64(buf_size)
				}

				idx_floor := int(math.floor(read_ptr))
				idx_ceil := (idx_floor + 1) % buf_size
				frac := read_ptr - f64(idx_floor)

				delayed_l := c_buf_l[idx_floor] * (1.0 - frac) + c_buf_l[idx_ceil] * frac
				delayed_r := c_buf_r[idx_floor] * (1.0 - frac) + c_buf_r[idx_ceil] * frac

				c_buf_l[c_idx] = val_l + delayed_l * fb
				c_buf_r[c_idx] = val_r + delayed_r * fb
				c_idx = (c_idx + 1) % buf_size

				shader.chorus_buf_l[inst.out_var] = c_buf_l
				shader.chorus_buf_r[inst.out_var] = c_buf_r
				shader.chorus_idx[inst.out_var] = c_idx

				shader.vars_l[inst.out_var] = val_l * (1.0 - mix) + delayed_l * mix
				shader.vars_r[inst.out_var] = val_r * (1.0 - mix) + delayed_r * mix
			}
			'exciter' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				cutoff := inst.args[0].f64()
				drive := inst.args[1].f64()
				mix := inst.args[2].f64()

				mut prev_l := shader.prev_filter_l[inst.out_var + '_exc']
				mut prev_r := shader.prev_filter_r[inst.out_var + '_exc']
				alpha := 2.0 * math.pi * cutoff / sample_rate

				prev_l = prev_l + alpha * (val_l - prev_l)
				prev_r = prev_r + alpha * (val_r - prev_r)

				shader.prev_filter_l[inst.out_var + '_exc'] = prev_l
				shader.prev_filter_r[inst.out_var + '_exc'] = prev_r

				hp_l := val_l - prev_l
				hp_r := val_r - prev_r

				sat_l := math.tanh(hp_l * drive)
				sat_r := math.tanh(hp_r * drive)

				shader.vars_l[inst.out_var] = val_l + sat_l * mix
				shader.vars_r[inst.out_var] = val_r + sat_r * mix
			}
			'wavefolder' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				gain := inst.args[0].f64()

				mut out_l := val_l * gain
				for out_l > 1.0 || out_l < -1.0 {
					if out_l > 1.0 {
						out_l = 2.0 - out_l
					} else if out_l < -1.0 {
						out_l = -2.0 - out_l
					}
				}

				mut out_r := val_r * gain
				for out_r > 1.0 || out_r < -1.0 {
					if out_r > 1.0 {
						out_r = 2.0 - out_r
					} else if out_r < -1.0 {
						out_r = -2.0 - out_r
					}
				}

				shader.vars_l[inst.out_var] = out_l
				shader.vars_r[inst.out_var] = out_r
			}
			'vowel' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				vow_char := inst.args[0]
				mix := inst.args[1].f64()

				mut f1 := 600.0
				mut f2 := 1040.0
				mut f3 := 2250.0

				if vow_char == 'a' {
					f1, f2, f3 = 730.0, 1090.0, 2440.0
				} else if vow_char == 'e' {
					f1, f2, f3 = 530.0, 1840.0, 2480.0
				} else if vow_char == 'i' {
					f1, f2, f3 = 270.0, 2290.0, 3010.0
				} else if vow_char == 'o' {
					f1, f2, f3 = 570.0, 840.0, 2410.0
				} else if vow_char == 'u' {
					f1, f2, f3 = 300.0, 870.0, 2240.0
				}

				mut bp_sum_l := 0.0
				mut bp_sum_r := 0.0
				freqs := [f1, f2, f3]
				q := 12.0
				d := 1.0 / q

				for idx, freq in freqs {
					id_str := idx.str()
					mut f := 2.0 * math.sin(math.pi * freq / sample_rate)
					if f < 0.001 { f = 0.001 }
					if f > 0.99 { f = 0.99 }

					mut ic1_l := shader.svf_ic1_l[inst.out_var + '_vow' + id_str]
					mut ic2_l := shader.svf_ic2_l[inst.out_var + '_vow' + id_str]
					mut ic1_r := shader.svf_ic1_r[inst.out_var + '_vow' + id_str]
					mut ic2_r := shader.svf_ic2_r[inst.out_var + '_vow' + id_str]

					hp_l := val_l - ic2_l - d * ic1_l
					bp_l := ic1_l + f * hp_l
					lp_l := ic2_l + f * bp_l
					ic1_l = bp_l + f * hp_l
					ic2_l = lp_l + f * bp_l

					hp_r := val_r - ic2_r - d * ic1_r
					bp_r := ic1_r + f * hp_r
					lp_r := ic2_r + f * hp_r
					ic1_r = bp_r + f * hp_r
					ic2_r = lp_r + f * bp_r

					shader.svf_ic1_l[inst.out_var + '_vow' + id_str] = ic1_l
					shader.svf_ic2_l[inst.out_var + '_vow' + id_str] = ic2_l
					shader.svf_ic1_r[inst.out_var + '_vow' + id_str] = ic1_r
					shader.svf_ic2_r[inst.out_var + '_vow' + id_str] = ic2_r

					bp_sum_l += bp_l
					bp_sum_r += bp_r
				}

				out_l := val_l * (1.0 - mix) + (bp_sum_l * 2.5) * mix
				out_r := val_r * (1.0 - mix) + (bp_sum_r * 2.5) * mix

				shader.vars_l[inst.out_var] = out_l
				shader.vars_r[inst.out_var] = out_r
			}
			'phaser' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				rate := inst.args[0].f64()
				fb := inst.args[1].f64()
				mix := inst.args[2].f64()

				lfo := 0.5 + 0.5 * math.sin(2.0 * math.pi * rate * t)
				cutoff := 150.0 + lfo * 1550.0
				w0 := math.pi * cutoff / sample_rate
				a1 := (1.0 - math.tan(w0 * 0.5)) / (1.0 + math.tan(w0 * 0.5))

				fb_l := shader.prev_filter_l[inst.out_var + '_phfb_l']
				fb_r := shader.prev_filter_r[inst.out_var + '_phfb_r']

				mut ap_in_l := val_l + fb_l * fb
				mut ap_in_r := val_r + fb_r * fb

				for stage in 1 .. 5 {
					st_str := stage.str()

					xp_l := shader.prev_filter_l[inst.out_var + '_apx_l_' + st_str]
					yp_l := shader.prev_filter_l[inst.out_var + '_apy_l_' + st_str]
					xp_r := shader.prev_filter_r[inst.out_var + '_apx_r_' + st_str]
					yp_r := shader.prev_filter_r[inst.out_var + '_apy_r_' + st_str]

					out_l := a1 * ap_in_l + xp_l - a1 * yp_l
					out_r := a1 * ap_in_r + xp_r - a1 * yp_r

					shader.prev_filter_l[inst.out_var + '_apx_l_' + st_str] = ap_in_l
					shader.prev_filter_l[inst.out_var + '_apy_l_' + st_str] = out_l
					shader.prev_filter_r[inst.out_var + '_apx_r_' + st_str] = ap_in_r
					shader.prev_filter_r[inst.out_var + '_apy_r_' + st_str] = out_r

					ap_in_l = out_l
					ap_in_r = out_r
				}

				shader.prev_filter_l[inst.out_var + '_phfb_l'] = ap_in_l
				shader.prev_filter_r[inst.out_var + '_phfb_r'] = ap_in_r

				shader.vars_l[inst.out_var] = val_l * (1.0 - mix) + ap_in_l * mix
				shader.vars_r[inst.out_var] = val_r * (1.0 - mix) + ap_in_r * mix
			}
			'ms_width' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				width := inst.args[0].f64()

				mid := (val_l + val_r) * 0.5
				side := (val_l - val_r) * 0.5 * width

				shader.vars_l[inst.out_var] = mid + side
				shader.vars_r[inst.out_var] = mid - side
			}
			'modulate' {
				is_var_l := (inst.args[0][0] >= `a` && inst.args[0][0] <= `z`) || (inst.args[0][0] >= `A` && inst.args[0][0] <= `Z`)
				in_val_l := if is_var_l { shader.vars_l[inst.args[0]] } else { inst.args[0].f64() }
				in_val_r := if is_var_l { shader.vars_r[inst.args[0]] } else { inst.args[0].f64() }
				mod_type := inst.args[1]
				mod_freq := inst.args[2].f64()
				depth := inst.args[3].f64()

				mut mod_sig := 1.0
				if mod_type == 'tremolo' {
					mod_sig = 1.0 - depth + depth * math.sin(2.0 * math.pi * mod_freq * t)
				} else if mod_type == 'ring' {
					mod_sig = math.sin(2.0 * math.pi * mod_freq * t)
				}
				shader.vars_l[inst.out_var] = in_val_l * mod_sig
				shader.vars_r[inst.out_var] = in_val_r * mod_sig
			}
			'bitcrush' {
				val_l := shader.vars_l[inst.out_var]
				val_r := shader.vars_r[inst.out_var]
				bits := inst.args[0].f64()
				steps := math.pow(2.0, bits)
				shader.vars_l[inst.out_var] = math.floor(val_l * steps + 0.5) / steps
				shader.vars_r[inst.out_var] = math.floor(val_r * steps + 0.5) / steps
			}
			'pan' {
				pan_val := inst.args[0].f64()
				angle := (pan_val + 1.0) * math.pi / 4.0
				left_gain := math.cos(angle)
				right_gain := math.sin(angle)
				shader.vars_l[inst.out_var] = shader.vars_l[inst.out_var] * left_gain
				shader.vars_r[inst.out_var] = shader.vars_r[inst.out_var] * right_gain
			}
			'autopan' {
				freq_hz := inst.args[0].f64()
				pan_sweep := math.sin(2.0 * math.pi * freq_hz * t)
				angle := (pan_sweep + 1.0) * math.pi / 4.0
				left_gain := math.cos(angle)
				right_gain := math.sin(angle)
				shader.vars_l[inst.out_var] = shader.vars_l[inst.out_var] * left_gain
				shader.vars_r[inst.out_var] = shader.vars_r[inst.out_var] * right_gain
			}
			else {}
		}
		if inst.out_var == 'x' || inst.out_var == 'y' {
			shader.vars_l['x'] = shader.vars_l[inst.out_var]
			shader.vars_r['x'] = shader.vars_r[inst.out_var]
		}
	}
	return shader.vars_l['y'], shader.vars_r['y']
}

fn interpret_track(commands []Command, single_samples map[string]SingleSampleInstrument, multi_samples map[string]MultiSampleInstrument, custom_synths map[string]CustomSynth, active_shaders map[string]AudioShader, track_effects []string, sample_rate u32) []f64 {
	mut local_shaders := clone_shaders(active_shaders)
	dry_pcm := interpret_track_mut(commands, single_samples, multi_samples, custom_synths, mut
		local_shaders, sample_rate)

	if track_effects.len == 0 {
		return dry_pcm
	}

	mut processed_pcm := []f64{cap: dry_pcm.len}
	mut i := 0
	for i < dry_pcm.len - 1 {
		t := f64(i / 2) / f64(sample_rate)
		mut left_val := dry_pcm[i]
		mut right_val := dry_pcm[i + 1]
		for fx_name in track_effects {
			if fx_name in local_shaders {
				left_val, right_val = apply_shader(mut local_shaders[fx_name], left_val,
					right_val, t)
			}
		}
		processed_pcm << left_val
		processed_pcm << right_val
		i += 2
	}
	return processed_pcm
}

fn interpret_track_mut(commands []Command, single_samples map[string]SingleSampleInstrument, multi_samples map[string]MultiSampleInstrument, custom_synths map[string]CustomSynth, mut active_shaders map[string]AudioShader, sample_rate u32) []f64 {
	mut track_pcm := []f64{}
	mut loop_stack := []LoopState{}
	mut ip := 0
	mut prev_filter_val := 0.0

	for ip < commands.len {
		cmd := commands[ip]
		match cmd.cmd_type {
			'loop' {
				loop_stack << LoopState{
					start_ip: ip + 1
					total_count: cmd.loop_count
					current_iter: 1
				}
				ip++
			}
			'end' {
				if loop_stack.len == 0 {
					ip++
					continue
				}
				last_idx := loop_stack.len - 1
				if loop_stack[last_idx].current_iter < loop_stack[last_idx].total_count {
					loop_stack[last_idx].current_iter++
					ip = loop_stack[last_idx].start_ip
				} else {
					loop_stack.pop()
					ip++
				}
			}
			'note' {
				freq := note_to_freq(cmd.note)
				duration_sec := f64(cmd.duration_ms) / 1000.0
				num_samples := int(f64(sample_rate) * duration_sec)

				mut generated_pcm := []f64{}

				if cmd.wave_type in single_samples {
					inst := single_samples[cmd.wave_type]
					base_freq := note_to_freq(inst.base_note)
					ratio := if base_freq > 0.0 { freq / base_freq } else { 1.0 }

					start_sec := f64(cmd.start_ms) / 1000.0
					start_src_idx := start_sec * f64(inst.sample.sample_rate)

					mut actual_num_samples := num_samples
					if cmd.duration_ms == 0 {
						remaining_src_samples := f64(inst.sample.samples.len) - start_src_idx
						if remaining_src_samples > 0 {
							resampled_duration_sec := (remaining_src_samples / f64(inst.sample.sample_rate)) / ratio
							actual_num_samples = int(resampled_duration_sec * f64(sample_rate))
						} else {
							actual_num_samples = 0
						}
					}

					for i in 0 .. actual_num_samples {
						mut sample_val := 0.0
						if freq > 0.0 {
							pos := start_src_idx + f64(i) * ratio * (f64(inst.sample.sample_rate) / f64(sample_rate))
							idx_floor := int(math.floor(pos))
							idx_ceil := idx_floor + 1
							frac := pos - f64(idx_floor)

							if idx_floor >= 0 && idx_floor < inst.sample.samples.len {
								val1 := inst.sample.samples[idx_floor]
								val2 := if idx_ceil < inst.sample.samples.len {
									inst.sample.samples[idx_ceil]
								} else {
									0.0
								}
								sample_val = val1 + frac * (val2 - val1)
							}

							fade_samples := int(0.01 * f64(sample_rate))
							mut env := 1.0
							if i < fade_samples {
								env = f64(i) / f64(fade_samples)
							} else if i > actual_num_samples - fade_samples {
								env = f64(num_samples - i) / f64(fade_samples)
							}
							sample_val *= env
						}
						generated_pcm << sample_val
					}
				} else if cmd.wave_type in multi_samples {
					inst := multi_samples[cmd.wave_type]
					if inst.samples.len == 0 {
						for _ in 0 .. num_samples {
							generated_pcm << 0.0
						}
					} else {
						mut min_dist := 99999
						mut best_note := ''
						target_semi := note_to_semitone(cmd.note)

						for def_note, _ in inst.samples {
							def_semi := note_to_semitone(def_note)
							dist := math.abs(target_semi - def_semi)
							if dist < min_dist {
								min_dist = int(dist)
								best_note = def_note
							}
						}

						best_sample := inst.samples[best_note]
						base_freq := note_to_freq(best_note)
						ratio := if base_freq > 0.0 { freq / base_freq } else { 1.0 }

						start_sec := f64(cmd.start_ms) / 1000.0
						start_src_idx := start_sec * f64(best_sample.sample_rate)

						mut actual_num_samples := num_samples
						if cmd.duration_ms == 0 {
							remaining_src_samples := f64(best_sample.samples.len) - start_src_idx
							if remaining_src_samples > 0 {
								resampled_duration_sec := (remaining_src_samples / f64(best_sample.sample_rate)) / ratio
								actual_num_samples = int(resampled_duration_sec * f64(sample_rate))
							} else {
								actual_num_samples = 0
							}
						}

						for i in 0 .. actual_num_samples {
							mut sample_val := 0.0
							if freq > 0.0 {
								pos := start_src_idx + f64(i) * ratio * (f64(best_sample.sample_rate) / f64(sample_rate))
								idx_floor := int(math.floor(pos))
								idx_ceil := idx_floor + 1
								frac := pos - f64(idx_floor)

								if idx_floor >= 0 && idx_floor < best_sample.samples.len {
									val1 := best_sample.samples[idx_floor]
									val2 := if idx_ceil < best_sample.samples.len {
										best_sample.samples[idx_ceil]
									} else {
										0.0
									}
									sample_val = val1 + frac * (val2 - val1)
								}

								fade_samples := int(0.01 * f64(sample_rate))
								mut env := 1.0
								if i < fade_samples {
									env = f64(i) / f64(fade_samples)
								} else if i > actual_num_samples - fade_samples {
									env = f64(num_samples - i) / f64(fade_samples)
								}
								sample_val *= env
							}
							generated_pcm << sample_val
						}
					}
				} else if cmd.wave_type in custom_synths {
					synth := custom_synths[cmd.wave_type]

					for i in 0 .. num_samples {
						mut sample_val := 0.0
						if freq > 0.0 {
							t := f64(i) / f64(sample_rate)

							a_sec := f64(synth.attack_ms) / 1000.0
							d_sec := f64(synth.decay_ms) / 1000.0
							s_level := synth.sustain_level
							r_sec := f64(synth.release_ms) / 1000.0

							mut adsr_env := 0.0
							mut scale_factor := 1.0
							sum_phases := a_sec + d_sec + r_sec
							if duration_sec < sum_phases {
								scale_factor = duration_sec / sum_phases
							}

							sa := a_sec * scale_factor
							sd := d_sec * scale_factor
							sr_val := r_sec * scale_factor

							if t < sa {
								adsr_env = t / (sa + 0.0001)
							} else if t < sa + sd {
								decay_progress := (t - sa) / (sd + 0.0001)
								adsr_env = 1.0 - decay_progress * (1.0 - s_level)
							} else if t < duration_sec - sr_val {
								adsr_env = s_level
							} else {
								release_progress := (t - (duration_sec - sr_val)) / (sr_val + 0.0001)
								adsr_env = s_level * (1.0 - release_progress)
							}
							if adsr_env < 0.0 { adsr_env = 0.0 }
							if adsr_env > 1.0 { adsr_env = 1.0 }

							mut lfo_vol := 1.0
							if synth.lfo_freq > 0.0 {
								lfo_vol = 0.7 + 0.3 * math.sin(2.0 * math.pi * synth.lfo_freq * t)
							}

							mut fm_index := 0.0
							if synth.fm_ratio > 0.0 {
								fm_index = 2.0 + 1.5 * math.sin(2.0 * math.pi * 0.15 * t)
							}

							mut signal := 0.0
							voices := if synth.detune_voices > 0 { synth.detune_voices } else { 1 }

							for v_idx in 0 .. voices {
								mut detune_mult := 1.0
								if voices > 1 {
									offset := f64(v_idx) - f64(voices - 1) / 2.0
									detune_mult = 1.0 + offset * 0.006
								}

								v_freq := freq * detune_mult
								mut phase := 2.0 * math.pi * v_freq * t

								if synth.fm_ratio > 0.0 {
									modulator_phase := 2.0 * math.pi * (v_freq * synth.fm_ratio) * t
									phase += fm_index * math.sin(modulator_phase)
								}

								mut voice_val := 0.0
								match synth.osc_type {
									'sawtooth' {
										voice_val = 2.0 * (phase / (2.0 * math.pi) - math.floor(0.5 + phase / (2.0 * math.pi)))
									}
									'square' {
										voice_val = if math.sin(phase) >= 0.0 { 1.0 } else { -1.0 }
									}
									'triangle' {
										voice_val = 2.0 * math.abs(2.0 * (phase / (2.0 * math.pi) - math.floor(0.5 + phase / (2.0 * math.pi)))) - 1.0
									}
									'noise' {
										mut seed := u32(123456789 + i + v_idx * 99)
										seed = seed * 1664525 + 1013904223
										voice_val = f64(int(seed) % 2000) / 1000.0 - 1.0
									}
									else {
										voice_val = math.sin(phase)
									}
								}
								signal += voice_val
							}
							sample_val = signal / f64(voices)

							if synth.filter_cutoff > 0.0 {
								alpha := synth.filter_cutoff * (1.2 + 0.8 * math.sin(2.0 * math.pi * 0.08 * t))
								mut clamped_alpha := alpha
								if clamped_alpha < 0.001 {
									clamped_alpha = 0.001
								}
								if clamped_alpha > 0.99 {
									clamped_alpha = 0.99
								}
								prev_filter_val = prev_filter_val + clamped_alpha * (sample_val - prev_filter_val)
								sample_val = prev_filter_val
							}

							sample_val *= lfo_vol * adsr_env
						}
						generated_pcm << sample_val
					}
				} else {
					for i in 0 .. num_samples {
						mut sample_val := 0.0
						if freq > 0.0 {
							angle := 2.0 * math.pi * freq * f64(i) / f64(sample_rate)
							t := f64(i) / f64(sample_rate)
							progress := f64(i) / f64(num_samples)

							match cmd.wave_type {
								'square' {
									fade_samples := int(0.01 * f64(sample_rate))
									mut env := 1.0
									if i < fade_samples {
										env = f64(i) / f64(fade_samples)
									} else if i > num_samples - fade_samples {
										env = f64(num_samples - i) / f64(fade_samples)
									}
									sample_val = (if math.sin(angle) >= 0.0 { 1.0 } else { -1.0 }) * env
								}
								'sawtooth' {
									fade_samples := int(0.01 * f64(sample_rate))
									mut env := 1.0
									if i < fade_samples {
										env = f64(i) / f64(fade_samples)
									} else if i > num_samples - fade_samples {
										env = f64(num_samples - i) / f64(fade_samples)
									}
									sample_val = (2.0 * (angle / (2.0 * math.pi) - math.floor(0.5 + angle / (2.0 * math.pi)))) * env
								}
								'piano' {
									decay := math.exp(-4.0 * progress)
									attack_samples := int(0.005 * f64(sample_rate))
									mut env := decay
									if i < attack_samples {
										env = (f64(i) / f64(attack_samples)) * decay
									}
									mut signal := 0.0
									signal += 1.00 * math.sin(2.0 * math.pi * freq * t)
									signal += 0.50 * math.sin(2.0 * math.pi * (2.0 * freq) * t)
									signal += 0.25 * math.sin(2.0 * math.pi * (3.0 * freq) * t)
									signal += 0.12 * math.sin(2.0 * math.pi * (4.0 * freq) * t)
									signal += 0.06 * math.sin(2.0 * math.pi * (5.0 * freq) * t)
									sample_val = (signal / 1.93) * env
								}
								'pluck' {
									decay := math.exp(-6.0 * progress)
									mut signal := 0.0
									signal += 1.0 * math.sin(2.0 * math.pi * freq * t)
									signal += 0.6 * math.sin(2.0 * math.pi * (2.0 * freq) * t) * math.exp(-12.0 * progress)
									signal += 0.4 * math.sin(2.0 * math.pi * (3.0 * freq) * t) * math.exp(-18.0 * progress)
									signal += 0.2 * math.sin(2.0 * math.pi * (4.0 * freq) * t) * math.exp(-24.0 * progress)
									sample_val = (signal / 2.2) * decay
								}
								'bell' {
									decay := math.exp(-2.5 * progress)
									mut signal := 0.0
									signal += 1.0 * math.sin(2.0 * math.pi * freq * t)
									signal += 0.6 * math.sin(2.0 * math.pi * (2.0 * freq) * t)
									signal += 0.4 * math.sin(2.0 * math.pi * (2.4 * freq) * t)
									signal += 0.3 * math.sin(2.0 * math.pi * (3.0 * freq) * t)
									signal += 0.2 * math.sin(2.0 * math.pi * (3.7 * freq) * t)
									sample_val = (signal / 2.5) * decay
								}
								else {
									fade_samples := int(0.01 * f64(sample_rate))
									mut env := 1.0
									if i < fade_samples {
										env = f64(i) / f64(fade_samples)
									} else if i > num_samples - fade_samples {
										env = f64(num_samples - i) / f64(fade_samples)
									}
									sample_val = math.sin(angle) * env
								}
							}
						}
						generated_pcm << sample_val
					}
				}

				for i, sample_val in generated_pcm {
					t := f64(i) / f64(sample_rate)
					mut left_val := sample_val
					mut right_val := sample_val
					for fx_name in cmd.effects_chain {
						if fx_name in active_shaders {
							left_val, right_val = apply_shader(mut active_shaders[fx_name],
								left_val, right_val, t)
						}
					}
					track_pcm << left_val
					track_pcm << right_val
				}
				ip++
			}
			else {
				ip++
			}
		}
	}
	return track_pcm
}

fn main() {
	if os.args.len < 3 {
		println('Usage: v run musicc.v <input_file.mcc> <output_wav_file>')
		return
	}
	input_path := os.args[1]
	output_path := os.args[2]

	if !input_path.ends_with('.mcc') {
		println('[!] Error: Invalid file format. The Music Compiler Code file must have a .mcc extension.')
		return
	}

	lines := os.read_lines(input_path) or {
		println('[!] Error: Could not read input file: ${err}')
		return
	}

	mut debug_enabled := false
	for arg in os.args {
		if arg == '--debug' || arg == '-d' {
			debug_enabled = true
		}
	}

	mut slice_first_secs := 0.0
	mut slice_last_secs := 0.0
	mut has_slice_first := false
	mut has_slice_last := false

	for idx := 0; idx < os.args.len; idx++ {
		arg := os.args[idx]
		if arg == '--first' || arg == '-f' {
			if idx + 1 < os.args.len {
				slice_first_secs = os.args[idx + 1].f64()
				has_slice_first = true
			}
		} else if arg == '--last' || arg == '-l' {
			if idx + 1 < os.args.len {
				slice_last_secs = os.args[idx + 1].f64()
				has_slice_last = true
			}
		}
	}

	mut single_samples := map[string]SingleSampleInstrument{}
	mut multi_samples := map[string]MultiSampleInstrument{}
	mut custom_synths := map[string]CustomSynth{}
	mut active_shaders := map[string]AudioShader{}
	mut defined_tracks := map[string][]Command{}
	mut track_effects := map[string][]string{}
	mut master_effects := []string{}
	mut render_ranges := []RenderRange{}
	mut master_volume_factor := 1.0
	mut commands := []Command{}

	mut current_define_name := ''
	mut define_depth := 0
	mut define_commands := []Command{}

	mut current_fx_name := ''
	mut fx_instructions := []ShaderInstruction{}
	mut fx_delays := map[string]DelayLine{}

	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') {
			continue
		}

		parts := trimmed.split(' ')
		first_token := parts[0].to_upper()

		if first_token == 'DEBUG_MODE' {
			if parts.len > 1 && parts[1].to_upper() == 'ON' {
				debug_enabled = true
			}
			continue
		}

		if first_token == 'RENDER_RANGE' {
			if parts.len > 1 {
				range_parts := parts[1].split('-')
				if range_parts.len == 2 {
					render_ranges << RenderRange{
						start_sec: range_parts[0].f64()
						end_sec: range_parts[1].f64()
					}
				}
			}
			continue
		}

		if first_token == 'MASTER_VOLUME' {
			if parts.len > 1 {
				master_volume_factor = parts[1].f64()
			}
			continue
		}

		if first_token == 'MASTER_EFFECT' {
			if parts.len > 1 {
				master_effects = parts[1..].clone()
			}
			continue
		}

		if first_token == 'DEFINE_EFFECT' {
			if parts.len < 2 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE_EFFECT needs a name')
				return
			}
			current_fx_name = parts[1].to_lower()
			fx_instructions = []ShaderInstruction{}
			fx_delays = map[string]DelayLine{}
			if debug_enabled {
				println('[Debug] Parsing effect definition: ${current_fx_name}')
			}
			continue
		}

		if current_fx_name != '' {
			if first_token == 'END' {
				mut vars_map := map[string]f64{}
				vars_map['x'] = 0.0
				vars_map['y'] = 0.0
				for inst in fx_instructions {
					vars_map[inst.out_var] = 0.0
					for arg in inst.args {
						if arg.len > 0 && ((arg[0] >= `a` && arg[0] <= `z`) || (arg[0] >= `A` && arg[0] <= `Z`)) {
							vars_map[arg] = 0.0
						}
					}
				}

				active_shaders[current_fx_name] = AudioShader{
					name: current_fx_name
					instructions: fx_instructions
					delays: fx_delays
					prev_filter_l: map[string]f64{}
					prev_filter_r: map[string]f64{}
					vars_l: vars_map.clone()
					vars_r: vars_map.clone()
					comp_env_l: map[string]f64{}
					comp_env_r: map[string]f64{}
					svf_ic1_l: map[string]f64{}
					svf_ic2_l: map[string]f64{}
					svf_ic1_r: map[string]f64{}
					svf_ic2_r: map[string]f64{}
					reverb_buf_l: map[string][][]f64{}
					reverb_buf_r: map[string][][]f64{}
					reverb_idx_l: map[string][]int{}
					reverb_idx_r: map[string][]int{}
					chorus_buf_l: map[string][]f64{}
					chorus_buf_r: map[string][]f64{}
					chorus_idx: map[string]int{}
				}
				if debug_enabled {
					println('[Debug] Loaded Audio Shader effect: ${current_fx_name}')
				}
				current_fx_name = ''
				continue
			}

			op := parts[0].to_lower()
			if op == 'delay' {
				name := parts[1]
				size := parts[2].int()
				feedback := parts[3].f64()
				fx_delays[name] = DelayLine{
					buffer_l: []f64{len: size, init: 0.0}
					buffer_r: []f64{len: size, init: 0.0}
					write_idx: 0
					feedback: feedback
				}
				fx_instructions << ShaderInstruction{
					op: 'delay'
					out_var: name
					args: parts[1..]
				}
			} else {
				out_var := parts[1]
				args := parts[2..]
				fx_instructions << ShaderInstruction{
					op: op
					out_var: out_var
					args: args
				}
			}
			continue
		}

		if first_token == 'DEFINE_SYNTH' {
			if parts.len < 7 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE_SYNTH requires at least 6 arguments')
				return
			}
			name := parts[1].to_lower()
			osc_type := parts[2].to_lower()
			detune_voices := parts[3].int()
			lfo_freq := parts[4].f64()
			fm_ratio := parts[5].f64()
			filter_cutoff := parts[6].f64()

			mut attack_ms := 10
			mut decay_ms := 10
			mut sustain_level := 1.0
			mut release_ms := 10

			if parts.len >= 11 {
				attack_ms = parts[7].int()
				decay_ms = parts[8].int()
				sustain_level = parts[9].f64()
				release_ms = parts[10].int()
			}

			custom_synths[name] = CustomSynth{
				name: name
				osc_type: osc_type
				detune_voices: detune_voices
				lfo_freq: lfo_freq
				fm_ratio: fm_ratio
				filter_cutoff: filter_cutoff
				attack_ms: attack_ms
				decay_ms: decay_ms
				sustain_level: sustain_level
				release_ms: release_ms
			}
			if debug_enabled {
				println('[Debug] Registered synthesizer: ${name}')
			}
			continue
		}

		if first_token == 'DEFINE' {
			if parts.len < 2 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE requires a track name')
				return
			}
			track_def := parts[1].to_lower()
			sub_parts := track_def.split('|')
			current_define_name = sub_parts[0]
			define_depth = 1
			define_commands = []Command{}
			if sub_parts.len > 1 {
				track_effects[current_define_name] = sub_parts[1..].clone()
			} else {
				track_effects[current_define_name] = []string{}
			}
			if debug_enabled {
				println('[Debug] Parsing track: ${current_define_name}')
			}
			continue
		}

		if current_define_name != '' {
			if first_token == 'LOOP' || first_token == 'DEFINE' {
				define_depth++
			} else if first_token == 'END' {
				define_depth--
				if define_depth == 0 {
					defined_tracks[current_define_name] = define_commands
					if debug_enabled {
						println('[Debug] Closed track: ${current_define_name}')
					}
					current_define_name = ''
					continue
				}
			}

			if first_token == 'LOOP' {
				count := if parts.len > 1 { parts[1].int() } else { 1 }
				define_commands << Command{
					line_num: i + 1
					cmd_type: 'loop'
					loop_count: count
				}
			} else if first_token == 'END' {
				define_commands << Command{
					line_num: i + 1
					cmd_type: 'end'
				}
			} else {
				if parts.len < 2 {
					continue
				}
				note := parts[0]
				duration_str := parts[1]
				mut duration_ms := 0
				mut start_ms := 0
				mut end_ms := 0
				mut is_slice := false

				if duration_str.contains('-') {
					slice_parts := duration_str.split('-')
					if slice_parts.len == 2 {
						start_ms = slice_parts[0].int()
						end_ms = slice_parts[1].int()
						is_slice = true
						if end_ms > 0 {
							duration_ms = end_ms - start_ms
						} else {
							duration_ms = 0
						}
					}
				} else {
					duration_ms = duration_str.int()
				}

				mut wave_type := 'sine'
				mut effects_chain := []string{}
				if parts.len >= 3 {
					instrument_part := parts[2].to_lower()
					sub_parts := instrument_part.split('|')
					wave_type = sub_parts[0]
					if sub_parts.len > 1 {
						effects_chain = sub_parts[1..].clone()
					}
				}

				define_commands << Command{
					line_num: i + 1
					cmd_type: 'note'
					note: note
					duration_ms: duration_ms
					wave_type: wave_type
					start_ms: start_ms
					end_ms: end_ms
					is_slice: is_slice
					effects_chain: effects_chain
				}
			}
			continue
		}

		if first_token == 'LOAD_SAMPLE' {
			if parts.len < 4 {
				continue
			}
			name := parts[1].to_lower()
			path := parts[2]
			base_note := parts[3]
			wav := load_wav(path)
			if !wav.success {
				println('[-] Warning: Sample at line ${i + 1} was not loaded.')
				continue
			}
			single_samples[name] = SingleSampleInstrument{
				name: name
				sample: wav
				base_note: base_note
			}
			if debug_enabled {
				println('[Debug] Loaded WAV sample: ${name}')
			}
		} else if first_token == 'LOAD_MULTISAMPLE' {
			if parts.len < 2 {
				continue
			}
			name := parts[1].to_lower()
			multi_samples[name] = MultiSampleInstrument{
				name: name
				samples: map[string]WavSample{}
			}
		} else if first_token == 'ADD_SAMPLE' {
			if parts.len < 4 {
				continue
			}
			inst_name := parts[1].to_lower()
			note_name := parts[2]
			path := parts[3]
			if inst_name in multi_samples {
				wav := load_wav(path)
				if !wav.success {
					println('[-] Warning: Multi-sample at line ${i + 1} was not loaded.')
					continue
				}
				multi_samples[inst_name].samples[note_name] = wav
				if debug_enabled {
					println('[Debug] Added sample to bank ${inst_name}: ${note_name}')
				}
			} else {
				println('[-] Error line ${i + 1}: Multi-sample instrument ${inst_name} was not loaded')
			}
		} else if first_token == 'PLAY_CONCURRENT' {
			commands << Command{
				line_num: i + 1
				cmd_type: 'play_concurrent'
				wave_type: parts[1..].join(' ').to_lower()
			}
		} else if first_token == 'LOOP' {
			count := if parts.len > 1 { parts[1].int() } else { 1 }
			commands << Command{
				line_num: i + 1
				cmd_type: 'loop'
				loop_count: count
			}
		} else if first_token == 'END' {
			commands << Command{
				line_num: i + 1
				cmd_type: 'end'
			}
		} else {
			if parts.len < 2 {
				continue
			}
			note := parts[0]
			duration_str := parts[1]
			mut duration_ms := 0
			mut start_ms := 0
			mut end_ms := 0
			mut is_slice := false

			if duration_str.contains('-') {
				slice_parts := duration_str.split('-')
				if slice_parts.len == 2 {
					start_ms = slice_parts[0].int()
					end_ms = slice_parts[1].int()
					is_slice = true
					if end_ms > 0 {
						duration_ms = end_ms - start_ms
					} else {
						duration_ms = 0
					}
				}
			} else {
				duration_ms = duration_str.int()
			}

			mut wave_type := 'sine'
			mut effects_chain := []string{}
			if parts.len >= 3 {
				instrument_part := parts[2].to_lower()
				sub_parts := instrument_part.split('|')
				wave_type = sub_parts[0]
				if sub_parts.len > 1 {
					effects_chain = sub_parts[1..].clone()
				}
			}

			commands << Command{
				line_num: i + 1
				cmd_type: 'note'
				note: note
				duration_ms: duration_ms
				wave_type: wave_type
				start_ms: start_ms
				end_ms: end_ms
				is_slice: is_slice
				effects_chain: effects_chain
			}
		}
	}

	if current_define_name != '' {
		println('[!] Compilation Error: DEFINE block "${current_define_name}" was never closed.')
		return
	}

	sample_rate := u32(44100)
	mut master_dry_pcm := []f64{}
	volume := 28000.0 * master_volume_factor

	println('[*] Interpreting instructions and generating audio...')

	mut loop_stack := []LoopState{}
	mut ip := 0

	for ip < commands.len {
		cmd := commands[ip]
		match cmd.cmd_type {
			'loop' {
				loop_stack << LoopState{
					start_ip: ip + 1
					total_count: cmd.loop_count
					current_iter: 1
				}
				ip++
			}
			'end' {
				if loop_stack.len == 0 {
					println('[!] Syntax Error: "END" statement found without a matching block.')
					return
				}
				last_idx := loop_stack.len - 1
				if loop_stack[last_idx].current_iter < loop_stack[last_idx].total_count {
					loop_stack[last_idx].current_iter++
					ip = loop_stack[last_idx].start_ip
				} else {
					loop_stack.pop()
					ip++
				}
			}
			'play_concurrent' {
				track_specifiers := cmd.wave_type.split(' ')
				mut threads := []thread []f64{}
				mut track_vols := []f64{}
				for spec in track_specifiers {
					cleaned := spec.trim_space()
					if cleaned == '' {
						continue
					}
					parts := cleaned.split(':')
					name := parts[0]
					vol := if parts.len > 1 { parts[1].f64() } else { 1.0 }

					if name in defined_tracks {
						track_cmds := defined_tracks[name]
						fx := track_effects[name] or { []string{} }
						threads << go interpret_track(track_cmds, single_samples, multi_samples,
							custom_synths, active_shaders, fx, sample_rate)
						track_vols << vol
					} else {
						println('[-] Error: Defined track "${name}" not found.')
					}
				}

				results := threads.wait()

				mut max_len := 0
				for res in results {
					if res.len > max_len {
						max_len = res.len
					}
				}

				mut mixed_block := []f64{len: max_len, init: 0.0}
				for i in 0 .. max_len {
					mut mixed_sample := 0.0
					for r_idx, res in results {
						if i < res.len {
							mixed_sample += res[i] * track_vols[r_idx]
						}
					}
					if results.len > 1 {
						mixed_sample /= math.sqrt(f64(results.len))
					}
					mixed_block[i] = mixed_sample
				}

				for val in mixed_block {
					master_dry_pcm << val
				}
				ip++
			}
			'note' {
				res := interpret_track_mut([cmd], single_samples, multi_samples, custom_synths, mut
					active_shaders, sample_rate)
				for val in res {
					master_dry_pcm << val
				}
				ip++
			}
			else {
				ip++
			}
		}
	}

	println('[*] Applying master bus effects...')
	mut master_wet_pcm := []f64{cap: master_dry_pcm.len}
	if master_effects.len > 0 {
		mut k := 0
		for k < master_dry_pcm.len - 1 {
			t := f64(k / 2) / f64(sample_rate)
			mut left_val := master_dry_pcm[k]
			mut right_val := master_dry_pcm[k + 1]
			for fx_name in master_effects {
				if fx_name in active_shaders {
					left_val, right_val = apply_shader(mut active_shaders[fx_name], left_val,
						right_val, t)
				}
			}
			master_wet_pcm << left_val
			master_wet_pcm << right_val
			k += 2
		}
	} else {
		master_wet_pcm = master_dry_pcm.clone()
	}

	if render_ranges.len > 0 {
		println('[*] Splicing requested render ranges...')
		mut master_sliced_pcm := []f64{}
		for r in render_ranges {
			mut start_idx := int(r.start_sec * f64(sample_rate)) * 2
			mut end_idx := int(r.end_sec * f64(sample_rate)) * 2

			if start_idx < 0 {
				start_idx = 0
			}
			if end_idx > master_wet_pcm.len {
				end_idx = master_wet_pcm.len
			}
			if start_idx >= master_wet_pcm.len {
				continue
			}
			if end_idx < start_idx {
				continue
			}

			for val in master_wet_pcm[start_idx..end_idx] {
				master_sliced_pcm << val
			}
		}
		master_wet_pcm = master_sliced_pcm.clone()
	}

	if has_slice_first {
		mut limit_samples := int(slice_first_secs * f64(sample_rate)) * 2
		if limit_samples > master_wet_pcm.len {
			limit_samples = master_wet_pcm.len
		}
		master_wet_pcm = master_wet_pcm[0..limit_samples].clone()
	} else if has_slice_last {
		mut limit_samples := int(slice_last_secs * f64(sample_rate)) * 2
		if limit_samples > master_wet_pcm.len {
			limit_samples = master_wet_pcm.len
		}
		start_idx := master_wet_pcm.len - limit_samples
		master_wet_pcm = master_wet_pcm[start_idx..].clone()
	}

	mut pcm_data := []u8{}
	for sample_val in master_wet_pcm {
		mut sample_16 := i16(0)
		scaled_val := sample_val * volume
		if scaled_val > 32767.0 {
			sample_16 = 32767
		} else if scaled_val < -32768.0 {
			sample_16 = -32768
		} else {
			sample_16 = i16(scaled_val)
		}
		pcm_data << u8(sample_16)
		pcm_data << u8(sample_16 >> 8)
	}

	data_len := u32(pcm_data.len)
	header := make_wav_header(data_len, sample_rate)

	mut outfile := os.create(output_path) or {
		println('[!] Error: Could not create output file: ${err}')
		return
	}
	defer { outfile.close() }

	outfile.write(header) or { panic(err) }
	outfile.write(pcm_data) or { panic(err) }

	println('[+] Finished compiling! Saved to ${output_path}')
}
