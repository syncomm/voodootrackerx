#ifndef VTX_C_MIXER_H
#define VTX_C_MIXER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTX_C_MIXER_DEFAULT_SAMPLE_RATE 44100.0
#define VTX_C_MIXER_DEFAULT_CHANNEL_COUNT 2u

// Temporary fixed voice limit for the early offline C mixer path.
// Rendering uses this preallocated storage and does not allocate in the render call.
#define VTX_C_MIXER_MAX_VOICES 32u

// Synthetic offline envelopes use copied fixed-size point storage. XM instruments are
// not wired into this C-backed path yet.
#define VTX_C_MIXER_MAX_ENVELOPE_POINTS 12u

typedef enum {
    VTX_C_MIXER_STATUS_OK = 0,
    VTX_C_MIXER_STATUS_INVALID_ARGUMENT = 1,
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
    const VTXCMixerEnvelopePoint *points;
    uint32_t point_count;
} VTXCMixerEnvelope;

typedef struct {
    VTXCMixerEnvelopePoint points[VTX_C_MIXER_MAX_ENVELOPE_POINTS];
    uint32_t point_count;
    uint32_t position_frame;
    int enabled;
} VTXCMixerEnvelopeState;

typedef struct {
    float *sample_pcm;
    uint32_t sample_frame_count;
    double sample_position;
    uint64_t scheduled_start_frame;
    float gain;
    float pan;
    VTXCMixerLoopMode loop_mode;
    uint32_t loop_start_frame;
    uint32_t loop_end_frame;
    int ping_pong_direction;
    VTXCMixerEnvelopeState volume_envelope;
    VTXCMixerEnvelopeState pan_envelope;
    int active;
} VTXCMixerVoice;

typedef struct {
    VTXCMixerConfig config;
    uint64_t current_frame;
    uint32_t voice_count;
    VTXCMixerVoice voices[VTX_C_MIXER_MAX_VOICES];
} VTXCMixerState;

VTXCMixerConfig vtx_c_mixer_default_config(void);
VTXCMixerStatus vtx_c_mixer_init(VTXCMixerState *state, VTXCMixerConfig config);
VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state);
VTXCMixerStatus vtx_c_mixer_configure(VTXCMixerState *state, VTXCMixerConfig config);

// Clears all active one-shot voices and returns the mixer to deterministic silence.
VTXCMixerStatus vtx_c_mixer_clear_voices(VTXCMixerState *state);

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

VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
);

#ifdef __cplusplus
}
#endif

#endif
