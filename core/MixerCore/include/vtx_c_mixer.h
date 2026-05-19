#ifndef VTX_C_MIXER_H
#define VTX_C_MIXER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTX_C_MIXER_DEFAULT_SAMPLE_RATE 44100.0
#define VTX_C_MIXER_DEFAULT_CHANNEL_COUNT 2u

// Fixed voice storage for the offline C mixer path.
// Scheduled and active voices currently share this deterministic preallocated pool.
// Rendering uses this storage and does not allocate in the render call.
#define VTX_C_MIXER_MAX_VOICES 256u
#define VTX_C_MIXER_MAX_SCHEDULED_VOICES VTX_C_MIXER_MAX_VOICES
#define VTX_C_MIXER_MAX_ACTIVE_VOICES VTX_C_MIXER_MAX_VOICES

// Fixed storage for offline caller-scheduled voice gain/pan updates.
// These are generic mixer automation events; callers own any tracker-specific decoding.
#define VTX_C_MIXER_MAX_VOICE_STATE_EVENTS 4096u

// Fixed deterministic dezipper for offline gain/pan update events.
// At 44.1 kHz this is roughly 0.73 ms, short enough to avoid changing tracker
// timing while reducing single-frame gain/pan discontinuities.
#define VTX_C_MIXER_GAIN_PAN_UPDATE_RAMP_FRAMES 32u

// Synthetic offline envelopes use copied fixed-size point storage. XM instruments are
// not wired into this C-backed path yet.
#define VTX_C_MIXER_MAX_ENVELOPE_POINTS 12u

typedef enum {
    VTX_C_MIXER_STATUS_OK = 0,
    VTX_C_MIXER_STATUS_INVALID_ARGUMENT = 1,
    VTX_C_MIXER_STATUS_VOICE_CAPACITY_EXCEEDED = 2,
} VTXCMixerStatus;

typedef enum {
    VTX_C_MIXER_LOOP_NONE = 0,
    VTX_C_MIXER_LOOP_FORWARD = 1,
    VTX_C_MIXER_LOOP_PING_PONG = 2,
} VTXCMixerLoopMode;

typedef struct {
    double sample_rate;
    uint32_t channel_count;
} VTXCMixerConfig;

typedef struct {
    uint32_t position_frame;
    float value;
} VTXCMixerEnvelopePoint;

typedef struct {
    int active;
    float start;
    float target;
    uint32_t total_frames;
    uint32_t position_frame;
} VTXCMixerValueRampRuntimeState;

typedef struct {
    const VTXCMixerEnvelopePoint *points;
    uint32_t point_count;
    int sustain_enabled;
    uint32_t sustain_frame;
    int loop_enabled;
    uint32_t loop_start_frame;
    uint32_t loop_end_frame;
} VTXCMixerEnvelope;

typedef struct {
    VTXCMixerEnvelopePoint points[VTX_C_MIXER_MAX_ENVELOPE_POINTS];
    uint32_t point_count;
    uint32_t position_frame;
    int sustain_enabled;
    uint32_t sustain_frame;
    int loop_enabled;
    uint32_t loop_start_frame;
    uint32_t loop_end_frame;
    int enabled;
} VTXCMixerEnvelopeState;

typedef struct {
    float *sample_pcm;
    uint32_t sample_frame_count;
    uint32_t initial_sample_frame;
    double sample_position;
    double initial_sample_step;
    double sample_step;
    uint64_t scheduled_start_frame;
    float initial_gain;
    float initial_pan;
    float gain;
    float pan;
    int gain_ramp_active;
    float gain_ramp_start;
    float gain_ramp_target;
    uint32_t gain_ramp_total_frames;
    uint32_t gain_ramp_position_frame;
    int pan_ramp_active;
    float pan_ramp_start;
    float pan_ramp_target;
    uint32_t pan_ramp_total_frames;
    uint32_t pan_ramp_position_frame;
    VTXCMixerLoopMode loop_mode;
    uint32_t loop_start_frame;
    uint32_t loop_end_frame;
    int ping_pong_direction;
    VTXCMixerEnvelopeState volume_envelope;
    VTXCMixerEnvelopeState pan_envelope;
    uint64_t key_off_frame;
    int has_key_off_frame;
    int key_on;
    float fadeout_value;
    float fadeout_decrement_per_frame;
    int has_channel_tag;
    uint32_t channel_tag;
    int active;
} VTXCMixerVoice;

