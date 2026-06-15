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
	instructions  []ShaderInstruction
	delays        map[string]DelayLine
	prev_filter_l map[string]f64
	prev_filter_r map[string]f64
	vars_l        map[string]f64
	vars_r        map[string]f64
	comp_env_l    map[string]f64
	comp_env_r    map[string]f64
	svf_ic1_l     map[string]f64
	svf_ic2_l     map[string]f64
	svf_ic1_r     map[string]f64
	svf_ic2_r     map[string]f64
	reverb_buf_l  map[string][][]f64
	reverb_buf_r  map[string][][]f64
	reverb_idx_l  map[string][]int
	reverb_idx_r  map[string][]int
	chorus_buf_l  map[string][]f64
	chorus_buf_r  map[string][]f64
	chorus_idx    map[string]int
}

struct FastMixPair {
	is_var bool
	var_id int
	val    f64
	weight f64
}

struct FastArg {
	is_var bool
	var_id int
	val    f64
}

struct FastInstruction {
	op         string
	out_var_id int
	args       []FastArg
	mix_pairs  []FastMixPair
	str_args   []string
}

struct FastDelayLine {
mut:
	buffer_l  []f64
	buffer_r  []f64
	write_idx int
	feedback  f64
}

struct FastAudioShader {
	name string
mut:
	instructions  []FastInstruction
	var_to_id     map[string]int
	num_vars      int
	vars_l        []f64
	vars_r        []f64
	delays        []FastDelayLine
	prev_filter_l []f64
	prev_filter_r []f64
	comp_env_l    []f64
	comp_env_r    []f64
	svf_ic1_l     []f64
	svf_ic2_l     []f64
	svf_ic1_r     []f64
	svf_ic2_r     []f64
	reverb_buf_l  [][][]f64
	reverb_buf_r  [][][]f64
	reverb_idx_l  [][]int
	reverb_idx_r  [][]int
	chorus_buf_l  [][]f64
	chorus_buf_r  [][]f64
	chorus_idx    []int
	reverse_buf_l [][]f64
	reverse_buf_r [][]f64
	reverse_idx   []int
}

struct RenderRange {
	start_sec f64
	end_sec   f64
}

struct Command {
	line_num   int
	cmd_type   string
	note       string
	duration_ms int
	wave_type  string
	loop_count int
mut:
	start_ms      int
	end_ms        int
	is_slice      bool
	effects_chain []string
	velocity      f64 = 1.0
}

struct LoopState {
	start_ip     int
	total_count  int
mut:
	current_iter int
}

fn note_to_freq(note string, base_pitch f64) f64 {
	if note == 'REST' || note == 'P' || note == 'rest' || note == 'p' {
		return 0.0
	}
	if note.len == 0 {
		return 0.0
	}
	
	mut is_num := true
	for c in note {
		if c < `0` || c > `9` {
			is_num = false
			break
		}
	}
	if is_num {
		midi_val := note.int()
		semitones := midi_val - 69
		return base_pitch * math.pow(2.0, f64(semitones) / 12.0)
	}
	
	upper_note := note.to_upper()
	note_names := ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

	mut name := upper_note[0..1]
	mut octave_str := upper_note[1..]

	if upper_note.len > 2 && (upper_note[1] == `#` || upper_note[1] == `B`) {
		name = upper_note[0..2]
		octave_str = upper_note[2..]
	}

	if name == 'DB' {
		name = 'C#'
	} else if name == 'EB' {
		name = 'D#'
	} else if name == 'GB' {
		name = 'F#'
	} else if name == 'AB' {
		name = 'G#'
	} else if name == 'BB' {
		name = 'A#'
	}

	note_idx := note_names.index(name)
	if note_idx == -1 {
		return 0.0
	}

	octave := octave_str.int()
	semitones := (octave - 4) * 12 + (note_idx - 9)
	return base_pitch * math.pow(2.0, f64(semitones) / 12.0)
}

fn note_to_semitone(note string) int {
	if note.len == 0 {
		return 0
	}
	
	mut is_num := true
	for c in note {
		if c < `0` || c > `9` {
			is_num = false
			break
		}
	}
	if is_num {
		return note.int() - 69
	}

	upper_note := note.to_upper()
	note_names := ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
	mut name := upper_note[0..1]
	mut octave_str := upper_note[1..]

	if upper_note.len > 2 && (upper_note[1] == `#` || upper_note[1] == `B`) {
		name = upper_note[0..2]
		octave_str = upper_note[2..]
	}

	if name == 'DB' {
		name = 'C#'
	} else if name == 'EB' {
		name = 'D#'
	} else if name == 'GB' {
		name = 'F#'
	} else if name == 'AB' {
		name = 'G#'
	} else if name == 'BB' {
		name = 'A#'
	}

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
		return WavSample{
			success: false
		}
	}
	if data.len < 44 {
		println('[!] Error: File ${path} is too small to be a valid WAV.')
		return WavSample{
			success: false
		}
	}
	if data[0] != `R` || data[1] != `I` || data[2] != `F` || data[3] != `F` {
		println('[!] Error: File ${path} is not a valid RIFF/WAV.')
		return WavSample{
			success: false
		}
	}
	if data[8] != `W` || data[9] != `A` || data[10] != `V` || data[11] != `E` {
		println('[!] Error: File ${path} is not a valid WAVE file.')
		return WavSample{
			success: false
		}
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
		return WavSample{
			success: false
		}
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
		return WavSample{
			success: false
		}
	}

	return WavSample{
		samples: samples
		sample_rate: sample_rate
		success: true
	}
}

