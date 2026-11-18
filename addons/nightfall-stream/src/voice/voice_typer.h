#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

struct whisper_context;

namespace godot {

// Voice typing (Steam Frame): hold a button, speak, let go. The microphone is
// recorded into memory only (never to disk), transcribed on the headset with
// whisper.cpp, and the audio is thrown away. The text is handed back to
// GDScript through the "transcribed" signal; GDScript sends it into the
// encrypted stream. Nothing here logs what was said.
class VoiceTyper : public RefCounted {
    GDCLASS(VoiceTyper, RefCounted)

public:
    VoiceTyper();
    ~VoiceTyper() override;

    // Loads the model in the background. Emits "model_loaded"(ok, error).
    bool load_model(const String &path, int threads);
    bool is_ready() const { return ctx_.load() != nullptr; }
    bool is_loading() const { return loading_.load(); }
    bool is_busy() const { return busy_.load(); }
    // True from start_recording() until stop_recording(): while the
    // microphone is being opened as well as while it records.
    bool is_recording() const { return recording_.load() || opening_.load(); }
    bool is_opening() const { return opening_.load(); }
    String get_error() const;

    // Opens the default microphone and records into memory (max 30 s).
    // Opening takes about half a second on the Steam Frame, so it happens in
    // the background: this returns at once, and "recording_started"(ok,
    // error) follows when the microphone is open (or couldn't be opened, or
    // stop_recording() came first: then ok is false and error is empty).
    bool start_recording();
    // Stops recording. With transcribe=true the clip is transcribed in the
    // background and "transcribed"(text, rms, seconds) is emitted; the audio
    // is freed either way.
    void stop_recording(bool transcribe);
    // Peak level of the latest audio, 0-1 (for a meter; never audio itself).
    float get_level() const { return level_.load(); }
    // Numbers about the last clip, for the log: quiet_share and zero_share
    // (0..1, how much of it was silence or dead samples), and tokens, parts
    // and no_speech (what the model made of it). Nothing of what was said.
    Dictionary get_last_clip_stats() const;
    // Shortens every pause longer than PAUSE_KEPT_BLOCKS tenths of a second
    // to that length, in place; returns the number of samples removed. See
    // stop_recording for why. The second form is for tests.
    static size_t compress_pauses(std::vector<float> &clip);
    static PackedFloat32Array compress_pauses_in(const PackedFloat32Array &samples);
    void set_language(const String &lang);

    // Called from the audio thread.
    void on_audio(const float *samples, unsigned frames);

protected:
    static void _bind_methods();

private:
    void set_error(const std::string &e);
    void close_device();
    void join_worker();
    void join_opener();

    std::atomic<whisper_context *> ctx_{nullptr};
    int threads_ = 4;
    std::string language_ = "en";

    void *device_ = nullptr; // ma_device; guarded by device_mutex_
    std::mutex device_mutex_;
    std::thread opener_;
    std::atomic<bool> opening_{false};
    bool cancel_open_ = false; // guarded by device_mutex_
    std::mutex audio_mutex_;
    std::vector<float> audio_;
    std::atomic<bool> recording_{false};
    std::atomic<bool> busy_{false};
    std::atomic<bool> loading_{false};
    std::atomic<float> level_{0.0f};
    std::thread worker_;
    mutable std::mutex error_mutex_;
    std::string error_;
    mutable std::mutex stats_mutex_;
    double stats_quiet_share_ = 0.0;
    double stats_zero_share_ = 0.0;
    double stats_no_speech_ = 0.0;
    double stats_trimmed_seconds_ = 0.0;
    int stats_tokens_ = 0;
    int stats_parts_ = 0;
    int stats_passes_ = 0;
    std::vector<double> stats_stretches_;

    static constexpr int SAMPLE_RATE = 16000;
    static constexpr size_t MAX_SAMPLES = SAMPLE_RATE * 30;
    // See stop_recording: how much of Whisper's 30 s window (1500 steps) a
    // clip is given beyond its own length, and the least it is ever given.
    static constexpr int AUDIO_CTX_MARGIN = 128;
    static constexpr int AUDIO_CTX_MIN = 384;
    // The most text a clip may come back as: about three times ordinary
    // dictation (which ran at 3 tokens a second in the logs), plus room for a
    // short clip's punctuation. See stop_recording.
    static constexpr double MAX_TOKENS_PER_SECOND = 10.0;
    static constexpr int MAX_TOKENS_MARGIN = 24;
    // How many stretches a clip is worked out in at most: the model stopping
    // early more often than this in one clip (30 seconds at the longest)
    // would be something else going wrong.
    static constexpr int MAX_STRETCHES = 6;
    // A tenth-of-a-second block under this RMS (16-bit scale) counts as
    // quiet. The same level VoiceTyping uses for "didn't hear anything".
    static constexpr double QUIET_BLOCK_RMS = 30.0;
    // Half a second of each pause is kept: enough for the model to hear a
    // break between sentences.
    static constexpr size_t PAUSE_KEPT_BLOCKS = 5;
};

} // namespace godot
