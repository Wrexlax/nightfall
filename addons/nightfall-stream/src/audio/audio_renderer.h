#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include "opus_decoder.h"
#include "platform_audio.h"
#include <memory>
#include <atomic>
#include <vector>

extern "C" {
#include <Limelight.h>
}

namespace godot {

class AudioRenderer : public RefCounted {
    GDCLASS(AudioRenderer, RefCounted);

public:
    AudioRenderer();
    ~AudioRenderer();

    int init(int audio_configuration, const POPUS_MULTISTREAM_CONFIGURATION opus_config, void *context, int ar_flags);
    void start();
    void stop();
    void cleanup();
    void decode_and_play_sample(const char *sample_data, int sample_length);
    int64_t get_packets_received() const { return packets_received_.load(); }
    void play_local_pcm(const float *data, size_t frames);
    void set_muted(bool muted);
    bool is_muted() const;
    void set_volume_boost_db(float db);
    float get_volume_boost_db() const;
    void set_android_output(int output);

    bool is_initialized() const;
    int get_channels() const;
    int get_sample_rate() const;
    float get_latency_ms() const;
    String get_backend_name() const;

protected:
    static void _bind_methods();

private:
    void _downmix_to_stereo(const float *multi, float *stereo);
    void _apply_volume_boost(float *samples, int count) const;
    void _record_audio(const float *decoded, int decoded_channels, const float *output, int output_channels, int frames, bool written);

    static AudioRenderer *active_instance_;
    friend class StreamConnection;

    static int _cb_init(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void *context, int arFlags);
    static void _cb_start();
    static void _cb_stop();
    static void _cb_cleanup();
    static void _cb_decode_and_play_sample(char *sampleData, int sampleLength);

    Ref<OpusDecoderWrapper> opus_decoder_;
    std::unique_ptr<nightfall::PlatformAudio> audio_backend_;
    PackedByteArray opus_data_buf_;

    int audio_configuration_ = 0;
    int channels_ = 0;
    int sample_rate_ = 48000;
    int samples_per_frame_ = 240;
    unsigned char channel_mapping_[8] = {};

    std::atomic<bool> initialized_{false};
    std::atomic<int64_t> packets_received_{0};
    std::atomic<bool> running_{false};
    std::atomic<bool> muted_{false};
    std::atomic<float> volume_boost_db_{0.0f};
    std::atomic<float> volume_gain_{1.0f};
    std::atomic<int> android_output_{0};
    double decoded_energy_[2] = {}, output_energy_[2] = {};
    float decoded_peak_[2] = {}, output_peak_[2] = {};
    uint64_t diagnostic_frames_ = 0, diagnostic_failures_ = 0;
    // Short-window diagnostics around gaps in the audio stream (pause buzz).
    int64_t last_packet_us_ = 0;
    int64_t watch_until_us_ = 0;
    uint64_t win_frames_ = 0;
    double win_energy_ = 0.0;
    float win_peak_ = 0.0f;
    // Last 3 s of 100 ms windows (peak dBFS), dumped when a gap starts.
    float hist_peak_db_[30] = {};
    float hist_rep_[30] = {};      // 0..1: how strongly the window repeats itself (a looping buffer = buzz)
    float dec_buf_[1300] = {};     // mono, 12 kHz, current window
    int dec_len_ = 0;
    int hist_pos_ = 0;
    uint64_t plc_frames_ = 0;
    // A packet byte-identical to the one before it is a re-sent packet (a
    // stuck sender looping its last audio = the pause buzz), not new sound.
    std::vector<uint8_t> prev_packet_;
    int repeat_run_ = 0;
    uint64_t repeated_packets_ = 0;
};

} // namespace godot