fn compile_shader(sh AudioShader) FastAudioShader {
	mut var_to_id := map[string]int{}
	mut next_id := 0

	var_to_id['x'] = 0
	var_to_id['y'] = 1
	next_id = 2

	for inst in sh.instructions {
		if inst.out_var !in var_to_id {
			var_to_id[inst.out_var] = next_id
			next_id++
		}
		for arg in inst.args {
			if arg.len > 0 && ((arg[0] >= `a` && arg[0] <= `z`) || (arg[0] >= `A` && arg[0] <= `Z`)) {
				if arg !in ['lowpass', 'highpass', 'bandpass', 'notch', 'tanh', 'hard', 'soft',
					'fold', 'tremolo', 'ring', 'a', 'e', 'i', 'o', 'u'] {
					if arg !in var_to_id {
						var_to_id[arg] = next_id
						next_id++
					}
				}
			}
		}
	}

	mut fast_instructions := []FastInstruction{}

	for inst in sh.instructions {
		out_id := var_to_id[inst.out_var]
		mut args := []FastArg{}
		mut mix_pairs := []FastMixPair{}
		mut str_args := []string{}

		if inst.op == 'mix' {
			mut i := 0
			for i < inst.args.len - 1 {
				var_name := inst.args[i]
				weight := inst.args[i + 1].f64()
				is_var := (var_name[0] >= `a` && var_name[0] <= `z`) || (var_name[0] >= `A` && var_name[0] <= `Z`)
				mut var_id := -1
				mut val := 0.0
				if is_var {
					var_id = var_to_id[var_name]
				} else {
					val = var_name.f64()
				}
				mix_pairs << FastMixPair{
					is_var: is_var
					var_id: var_id
					val: val
					weight: weight
				}
				i += 2
			}
		} else {
			for arg in inst.args {
				is_alpha := arg.len > 0 && ((arg[0] >= `a` && arg[0] <= `z`) || (arg[0] >= `A` && arg[0] <= `Z`))
				is_keyword := arg in ['lowpass', 'highpass', 'bandpass', 'notch', 'tanh', 'hard',
					'soft', 'fold', 'tremolo', 'ring', 'a', 'e', 'i', 'o', 'u']

				if is_alpha && !is_keyword {
					var_id := var_to_id[arg]
					args << FastArg{
						is_var: true
						var_id: var_id
						val: 0.0
					}
				} else if is_keyword {
					str_args << arg
				} else {
					args << FastArg{
						is_var: false
						var_id: -1
						val: arg.f64()
					}
				}
			}
		}

		fast_instructions << FastInstruction{
			op: inst.op
			out_var_id: out_id
			args: args
			mix_pairs: mix_pairs
			str_args: str_args
		}
	}

	mut vars_l := []f64{len: next_id, init: 0.0}
	mut vars_r := []f64{len: next_id, init: 0.0}
	mut prev_filter_l := []f64{len: next_id * 20, init: 0.0}
	mut prev_filter_r := []f64{len: next_id * 20, init: 0.0}
	mut comp_env_l := []f64{len: next_id, init: 0.0}
	mut comp_env_r := []f64{len: next_id, init: 0.0}
	mut svf_ic1_l := []f64{len: next_id * 20, init: 0.0}
	mut svf_ic2_l := []f64{len: next_id * 20, init: 0.0}
	mut svf_ic1_r := []f64{len: next_id * 20, init: 0.0}
	mut svf_ic2_r := []f64{len: next_id * 20, init: 0.0}

	mut delays := []FastDelayLine{len: next_id}
	for name, dl in sh.delays {
		id := var_to_id[name]
		delays[id] = FastDelayLine{
			buffer_l: dl.buffer_l.clone()
			buffer_r: dl.buffer_r.clone()
			write_idx: dl.write_idx
			feedback: dl.feedback
		}
	}

	return FastAudioShader{
		name: sh.name
		instructions: fast_instructions
		var_to_id: var_to_id
		num_vars: next_id
		vars_l: vars_l
		vars_r: vars_r
		delays: delays
		prev_filter_l: prev_filter_l
		prev_filter_r: prev_filter_r
		comp_env_l: comp_env_l
		comp_env_r: comp_env_r
		svf_ic1_l: svf_ic1_l
		svf_ic2_l: svf_ic2_l
		svf_ic1_r: svf_ic1_r
		svf_ic2_r: svf_ic2_r
		reverb_buf_l: [][][]f64{len: next_id}
		reverb_buf_r: [][][]f64{len: next_id}
		reverb_idx_l: [][]int{len: next_id}
		reverb_idx_r: [][]int{len: next_id}
		chorus_buf_l: [][]f64{len: next_id}
		chorus_buf_r: [][]f64{len: next_id}
		chorus_idx: []int{len: next_id, init: 0}
		reverse_buf_l: [][]f64{len: next_id}
		reverse_buf_r: [][]f64{len: next_id}
		reverse_idx: []int{len: next_id, init: 0}
	}
}

fn clone_fast_shaders(shaders map[string]FastAudioShader) map[string]FastAudioShader {
	mut cloned := map[string]FastAudioShader{}
	for name, sh in shaders {
		mut cloned_delays := []FastDelayLine{len: sh.delays.len}
		for d_idx, dl in sh.delays {
			cloned_delays[d_idx] = FastDelayLine{
				buffer_l: dl.buffer_l.clone()
				buffer_r: dl.buffer_r.clone()
				write_idx: dl.write_idx
				feedback: dl.feedback
			}
		}

		mut cloned_reverb_buf_l := [][][]f64{len: sh.reverb_buf_l.len}
		mut cloned_reverb_buf_r := [][][]f64{len: sh.reverb_buf_r.len}
		for i_id in 0 .. sh.reverb_buf_l.len {
			mut rbl := [][]f64{len: sh.reverb_buf_l[i_id].len}
			for i_comb in 0 .. sh.reverb_buf_l[i_id].len {
				rbl[i_comb] = sh.reverb_buf_l[i_id][i_comb].clone()
			}
			cloned_reverb_buf_l[i_id] = rbl

			mut rbr := [][]f64{len: sh.reverb_buf_r[i_id].len}
			for i_comb in 0 .. sh.reverb_buf_r[i_id].len {
				rbr[i_comb] = sh.reverb_buf_r[i_id][i_comb].clone()
			}
			cloned_reverb_buf_r[i_id] = rbr
		}

		mut cloned_reverb_idx_l := [][]int{len: sh.reverb_idx_l.len}
		mut cloned_reverb_idx_r := [][]int{len: sh.reverb_idx_r.len}
		for i_id in 0 .. sh.reverb_idx_l.len {
			cloned_reverb_idx_l[i_id] = sh.reverb_idx_l[i_id].clone()
			cloned_reverb_idx_r[i_id] = sh.reverb_idx_r[i_id].clone()
		}

		mut cloned_chorus_buf_l := [][]f64{len: sh.chorus_buf_l.len}
		mut cloned_chorus_buf_r := [][]f64{len: sh.chorus_buf_r.len}
		for i_id in 0 .. sh.chorus_buf_l.len {
			cloned_chorus_buf_l[i_id] = sh.chorus_buf_l[i_id].clone()
			cloned_chorus_buf_r[i_id] = sh.chorus_buf_r[i_id].clone()
		}

		mut cloned_reverse_buf_l := [][]f64{len: sh.reverse_buf_l.len}
		mut cloned_reverse_buf_r := [][]f64{len: sh.reverse_buf_r.len}
		for i_id in 0 .. sh.reverse_buf_l.len {
			cloned_reverse_buf_l[i_id] = sh.reverse_buf_l[i_id].clone()
			cloned_reverse_buf_r[i_id] = sh.reverse_buf_r[i_id].clone()
		}

		cloned[name] = FastAudioShader{
			name: sh.name
			instructions: sh.instructions.clone()
			var_to_id: sh.var_to_id.clone()
			num_vars: sh.num_vars
			vars_l: sh.vars_l.clone()
			vars_r: sh.vars_r.clone()
			delays: cloned_delays
			prev_filter_l: sh.prev_filter_l.clone()
			prev_filter_r: sh.prev_filter_r.clone()
			comp_env_l: sh.comp_env_l.clone()
			comp_env_r: sh.comp_env_r.clone()
			svf_ic1_l: sh.svf_ic1_l.clone()
			svf_ic2_l: sh.svf_ic2_l.clone()
			svf_ic1_r: sh.svf_ic1_r.clone()
			svf_ic2_r: sh.svf_ic2_r.clone()
			reverb_buf_l: cloned_reverb_buf_l
			reverb_buf_r: cloned_reverb_buf_r
			reverb_idx_l: cloned_reverb_idx_l
			reverb_idx_r: cloned_reverb_idx_r
			chorus_buf_l: cloned_chorus_buf_l
			chorus_buf_r: cloned_chorus_buf_r
			chorus_idx: sh.chorus_idx.clone()
			reverse_buf_l: cloned_reverse_buf_l
			reverse_buf_r: cloned_reverse_buf_r
			reverse_idx: sh.reverse_idx.clone()
		}
	}
	return cloned
}