typedef struct {
    uint32_t voice_index;
    uint64_t scheduled_frame;
    int update_gain;
    float gain;
    int update_pan;
    float pan;
    int update_sample_step;
    double sample_step;
    int ramp_enabled;
} VTXCMixerVoiceStateEvent;

typedef struct {
    VTXCMixerConfig config;
    uint64_t current_frame;
    uint32_t voice_count;
    uint32_t voice_state_event_count;
    uint32_t next_voice_state_event_index;
    VTXCMixerVoice voices[VTX_C_MIXER_MAX_VOICES];
    VTXCMixerVoiceStateEvent voice_state_events[VTX_C_MIXER_MAX_VOICE_STATE_EVENTS];
} VTXCMixerState;

VTXCMixerConfig vtx_c_mixer_default_config(void);
uint32_t vtx_c_mixer_gain_pan_update_ramp_frame_count(void);
uint32_t vtx_c_mixer_loaded_voice_count(const VTXCMixerState *state);
uint32_t vtx_c_mixer_active_voice_count(const VTXCMixerState *state);
uint64_t vtx_c_mixer_current_frame(const VTXCMixerState *state);
VTXCMixerStatus vtx_c_mixer_init(VTXCMixerState *state, VTXCMixerConfig config);
VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state);
VTXCMixerStatus vtx_c_mixer_configure(VTXCMixerState *state, VTXCMixerConfig config);

// Clears all active one-shot voices and returns the mixer to deterministic silence.
VTXCMixerStatus vtx_c_mixer_clear_voices(VTXCMixerState *state);

// Attaches a caller-owned channel tag to an existing voice. The C mixer treats
// this as an opaque identifier; callers own tracker/channel semantics.
VTXCMixerStatus vtx_c_mixer_set_voice_channel_tag(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint32_t channel_tag
);

// Stops and releases loaded voices with a matching channel tag. Untagged voices
// are never matched by this call. The stopped count reports released voices.
VTXCMixerStatus vtx_c_mixer_stop_voices_for_channel_tag(
    VTXCMixerState *state,
    uint32_t channel_tag,
    uint32_t *out_stopped_count
);

// Copies a caller-owned mono Float32 sample buffer into C-owned one-shot voice storage.
VTXCMixerStatus vtx_c_mixer_add_one_shot_sample(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    uint32_t *out_voice_index
);

// Copies a caller-owned mono Float32 sample buffer into C-owned voice storage.
// loop_end_frame is exclusive; invalid loop definitions fall back to one-shot playback.
VTXCMixerStatus vtx_c_mixer_add_sample_voice(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t *out_voice_index
);

// Copies a caller-owned mono Float32 sample buffer into C-owned voice storage with
// an explicit source-sample step per output frame. Fractional positions are rendered
// with deterministic linear interpolation. Invalid steps fall back to 1.0.
VTXCMixerStatus vtx_c_mixer_add_sample_voice_with_step(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t *out_voice_index
);

// Explicit-step voice variant with an initial source sample frame. This is a generic
// offline mixer primitive; callers own any tracker-specific effect decoding.
VTXCMixerStatus vtx_c_mixer_add_sample_voice_with_step_at_source_frame(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    uint32_t initial_sample_frame,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t *out_voice_index
);

// Copies a caller-owned mono Float32 sample buffer into C-owned scheduled voice storage.
// scheduled_start_frame is an absolute output frame in the mixer timeline. Voices render
// silence until the mixer cursor reaches that frame. Adding a scheduled voice behind the
// current cursor is rejected so late events cannot silently lose their absolute timing.
// The temporary voice slot limit is VTX_C_MIXER_MAX_VOICES.
VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    uint32_t *out_voice_index
);