fn apply_fast_shader(mut shader FastAudioShader, input_l f64, input_r f64, t f64) (f64, f64) {
	shader.vars_l[0] = input_l
	shader.vars_r[0] = input_r
	shader.vars_l[1] = input_l
	shader.vars_r[1] = input_r

	sample_rate := 44100.0
	num_vars := shader.num_vars

	for inst in shader.instructions {
		id := inst.out_var_id
		match inst.op {
			'delay' {
				mut dl := shader.delays[id]
				if dl.buffer_l.len > 0 {
					delay_l := dl.buffer_l[dl.write_idx]
					delay_r := dl.buffer_r[dl.write_idx]
					shader.vars_l[id] = delay_l
					shader.vars_r[id] = delay_r

					input_to_delay_l := shader.vars_l[0]
					input_to_delay_r := shader.vars_r[0]
					dl.buffer_l[dl.write_idx] = input_to_delay_l + delay_l * dl.feedback
					dl.buffer_r[dl.write_idx] = input_to_delay_r + delay_r * dl.feedback
					dl.write_idx = (dl.write_idx + 1) % dl.buffer_l.len
					shader.delays[id] = dl
				}
			}
			'reverse' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				block_size := if inst.args.len > 0 { int(inst.args[0].val) } else { 22050 }

				if shader.reverse_buf_l[id].len == 0 {
					shader.reverse_buf_l[id] = []f64{len: block_size * 2, init: 0.0}
					shader.reverse_buf_r[id] = []f64{len: block_size * 2, init: 0.0}
					shader.reverse_idx[id] = 0
				}

				mut buf_l := shader.reverse_buf_l[id]
				mut buf_r := shader.reverse_buf_r[id]
				mut idx := shader.reverse_idx[id]

				write_idx := idx
				buf_l[write_idx] = val_l
				buf_r[write_idx] = val_r

				write_block := idx / block_size
				read_block := 1 - write_block

				write_offset := idx % block_size
				read_offset := (block_size - 1) - write_offset
				read_idx := read_block * block_size + read_offset

				mut out_l := buf_l[read_idx]
				mut out_r := buf_r[read_idx]
				
				fade_samples := 350
				mut gain := 1.0
				if write_offset < fade_samples {
					gain = f64(write_offset) / f64(fade_samples)
				} else if write_offset > block_size - fade_samples {
					gain = f64(block_size - write_offset) / f64(fade_samples)
				}

				out_l *= gain
				out_r *= gain

				idx = (idx + 1) % (block_size * 2)

				shader.reverse_buf_l[id] = buf_l
				shader.reverse_buf_r[id] = buf_r
				shader.reverse_idx[id] = idx

				shader.vars_l[id] = out_l
				shader.vars_r[id] = out_r
			}
			'mix' {
				mut sum_l := 0.0
				mut sum_r := 0.0
				for pair in inst.mix_pairs {
					val_l := if pair.is_var { shader.vars_l[pair.var_id] } else { pair.val }
					val_r := if pair.is_var { shader.vars_r[pair.var_id] } else { pair.val }
					sum_l += val_l * pair.weight
					sum_r += val_r * pair.weight
				}
				shader.vars_l[id] = sum_l
				shader.vars_r[id] = sum_r
			}
			'saturate' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				sat_type := inst.str_args[0]
				mut sat_l := val_l
				mut sat_r := val_r
				match sat_type {
					'tanh' {
						sat_l = math.tanh(val_l)
						sat_r = math.tanh(val_r)
					}
					'hard' {
						if val_l > 1.0 {
							sat_l = 1.0
						} else if val_l < -1.0 {
							sat_l = -1.0
						}
						if val_r > 1.0 {
							sat_r = 1.0
						} else if val_r < -1.0 {
							sat_r = -1.0
						}
					}
					'soft' {
						if val_l > 1.0 {
							sat_l = 2.0 / 3.0
						} else if val_l < -1.0 {
							sat_l = -2.0 / 3.0
						} else {
							sat_l = val_l - (val_l * val_l * val_l) / 3.0
						}
						if val_r > 1.0 {
							sat_r = 2.0 / 3.0
						} else if val_r < -1.0 {
							sat_r = -2.0 / 3.0
						} else {
							sat_r = val_r - (val_r * val_r * val_r) / 3.0
						}
					}
					'fold' {
						sat_l = math.sin(val_l * math.pi * 0.5)
						sat_r = math.sin(val_r * math.pi * 0.5)
					}
					else {}
				}
				shader.vars_l[id] = sat_l
				shader.vars_r[id] = sat_r
			}
			'filter' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				filter_type := inst.str_args[0]
				cutoff := inst.args[0].val

				mut safe_cutoff := cutoff
				if safe_cutoff < 0.001 {
					safe_cutoff = 0.001
				}
				if safe_cutoff > 0.999 {
					safe_cutoff = 0.999
				}

				mut prev_l := shader.prev_filter_l[id]
				mut prev_r := shader.prev_filter_r[id]
				if filter_type == 'lowpass' {
					prev_l = prev_l + safe_cutoff * (val_l - prev_l)
					prev_r = prev_r + safe_cutoff * (val_r - prev_r)
					shader.vars_l[id] = prev_l
					shader.vars_r[id] = prev_r
				} else if filter_type == 'highpass' {
					prev_l = prev_l + safe_cutoff * (val_l - prev_l)
					prev_r = prev_r + safe_cutoff * (val_r - prev_r)
					shader.vars_l[id] = val_l - prev_l
					shader.vars_r[id] = val_r - prev_r
				}
				shader.prev_filter_l[id] = prev_l
				shader.prev_filter_r[id] = prev_r
			}
			'compressor' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				threshold_db := inst.args[0].val
				ratio := inst.args[1].val
				attack_ms := inst.args[2].val
				release_ms := inst.args[3].val
				makeup_db := inst.args[4].val

				t_att := math.exp(-1.0 / (sample_rate * (attack_ms / 1000.0)))
				t_rel := math.exp(-1.0 / (sample_rate * (release_ms / 1000.0)))

				mut env_l := shader.comp_env_l[id]
				mut env_r := shader.comp_env_r[id]

				abs_l := math.abs(val_l)
				abs_r := math.abs(val_r)

				env_l = if abs_l > env_l {
					t_att * env_l + (1.0 - t_att) * abs_l
				} else {
					t_rel * env_l + (1.0 - t_rel) * abs_l
				}
				env_r = if abs_r > env_r {
					t_att * env_r + (1.0 - t_att) * abs_r
				} else {
					t_rel * env_r + (1.0 - t_rel) * abs_r
				}

				shader.comp_env_l[id] = env_l
				shader.comp_env_r[id] = env_r

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

				shader.vars_l[id] = val_l * total_gain_l
				shader.vars_r[id] = val_r * total_gain_r
			}
			'svf' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				f_type := inst.str_args[0]
				cutoff := inst.args[0].val
				q := inst.args[1].val

				mut f := 2.0 * math.sin(math.pi * cutoff / sample_rate)
				if f < 0.001 {
					f = 0.001
				}
				if f > 0.99 {
					f = 0.99
				}
				d := 1.0 / q

				mut ic1_l := shader.svf_ic1_l[id]
				mut ic2_l := shader.svf_ic2_l[id]
				mut ic1_r := shader.svf_ic1_r[id]
				mut ic2_r := shader.svf_ic2_r[id]

				hp_l := val_l - ic2_l - d * ic1_l
				bp_l := ic1_l + f * hp_l
				lp_l := ic2_l + f * bp_l
				ic1_l = bp_l
				ic2_l = lp_l

				hp_r := val_r - ic2_r - d * ic1_r
				bp_r := ic1_r + f * hp_r
				lp_r := ic2_r + f * bp_r
				ic1_r = bp_r
				ic2_r = lp_r

				shader.svf_ic1_l[id] = ic1_l
				shader.svf_ic2_l[id] = ic2_l
				shader.svf_ic1_r[id] = ic1_r
				shader.svf_ic2_r[id] = ic2_r

				mut out_l := val_l
				mut out_r := val_r

				match f_type {
					'lowpass' { out_l, out_r = lp_l, lp_r }
					'highpass' { out_l, out_r = hp_l, hp_r }
					'bandpass' { out_l, out_r = bp_l, bp_r }
					'notch' { out_l, out_r = hp_l + lp_l, hp_r + lp_r }
					else {}
				}

				shader.vars_l[id] = out_l
				shader.vars_r[id] = out_r
			}
			'reverb' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				size := inst.args[0].val
				damp := inst.args[1].val
				wet := inst.args[2].val
				dry := inst.args[3].val

				comb_lens_l := [1116, 1188, 1277, 1356]
				comb_lens_r := [1213, 1134, 1301, 1267]

				if shader.reverb_buf_l[id].len == 0 {
					mut bl := [][]f64{}
					mut br := [][]f64{}
					for sz in comb_lens_l {
						bl << []f64{len: sz, init: 0.0}
					}
					for sz in comb_lens_r {
						br << []f64{len: sz, init: 0.0}
					}
					shader.reverb_buf_l[id] = bl
					shader.reverb_buf_r[id] = br
					shader.reverb_idx_l[id] = [0, 0, 0, 0]
					shader.reverb_idx_r[id] = [0, 0, 0, 0]
				}

				mut bufs_l := shader.reverb_buf_l[id]
				mut bufs_r := shader.reverb_buf_r[id]
				mut idxs_l := shader.reverb_idx_l[id]
				mut idxs_r := shader.reverb_idx_r[id]

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

				shader.reverb_buf_l[id] = bufs_l
				shader.reverb_buf_r[id] = bufs_r
				shader.reverb_idx_l[id] = idxs_l
				shader.reverb_idx_r[id] = idxs_r

				mixed_l := val_l * dry + (comb_sum_l * 0.25) * wet
				mixed_r := val_r * dry + (comb_sum_r * 0.25) * wet

				shader.vars_l[id] = mixed_l
				shader.vars_r[id] = mixed_r
			}
			'chorus' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				rate := inst.args[0].val
				depth := inst.args[1].val
				fb := inst.args[2].val
				mix := inst.args[3].val

				buf_size := 4410

				if shader.chorus_buf_l[id].len == 0 {
					shader.chorus_buf_l[id] = []f64{len: buf_size, init: 0.0}
					shader.chorus_buf_r[id] = []f64{len: buf_size, init: 0.0}
					shader.chorus_idx[id] = 0
				}

				mut c_buf_l := shader.chorus_buf_l[id]
				mut c_buf_r := shader.chorus_buf_r[id]
				mut c_idx := shader.chorus_idx[id]

				lfo := math.sin(2.0 * math.pi * rate * t)
				delay_samples := 220.0 + lfo * (depth * 44.1)

				mut read_ptr := math.fmod(f64(c_idx) - delay_samples + f64(buf_size),
					f64(buf_size))
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

				shader.chorus_buf_l[id] = c_buf_l
				shader.chorus_buf_r[id] = c_buf_r
				shader.chorus_idx[id] = c_idx

				shader.vars_l[id] = val_l * (1.0 - mix) + delayed_l * mix
				shader.vars_r[id] = val_r * (1.0 - mix) + delayed_r * mix
			}
			'exciter' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				cutoff := inst.args[0].val
				drive := inst.args[1].val
				mix := inst.args[2].val

				exc_idx := id + num_vars
				mut prev_l := shader.prev_filter_l[exc_idx]
				mut prev_r := shader.prev_filter_r[exc_idx]
				alpha := 2.0 * math.pi * cutoff / sample_rate

				prev_l = prev_l + alpha * (val_l - prev_l)
				prev_r = prev_r + alpha * (val_r - prev_r)

				shader.prev_filter_l[exc_idx] = prev_l
				shader.prev_filter_r[exc_idx] = prev_r

				hp_l := val_l - prev_l
				hp_r := val_r - prev_r

				sat_l := math.tanh(hp_l * drive)
				sat_r := math.tanh(hp_r * drive)

				shader.vars_l[id] = val_l + sat_l * mix
				shader.vars_r[id] = val_r + sat_r * mix
			}
			'wavefolder' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				gain := inst.args[0].val

				mut out_l := val_l * gain
				mut iter_l := 0
				for (out_l > 1.0 || out_l < -1.0) && iter_l < 100 {
					if out_l > 1.0 {
						out_l = 2.0 - out_l
					} else if out_l < -1.0 {
						out_l = -2.0 - out_l
					}
					iter_l++
				}
				if iter_l >= 100 {
					out_l = if out_l > 0 { 1.0 } else { -1.0 }
				}

				mut out_r := val_r * gain
				mut iter_r := 0
				for (out_r > 1.0 || out_r < -1.0) && iter_r < 100 {
					if out_r > 1.0 {
						out_r = 2.0 - out_r
					} else if out_r < -1.0 {
						out_r = -2.0 - out_r
					}
					iter_r++
				}
				if iter_r >= 100 {
					out_r = if out_r > 0 { 1.0 } else { -1.0 }
				}

				shader.vars_l[id] = out_l
				shader.vars_r[id] = out_r
			}
			'vowel' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				vow_char := inst.str_args[0]
				mix := inst.args[0].val

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
					offset_idx := id + num_vars * (1 + idx)
					mut f := 2.0 * math.sin(math.pi * freq / sample_rate)
					if f < 0.001 {
						f = 0.001
					}
					if f > 0.99 {
						f = 0.99
					}

					mut ic1_l := shader.svf_ic1_l[offset_idx]
					mut ic2_l := shader.svf_ic2_l[offset_idx]
					mut ic1_r := shader.svf_ic1_r[offset_idx]
					mut ic2_r := shader.svf_ic2_r[offset_idx]

					hp_l := val_l - ic2_l - d * ic1_l
					bp_l := ic1_l + f * hp_l
					lp_l := ic2_l + f * bp_l
					ic1_l = bp_l
					ic2_l = lp_l

					hp_r := val_r - ic2_r - d * ic1_r
					bp_r := ic1_r + f * hp_r
					lp_r := ic2_r + f * bp_r
					ic1_r = bp_r
					ic2_r = lp_r

					shader.svf_ic1_l[offset_idx] = ic1_l
					shader.svf_ic2_l[offset_idx] = ic2_l
					shader.svf_ic1_r[offset_idx] = ic1_r
					shader.svf_ic2_r[offset_idx] = ic2_r

					bp_sum_l += bp_l
					bp_sum_r += bp_r
				}

				out_l := val_l * (1.0 - mix) + (bp_sum_l * 2.5) * mix
				out_r := val_r * (1.0 - mix) + (bp_sum_r * 2.5) * mix

				shader.vars_l[id] = out_l
				shader.vars_r[id] = out_r
			}
			'phaser' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				rate := inst.args[0].val
				fb := inst.args[1].val
				mix := inst.args[2].val

				lfo := 0.5 + 0.5 * math.sin(2.0 * math.pi * rate * t)
				cutoff := 150.0 + lfo * 1550.0
				w0 := math.pi * cutoff / sample_rate
				a1 := (1.0 - math.tan(w0 * 0.5)) / (1.0 + math.tan(w0 * 0.5))

				fb_l_idx := id + num_vars * 1
				fb_r_idx := id + num_vars * 2

				fb_l := shader.prev_filter_l[fb_l_idx]
				fb_r := shader.prev_filter_r[fb_r_idx]

				mut ap_in_l := val_l + fb_l * fb
				mut ap_in_r := val_r + fb_r * fb

				for stage in 1 .. 5 {
					apx_l_idx := id + num_vars * (2 + stage)
					apy_l_idx := id + num_vars * (6 + stage)
					apx_r_idx := id + num_vars * (10 + stage)
					apy_r_idx := id + num_vars * (14 + stage)

					xp_l := shader.prev_filter_l[apx_l_idx]
					yp_l := shader.prev_filter_l[apy_l_idx]
					xp_r := shader.prev_filter_r[apx_r_idx]
					yp_r := shader.prev_filter_r[apy_r_idx]

					out_l := a1 * ap_in_l + xp_l - a1 * yp_l
					out_r := a1 * ap_in_r + xp_r - a1 * yp_r

					shader.prev_filter_l[apx_l_idx] = ap_in_l
					shader.prev_filter_l[apy_l_idx] = out_l
					shader.prev_filter_r[apx_r_idx] = ap_in_r
					shader.prev_filter_r[apy_r_idx] = out_r

					ap_in_l = out_l
					ap_in_r = out_r
				}

				shader.prev_filter_l[fb_l_idx] = ap_in_l
				shader.prev_filter_r[fb_r_idx] = ap_in_r

				shader.vars_l[id] = val_l * (1.0 - mix) + ap_in_l * mix
				shader.vars_r[id] = val_r * (1.0 - mix) + ap_in_r * mix
			}
			'ms_width' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				width := inst.args[0].val

				mid := (val_l + val_r) * 0.5
				side := (val_l - val_r) * 0.5 * width

				shader.vars_l[id] = mid + side
				shader.vars_r[id] = mid - side
			}
			'modulate' {
				mut in_val_l := shader.vars_l[0]
				mut in_val_r := shader.vars_r[0]
				mut mod_freq := 1.0
				mut depth := 0.5
				mut mod_type := 'tremolo'

				if inst.str_args.len > 0 {
					mod_type = inst.str_args[0]
				}

				if inst.args.len >= 3 {
					arg0 := inst.args[0]
					in_val_l = if arg0.is_var { shader.vars_l[arg0.var_id] } else { arg0.val }
					in_val_r = if arg0.is_var { shader.vars_r[arg0.var_id] } else { arg0.val }
					mod_freq = inst.args[1].val
					depth = inst.args[2].val
				} else if inst.args.len == 2 {
					in_val_l = shader.vars_l[id]
					in_val_r = shader.vars_r[id]
					mod_freq = inst.args[0].val
					depth = inst.args[1].val
				}

				mut mod_sig := 1.0
				if mod_type == 'tremolo' {
					mod_sig = 1.0 - depth + depth * math.sin(2.0 * math.pi * mod_freq * t)
				} else if mod_type == 'ring' {
					mod_sig = math.sin(2.0 * math.pi * mod_freq * t)
				}
				shader.vars_l[id] = in_val_l * mod_sig
				shader.vars_r[id] = in_val_r * mod_sig
			}
			'bitcrush' {
				val_l := shader.vars_l[id]
				val_r := shader.vars_r[id]
				bits := inst.args[0].val
				steps := math.pow(2.0, bits)
				shader.vars_l[id] = math.floor(val_l * steps + 0.5) / steps
				shader.vars_r[id] = math.floor(val_r * steps + 0.5) / steps
			}
			'pan' {
				pan_val := inst.args[0].val
				angle := (pan_val + 1.0) * math.pi / 4.0
				left_gain := math.cos(angle)
				right_gain := math.sin(angle)
				shader.vars_l[id] = shader.vars_l[id] * left_gain
				shader.vars_r[id] = shader.vars_r[id] * right_gain
			}
			'autopan' {
				freq_hz := inst.args[0].val
				pan_sweep := math.sin(2.0 * math.pi * freq_hz * t)
				angle := (pan_sweep + 1.0) * math.pi / 4.0
				left_gain := math.cos(angle)
				right_gain := math.sin(angle)
				shader.vars_l[id] = shader.vars_l[id] * left_gain
				shader.vars_r[id] = shader.vars_r[id] * right_gain
			}
			else {}
		}
		if id == 0 || id == 1 {
			shader.vars_l[0] = shader.vars_l[id]
			shader.vars_r[0] = shader.vars_r[id]
		}
	}
	return shader.vars_l[1], shader.vars_r[1]
}