// Scheduled voice variant with an explicit source-sample step per output frame.
// Fractional positions are rendered with deterministic linear interpolation.
// Invalid steps fall back to 1.0.
VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice_with_step(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    uint32_t *out_voice_index
);

// Scheduled explicit-step voice variant with an initial source sample frame.
// Out-of-range source starts produce an inactive silent voice instead of reading
// outside the copied sample buffer.
VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice_with_step_at_source_frame(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    uint32_t initial_sample_frame,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    uint32_t *out_voice_index
);

// Attaches a copied synthetic volume envelope to an existing voice.
// Values are clamped to 0.0...1.0 and multiply the voice gain. Invalid envelopes
// are disabled, which is equivalent to a constant 1.0 volume envelope.
VTXCMixerStatus vtx_c_mixer_set_voice_volume_envelope(
    VTXCMixerState *state,
    uint32_t voice_index,
    const VTXCMixerEnvelope *envelope
);

// Attaches a copied synthetic pan envelope to an existing voice.
// Values are clamped to -1.0...1.0, added to the voice pan, then clamped to the
// existing C mixer -1.0...1.0 pan convention. Invalid envelopes are disabled,
// which is equivalent to a neutral 0.0 pan offset.
VTXCMixerStatus vtx_c_mixer_set_voice_pan_envelope(
    VTXCMixerState *state,
    uint32_t voice_index,
    const VTXCMixerEnvelope *envelope
);

// Schedules a voice key-off/release at an absolute output frame. Fadeout is a
// caller-supplied per-output-frame decrement in the existing 0.0...1.0 gain domain.
VTXCMixerStatus vtx_c_mixer_set_voice_key_off_frame(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t key_off_frame,
    float fadeout_decrement_per_frame
);

// Imports caller-computed runtime state into an existing offline voice. This is
// intended for deterministic developer/offline window-continuation renders; it
// does not change mixer DSP semantics or allocate during rendering.
VTXCMixerStatus vtx_c_mixer_set_voice_runtime_state(
    VTXCMixerState *state,
    uint32_t voice_index,
    double sample_position,
    int ping_pong_direction,
    uint32_t volume_envelope_position_frame,
    uint32_t pan_envelope_position_frame,
    int key_on,
    float fadeout_value
);

// Imports caller-computed gain/pan ramp continuation state into an existing
// offline voice. This is only for deterministic window-continuation renders.
VTXCMixerStatus vtx_c_mixer_set_voice_gain_pan_ramp_state(
    VTXCMixerState *state,
    uint32_t voice_index,
    VTXCMixerValueRampRuntimeState gain_ramp,
    VTXCMixerValueRampRuntimeState pan_ramp
);

// Schedules a generic gain and/or pan update for an existing offline voice at an
// absolute output frame. At least one of update_gain/update_pan must be nonzero.
// Supported gain/pan updates use the fixed micro-ramp above.
VTXCMixerStatus vtx_c_mixer_schedule_voice_gain_pan_update(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    int update_gain,
    float gain,
    int update_pan,
    float pan
);

// Schedules a generic sample-step update for an existing offline voice at an
// absolute output frame. The adapter owns musical interpretation; C receives
// only a deterministic source-sample step.
VTXCMixerStatus vtx_c_mixer_schedule_voice_sample_step_update(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    double sample_step
);

// Schedules an immediate gain and/or pan set for an existing offline voice.
// This is reserved for hard-cut semantics such as ECx note cut, which must not
// be softened by the gain/pan update micro-ramp.
VTXCMixerStatus vtx_c_mixer_schedule_voice_gain_pan_update_immediate(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    int update_gain,
    float gain,
    int update_pan,
    float pan
);

VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
);

#ifdef __cplusplus
}
#endif

#endif