fn interpret_track(commands []Command, single_samples map[string]SingleSampleInstrument, multi_samples map[string]MultiSampleInstrument, custom_synths map[string]CustomSynth, active_shaders map[string]FastAudioShader, track_effects []string, sample_rate u32, max_samples_limit int, base_pitch f64) []f64 {
	mut local_shaders := clone_fast_shaders(active_shaders)
	dry_pcm := interpret_track_mut(commands, single_samples, multi_samples, custom_synths, mut
		local_shaders, sample_rate, max_samples_limit, base_pitch)

	if track_effects.len == 0 {
		return dry_pcm
	}

	mut processed_pcm := []f64{cap: dry_pcm.len}

	mut active_fx := []FastAudioShader{}
	for fx_name in track_effects {
		if fx_name in local_shaders {
			active_fx << local_shaders[fx_name]
		}
	}

	mut i := 0
	for i < dry_pcm.len - 1 {
		t := f64(i / 2) / f64(sample_rate)
		mut left_val := dry_pcm[i]
		mut right_val := dry_pcm[i + 1]
		for mut fx in active_fx {
			left_val, right_val = apply_fast_shader(mut fx, left_val, right_val, t)
		}
		processed_pcm << left_val
		processed_pcm << right_val
		i += 2
	}
	return processed_pcm
}

fn interpret_track_mut(commands []Command, single_samples map[string]SingleSampleInstrument, multi_samples map[string]MultiSampleInstrument, custom_synths map[string]CustomSynth, mut active_shaders map[string]FastAudioShader, sample_rate u32, max_samples_limit int, base_pitch f64) []f64 {
	mut track_pcm := []f64{cap: 1000000}
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
				freq := note_to_freq(cmd.note, base_pitch)
				duration_sec := f64(cmd.duration_ms) / 1000.0
				num_samples := int(f64(sample_rate) * duration_sec)

				mut generated_pcm := []f64{cap: num_samples}

				if cmd.wave_type in single_samples {
					inst := single_samples[cmd.wave_type]
					base_freq := note_to_freq(inst.base_note, base_pitch)
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
							pos := start_src_idx +
								f64(i) * ratio * (f64(inst.sample.sample_rate) / f64(sample_rate))
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
						sample_val *= cmd.velocity
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
						base_freq := note_to_freq(best_note, base_pitch)
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
								pos := start_src_idx +
									f64(i) * ratio * (f64(best_sample.sample_rate) / f64(sample_rate))
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
							sample_val *= cmd.velocity
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
								release_progress := (t - (duration_sec - sr_val)) / (sr_val +
									0.0001)
								adsr_env = s_level * (1.0 - release_progress)
							}
							if adsr_env < 0.0 {
								adsr_env = 0.0
							}
							if adsr_env > 1.0 {
								adsr_env = 1.0
							}

							mut lfo_vol := 1.0
							if synth.lfo_freq > 0.0 {
								lfo_vol = 0.7 +
									0.3 * math.sin(2.0 * math.pi * synth.lfo_freq * t)
							}

							mut fm_index := 0.0
							if synth.fm_ratio > 0.0 {
								fm_index = 2.0 + 1.5 * math.sin(2.0 * math.pi * 0.15 * t)
							}

							mut signal := 0.0
							voices := if synth.detune_voices > 0 {
								synth.detune_voices
							} else {
								1
							}

							for v_idx in 0 .. voices {
								mut detune_mult := 1.0
								if voices > 1 {
									offset := f64(v_idx) - f64(voices - 1) / 2.0
									detune_mult = 1.0 + offset * 0.006
								}

								v_freq := freq * detune_mult
								dt := v_freq / sample_rate

								mut voice_val := 0.0
								
								t_frac := math.fmod(v_freq * t, 1.0)
								mut positive_t_frac := t_frac
								if positive_t_frac < 0.0 {
									positive_t_frac += 1.0
								}

								match synth.osc_type {
									'sawtooth' {
										naive := 2.0 * positive_t_frac - 1.0
										mut blep_corr := 0.0
										if positive_t_frac < dt {
											t_val := positive_t_frac / dt
											blep_corr = t_val + t_val - t_val * t_val - 1.0
										} else if positive_t_frac > 1.0 - dt {
											t_val := (positive_t_frac - 1.0) / dt
											blep_corr = t_val * t_val + t_val + t_val + 1.0
										}
										voice_val = naive - blep_corr
									}
									'square' {
										naive := if positive_t_frac < 0.5 { 1.0 } else { -1.0 }
										
										mut corr0 := 0.0
										if positive_t_frac < dt {
											t_val := positive_t_frac / dt
											corr0 = t_val + t_val - t_val * t_val - 1.0
										} else if positive_t_frac > 1.0 - dt {
											t_val := (positive_t_frac - 1.0) / dt
											corr0 = t_val * t_val + t_val + t_val + 1.0
										}

										t_frac_shifted := math.fmod(positive_t_frac + 0.5, 1.0)
										mut corr1 := 0.0
										if t_frac_shifted < dt {
											t_val := t_frac_shifted / dt
											corr1 = t_val + t_val - t_val * t_val - 1.0
										} else if t_frac_shifted > 1.0 - dt {
											t_val := (t_frac_shifted - 1.0) / dt
											corr1 = t_val * t_val + t_val + t_val + 1.0
										}
										voice_val = naive + corr0 - corr1
									}
									'triangle' {
										voice_val = 2.0 * math.abs(2.0 * (positive_t_frac - math.floor(0.5 + positive_t_frac))) - 1.0
									}
									'noise' {
										mut seed := u32(123456789 + i + v_idx * 99)
										seed = seed * 1664525 + 1013904223
										voice_val = f64(int(seed) % 2000) / 1000.0 - 1.0
									}
									else {
										mut phase := 2.0 * math.pi * v_freq * t
										if synth.fm_ratio > 0.0 {
											modulator_phase := 2.0 * math.pi * (v_freq * synth.fm_ratio) * t
											phase += fm_index * math.sin(modulator_phase)
										}
										voice_val = math.sin(phase)
									}
								}
								signal += voice_val
							}
							sample_val = signal / f64(voices)

							if synth.filter_cutoff > 0.0 {
								alpha := synth.filter_cutoff * (1.2 +
									0.8 * math.sin(2.0 * math.pi * 0.08 * t))
								mut clamped_alpha := alpha
								if clamped_alpha < 0.001 {
									clamped_alpha = 0.001
								}
								if clamped_alpha > 0.99 {
									clamped_alpha = 0.99
								}
								prev_filter_val = prev_filter_val +
									clamped_alpha * (sample_val - prev_filter_val)
								sample_val = prev_filter_val
							}

							sample_val *= lfo_vol * adsr_env
						}
						sample_val *= cmd.velocity
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
									sample_val = (if math.sin(angle) >= 0.0 {
										1.0
									} else {
										-1.0
									}) * env
								}
								'sawtooth' {
									fade_samples := int(0.01 * f64(sample_rate))
									mut env := 1.0
									if i < fade_samples {
										env = f64(i) / f64(fade_samples)
									} else if i > num_samples - fade_samples {
										env = f64(num_samples - i) / f64(fade_samples)
									}
									sample_val = (2.0 *
										(angle / (2.0 * math.pi) -
										math.floor(0.5 + angle / (2.0 * math.pi)))) * env
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
									signal += 0.6 * math.sin(2.0 * math.pi * (2.0 * freq) * t) *
										math.exp(-12.0 * progress)
									signal += 0.4 * math.sin(2.0 * math.pi * (3.0 * freq) * t) *
										math.exp(-18.0 * progress)
									signal += 0.2 * math.sin(2.0 * math.pi * (4.0 * freq) * t) *
										math.exp(-24.0 * progress)
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
						sample_val *= cmd.velocity
						generated_pcm << sample_val
					}
				}

				mut active_fx := []FastAudioShader{}
				for fx_name in cmd.effects_chain {
					if fx_name in active_shaders {
						active_fx << active_shaders[fx_name]
					}
				}

				for i, sample_val in generated_pcm {
					t := f64(i) / f64(sample_rate)
					mut left_val := sample_val
					mut right_val := sample_val
					for mut fx in active_fx {
						left_val, right_val = apply_fast_shader(mut fx, left_val, right_val,
							t)
					}
					track_pcm << left_val
					track_pcm << right_val
				}

				if max_samples_limit > 0 && (track_pcm.len / 2) >= max_samples_limit {
					track_pcm = track_pcm[0..max_samples_limit * 2].clone()
					return track_pcm
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
	mut base_pitch := 440.0
	mut commands := []Command{}

	mut current_define_name := ''
	mut define_depth := 0
	mut define_commands := []Command{}
	mut define_start_line := 0

	mut current_fx_name := ''
	mut fx_instructions := []ShaderInstruction{}
	mut fx_delays := map[string]DelayLine{}

	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') {
			continue
		}

		parts := trimmed.split(' ')
		mut parsed_parts := []string{}
		for p in parts {
			if p.trim_space() != '' {
				parsed_parts << p.trim_space()
			}
		}
		if parsed_parts.len == 0 {
			continue
		}

		first_token := parsed_parts[0].to_upper()

		if first_token == 'DEBUG_MODE' {
			if parsed_parts.len > 1 && parsed_parts[1].to_upper() == 'ON' {
				debug_enabled = true
			}
			continue
		}

		if first_token == 'BASE_PITCH' {
			if parsed_parts.len > 1 {
				base_pitch = parsed_parts[1].f64()
			}
			continue
		}

		if first_token == 'RENDER_RANGE' {
			if parsed_parts.len > 1 {
				range_parts := parsed_parts[1].split('-')
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
			if parsed_parts.len > 1 {
				master_volume_factor = parsed_parts[1].f64()
			}
			continue
		}

		if first_token == 'MASTER_EFFECT' {
			if parsed_parts.len > 1 {
				master_effects = parsed_parts[1..].clone()
			}
			continue
		}

		if first_token == 'DEFINE_EFFECT' {
			if parsed_parts.len < 2 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE_EFFECT needs a name')
				return
			}
			current_fx_name = parsed_parts[1].to_lower()
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
						if arg.len > 0 && ((arg[0] >= `a` && arg[0] <= `z`) ||
							(arg[0] >= `A` && arg[0] <= `Z`)) {
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

			op := parsed_parts[0].to_lower()
			if op == 'delay' {
				name := parsed_parts[1]
				size := parsed_parts[2].int()
				feedback := parsed_parts[3].f64()
				fx_delays[name] = DelayLine{
					buffer_l: []f64{len: size, init: 0.0}
					buffer_r: []f64{len: size, init: 0.0}
					write_idx: 0
					feedback: feedback
				}
				fx_instructions << ShaderInstruction{
					op: 'delay'
					out_var: name
					args: parsed_parts[1..].clone()
				}
			} else {
				out_var := parsed_parts[1]
				args := parsed_parts[2..].clone()
				fx_instructions << ShaderInstruction{
					op: op
					out_var: out_var
					args: args
				}
			}
			continue
		}

		if first_token == 'DEFINE_SYNTH' {
			if parsed_parts.len < 7 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE_SYNTH requires at least 6 arguments')
				return
			}
			name := parsed_parts[1].to_lower()
			osc_type := parsed_parts[2].to_lower()
			detune_voices := parsed_parts[3].int()
			lfo_freq := parsed_parts[4].f64()
			fm_ratio := parsed_parts[5].f64()
			filter_cutoff := parsed_parts[6].f64()

			mut attack_ms := 10
			mut decay_ms := 10
			mut sustain_level := 1.0
			mut release_ms := 10

			if parsed_parts.len >= 11 {
				attack_ms = parsed_parts[7].int()
				decay_ms = parsed_parts[8].int()
				sustain_level = parsed_parts[9].f64()
				release_ms = parsed_parts[10].int()
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
			if parsed_parts.len < 2 {
				println('[!] Syntax Error (line ${i + 1}): DEFINE requires a track name')
				return
			}
			track_def := parsed_parts[1].to_lower()
			sub_parts := track_def.split('|')
			current_define_name = sub_parts[0]
			define_depth = 1
			define_commands = []Command{}
			define_start_line = i + 1
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
				count := if parsed_parts.len > 1 { parsed_parts[1].int() } else { 1 }
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
				if parsed_parts.len < 2 {
					continue
				}
				note := parsed_parts[0]
				duration_str := parsed_parts[1]
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
				if parsed_parts.len >= 3 {
					instrument_part := parsed_parts[2].to_lower()
					sub_parts := instrument_part.split('|')
					wave_type = sub_parts[0]
					if sub_parts.len > 1 {
						effects_chain = sub_parts[1..].clone()
					}
				}

				mut velocity := 1.0
				if parsed_parts.len >= 4 {
					velocity = parsed_parts[3].f64()
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
					velocity: velocity
				}
			}
			continue
		}

		if first_token == 'LOAD_SAMPLE' {
			if parsed_parts.len < 4 {
				continue
			}
			name := parsed_parts[1].to_lower()
			path := parsed_parts[2]
			base_note := parsed_parts[3]
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
			if parsed_parts.len < 2 {
				continue
			}
			name := parsed_parts[1].to_lower()
			multi_samples[name] = MultiSampleInstrument{
				name: name
				samples: map[string]WavSample{}
			}
		} else if first_token == 'ADD_SAMPLE' {
			if parsed_parts.len < 4 {
				continue
			}
			inst_name := parsed_parts[1].to_lower()
			note_name := parsed_parts[2]
			path := parsed_parts[3]
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
				wave_type: parsed_parts[1..].join(' ').to_lower()
			}
		} else if first_token == 'LOOP' {
			count := if parsed_parts.len > 1 { parsed_parts[1].int() } else { 1 }
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
			if parsed_parts.len < 2 {
				continue
			}
			note := parsed_parts[0]
			duration_str := parsed_parts[1]
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
			if parsed_parts.len >= 3 {
				instrument_part := parsed_parts[2].to_lower()
				sub_parts := instrument_part.split('|')
				wave_type = sub_parts[0]
				if sub_parts.len > 1 {
					effects_chain = sub_parts[1..].clone()
				}
			}

			mut velocity := 1.0
			if parsed_parts.len >= 4 {
				velocity = parsed_parts[3].f64()
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
				velocity: velocity
			}
		}
	}

	if current_define_name != '' {
		println('[!] Compilation Error: DEFINE block "${current_define_name}" (opened at line ${define_start_line}) was never closed. Did you forget an "END"?')
		return
	}

	sample_rate := u32(44100)

	mut max_samples_limit := -1
	if has_slice_first {
		max_samples_limit = int(slice_first_secs * f64(sample_rate))
	}

	println('[*] Reference Base Pitch: ${base_pitch} Hz')
	println('[*] Compiling audio shaders for DSP rendering...')
	mut fast_active_shaders := map[string]FastAudioShader{}
	for name, sh in active_shaders {
		fast_active_shaders[name] = compile_shader(sh)
	}

	mut master_dry_pcm := []f64{cap: 10000000}

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
						threads << spawn interpret_track(track_cmds, single_samples,
							multi_samples, custom_synths, fast_active_shaders, fx,
							sample_rate, max_samples_limit, base_pitch)
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

				if max_samples_limit > 0 && (master_dry_pcm.len / 2) >= max_samples_limit {
					master_dry_pcm = master_dry_pcm[0..max_samples_limit * 2].clone()
					break
				}
				ip++
			}
			'note' {
				res := interpret_track_mut([cmd], single_samples, multi_samples, custom_synths, mut
					fast_active_shaders, sample_rate, max_samples_limit, base_pitch)
				for val in res {
					master_dry_pcm << val
				}

				if max_samples_limit > 0 && (master_dry_pcm.len / 2) >= max_samples_limit {
					master_dry_pcm = master_dry_pcm[0..max_samples_limit * 2].clone()
					break
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
		mut active_master_fx := []FastAudioShader{}
		for fx_name in master_effects {
			if fx_name in fast_active_shaders {
				active_master_fx << fast_active_shaders[fx_name]
			}
		}

		mut k := 0
		for k < master_dry_pcm.len - 1 {
			t := f64(k / 2) / f64(sample_rate)
			mut left_val := master_dry_pcm[k]
			mut right_val := master_dry_pcm[k + 1]
			for mut fx in active_master_fx {
				left_val, right_val = apply_fast_shader(mut fx, left_val, right_val, t)
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
	
	mut max_peak := 0.0
	for sample_val in master_wet_pcm {
		abs_val := math.abs(sample_val)
		if abs_val > max_peak {
			max_peak = abs_val
		}
	}

	mut norm_factor := 1.0
	if max_peak > 0.0 {
		norm_factor = (0.95 * master_volume_factor) / max_peak
	}
	println('[*] Normalizing audio peak... (Max absolute peak found: ${max_peak:.4f}, Applied Gain: ${norm_factor:.2f}x)')

	mut pcm_data := []u8{}
	for sample_val in master_wet_pcm {
		mut sample_16 := i16(0)
		scaled_val := sample_val * norm_factor * 32767.0
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
		println('    Please check if the output directory exists and is writable.')
		return
	}
	defer { outfile.close() }

	outfile.write(header) or { panic(err) }
	outfile.write(pcm_data) or { panic(err) }

	println('[+] Finished compiling! Saved to ${output_path}')
}
