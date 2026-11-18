#include "voice_typer.h"

#include <miniaudio.h>
#include "whisper.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace godot {

namespace {

// whisper.cpp and ggml print progress and timing to stderr. None of it is
// what was said, but keep the app's output quiet and free of it anyway.
void quiet_log(enum ggml_log_level, const char *, void *) {}

void capture_callback(ma_device *device, void *, const void *input, ma_uint32 frames) {
    auto *self = static_cast<VoiceTyper *>(device->pUserData);
    if (self && input) {
        self->on_audio(static_cast<const float *>(input), frames);
    }
}

} // namespace

VoiceTyper::VoiceTyper() {
    whisper_log_set(quiet_log, nullptr);
}

VoiceTyper::~VoiceTyper() {
    {
        std::lock_guard<std::mutex> lock(device_mutex_);
        cancel_open_ = true;
    }
    join_opener();
    recording_.store(false);
    close_device();
    join_worker();
    if (whisper_context *c = ctx_.exchange(nullptr)) {
        whisper_free(c);
    }
}

void VoiceTyper::join_worker() {
    if (worker_.joinable()) {
        worker_.join();
    }
}

void VoiceTyper::set_error(const std::string &e) {
    std::lock_guard<std::mutex> lock(error_mutex_);
    error_ = e;
}

String VoiceTyper::get_error() const {
    std::lock_guard<std::mutex> lock(error_mutex_);
    return String::utf8(error_.c_str());
}

void VoiceTyper::set_language(const String &lang) {
    std::string l = lang.utf8().get_data();
    if (!l.empty() && l.size() <= 8) {
        language_ = l;
    }
}

bool VoiceTyper::load_model(const String &path, int threads) {
    if (ctx_ || loading_.load() || busy_.load()) {
        return ctx_ != nullptr;
    }
    join_worker();
    threads_ = std::clamp(threads, 1, 8);
    loading_.store(true);
    std::string p = path.utf8().get_data();
    worker_ = std::thread([this, p]() {
        whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false;
        whisper_context *ctx = whisper_init_from_file_with_params(p.c_str(), cparams);
        bool ok = ctx != nullptr;
        if (ok) {
            ctx_.store(ctx);
            set_error("");
        } else {
            set_error("could not load the speech model");
        }
        loading_.store(false);
        call_deferred("emit_signal", "model_loaded", ok, get_error());
    });
    return true;
}

void VoiceTyper::on_audio(const float *samples, unsigned frames) {
    if (!recording_.load()) {
        return;
    }
    float peak = 0.0f;
    for (unsigned i = 0; i < frames; ++i) {
        peak = std::max(peak, std::fabs(samples[i]));
    }
    level_.store(peak);
    std::lock_guard<std::mutex> lock(audio_mutex_);
    size_t room = MAX_SAMPLES > audio_.size() ? MAX_SAMPLES - audio_.size() : 0;
    size_t n = std::min<size_t>(room, frames);
    audio_.insert(audio_.end(), samples, samples + n);
}

bool VoiceTyper::start_recording() {
    if (!ctx_) {
        set_error("the speech model isn't loaded");
        return false;
    }
    if (recording_.load() || busy_.load() || opening_.load()) {
        return false;
    }
    join_opener();
    {
        std::lock_guard<std::mutex> lock(audio_mutex_);
        audio_.clear();
        audio_.reserve(SAMPLE_RATE * 10);
    }
    {
        std::lock_guard<std::mutex> lock(device_mutex_);
        cancel_open_ = false;
    }
    opening_.store(true);
    opener_ = std::thread([this]() {
        // The last recording's microphone is closed on the worker; wait for
        // that, so two devices never feed the same clip.
        join_worker();
        auto *dev = new ma_device();
        ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
        cfg.capture.format = ma_format_f32;
        cfg.capture.channels = 1;
        cfg.sampleRate = SAMPLE_RATE;
        cfg.dataCallback = capture_callback;
        cfg.pUserData = this;
        cfg.periodSizeInMilliseconds = 20;
        std::string error;
        if (ma_device_init(nullptr, &cfg, dev) != MA_SUCCESS) {
            delete dev;
            dev = nullptr;
            error = "could not open the microphone";
        } else {
            // Before the device starts, so the first callback is kept.
            recording_.store(true);
            if (ma_device_start(dev) != MA_SUCCESS) {
                recording_.store(false);
                ma_device_uninit(dev);
                delete dev;
                dev = nullptr;
                error = "could not start the microphone";
            }
        }
        bool ok = dev != nullptr;
        {
            std::lock_guard<std::mutex> lock(device_mutex_);
            if (ok && cancel_open_) {
                // stop_recording() came while the microphone was opening.
                recording_.store(false);
                ma_device_uninit(dev);
                delete dev;
                ok = false;
                std::lock_guard<std::mutex> audio_lock(audio_mutex_);
                std::fill(audio_.begin(), audio_.end(), 0.0f);
                audio_.clear();
            } else if (ok) {
                device_ = dev;
            }
            opening_.store(false);
        }
        if (!error.empty()) {
            set_error(error);
        }
        call_deferred("emit_signal", "recording_started", ok, String::utf8(error.c_str()));
    });
    return true;
}

void VoiceTyper::join_opener() {
    if (opener_.joinable()) {
        opener_.join();
    }
}

void VoiceTyper::close_device() {
    void *taken = nullptr;
    {
        std::lock_guard<std::mutex> lock(device_mutex_);
        taken = device_;
        device_ = nullptr;
    }
    if (taken) {
        auto *dev = static_cast<ma_device *>(taken);
        ma_device_uninit(dev);
        delete dev;
    }
    level_.store(0.0f);
}

void VoiceTyper::stop_recording(bool transcribe) {
    void *taken = nullptr;
    {
        std::lock_guard<std::mutex> lock(device_mutex_);
        if (opening_.load()) {
            // Not open yet: the opener closes it again when it gets there.
            cancel_open_ = true;
            return;
        }
        if (!recording_.load()) {
            return;
        }
        recording_.store(false);
        taken = device_;
        device_ = nullptr;
    }
    level_.store(0.0f);
    std::vector<float> clip;
    {
        std::lock_guard<std::mutex> lock(audio_mutex_);
        clip.swap(audio_);
    }
    bool run = transcribe && ctx_ && !clip.empty();
    if (!run) {
        std::fill(clip.begin(), clip.end(), 0.0f);
        clip.clear();
    }
    join_worker();
    busy_.store(run);
    // Closing the microphone can take a while too, so that is done on the
    // worker as well, before the clip is transcribed.
    worker_ = std::thread([this, taken, run, clip = std::move(clip)]() mutable {
        if (taken) {
            auto *dev = static_cast<ma_device *>(taken);
            ma_device_uninit(dev);
            delete dev;
        }
        if (!run) {
            return;
        }
        double sum = 0.0;
        for (float s : clip) {
            sum += double(s) * double(s);
        }
        // RMS on the 16-bit scale, so a threshold reads like whisper-frame's.
        double rms = std::sqrt(sum / double(clip.size())) * 32768.0;
        double seconds = double(clip.size()) / SAMPLE_RATE;
        // How much of the clip is sound at all, for telling a microphone that
        // delivered silence from a model that returned little: the share of
        // tenth-of-a-second blocks under the silence level, and the share of
        // samples that are exactly zero (a gated or stalled microphone).
        // Numbers about loudness only; nothing of what was said.
        const size_t block = size_t(SAMPLE_RATE / 10);
        size_t blocks = 0, quiet_blocks = 0, zero_samples = 0;
        for (size_t at = 0; at + block <= clip.size(); at += block) {
            double block_sum = 0.0;
            for (size_t k = at; k < at + block; ++k) {
                block_sum += double(clip[k]) * double(clip[k]);
                zero_samples += clip[k] == 0.0f ? 1 : 0;
            }
            blocks++;
            quiet_blocks += std::sqrt(block_sum / double(block)) * 32768.0 < QUIET_BLOCK_RMS ? 1 : 0;
        }
        const double quiet_share = blocks ? double(quiet_blocks) / double(blocks) : 0.0;
        const double zero_share = blocks ? double(zero_samples) / double(blocks * block) : 0.0;
        // Long pauses are shortened before the model hears the clip: the
        // model tends to end on a pause, and then has to listen again for
        // what was said after it (see the stretches below). It also makes
        // the clip shorter to work out.
        const double trimmed_seconds = double(compress_pauses(clip)) / SAMPLE_RATE;
        // whisper.cpp is unreliable on clips under a second: pad with silence.
        if (clip.size() < size_t(SAMPLE_RATE * 1.1)) {
            clip.resize(size_t(SAMPLE_RATE * 1.1), 0.0f);
        }
        whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        p.n_threads = threads_;
        p.language = language_.c_str();
        p.translate = false;
        p.no_context = true;
        // With timestamps. Without them whisper.cpp takes the model's first
        // "end of text" as the end of the whole clip, and what was said after
        // it is lost: 7s log, 34 characters back from 10 seconds of speech,
        // 50 from 14: whole parts of sentences were cut off, though long pauses are already shortened above. With
        // them, whisper.cpp goes on from where the model stopped until the
        // clip is used up, at the cost of listening again from that point
        // (made cheaper below by handing the clip over a stretch at a time).
        p.no_timestamps = false;
        p.single_segment = false;
        p.print_special = false;
        p.print_progress = false;
        p.print_realtime = false;
        p.print_timestamps = false;
        p.suppress_nst = true;
        p.no_speech_thold = 0.6f;
        p.greedy.best_of = 1;
        std::string text;
        int tokens = 0;
        int parts = 0;
        int passes = 0;
        double no_speech = 0.0;
        whisper_context *ctx = ctx_.load();
        // The model stops at a pause now and then, and with timestamps
        // whisper.cpp then listens again from where it stopped. Left to do
        // that itself it listens to a window as long as the whole clip each
        // time: in the 7v log 30 seconds of speech took 9.6 s to work out
        // when it listened once and 21 to 23 s when it listened twice. So the
        // clip is handed over a stretch at a time instead. whisper.cpp is
        // stopped as it is about to listen again (the encoder callback), what
        // it has made of the stretch so far is kept, and the next stretch
        // starts where its last part ended and is only as long as what is
        // left, so listening again costs what is left and not the whole clip.
        struct Listening {
            int begun = 0;
            int allowed = 1;
        };
        p.encoder_begin_callback = [](whisper_context *, whisper_state *, void *data) -> bool {
            auto *listening = static_cast<Listening *>(data);
            return ++listening->begun <= listening->allowed;
        };
        // Told to find the language itself, whisper.cpp listens once more at
        // the start for that.
        const int once = (language_.empty() || language_ == "auto") ? 2 : 1;
        size_t at = 0;
        bool failed = false;
        std::vector<float> padded;
        // How long each stretch was, in seconds, for the log.
        std::vector<double> stretch_seconds;
        for (int stretch = 0; stretch < MAX_STRETCHES && at < clip.size(); ++stretch) {
            size_t left = clip.size() - at;
            // Under a third of a second can't hold a word.
            if (stretch > 0 && left < size_t(SAMPLE_RATE * 0.3)) {
                break;
            }
            const float *samples = clip.data() + at;
            // whisper.cpp is unreliable on clips under a second: pad with silence.
            if (left < size_t(SAMPLE_RATE * 1.1)) {
                padded.assign(samples, samples + left);
                padded.resize(size_t(SAMPLE_RATE * 1.1), 0.0f);
                samples = padded.data();
                left = padded.size();
            }
            // Whisper listens to a fixed 30 second window (1500 steps of 20 ms)
            // however short the clip, which is why two seconds of speech took
            // as long to work out as twenty-six. Hand it the stretch's own
            // length plus a margin, and the listening half of the work shrinks
            // with it. (whisper_full_params.audio_ctx; whisper.cpp's stream
            // example does the same with a fixed 768.) Never below about eight
            // seconds: very short windows make the model repeat itself.
            const int steps = int(std::ceil(double(left) / SAMPLE_RATE * 50.0)) + AUDIO_CTX_MARGIN;
            p.audio_ctx = std::clamp(steps, AUDIO_CTX_MIN, whisper_n_audio_ctx(ctx));
            // The model can get stuck repeating its last word (a 1.1 second
            // clip once came back as "Meteor" twenty-three times, and took 7.8
            // seconds to do it). Nobody says more than a few words a second,
            // so stop it at a generous word budget for the stretch's length;
            // what remains of a runaway is tidied in
            // VoiceTyping.collapse_runaway().
            p.max_tokens = int(std::ceil(double(left) / SAMPLE_RATE * MAX_TOKENS_PER_SECOND)) + MAX_TOKENS_MARGIN;
            Listening listening;
            // The last stretch allowed: whisper.cpp finishes it its own way.
            listening.allowed = stretch == MAX_STRETCHES - 1 ? INT_MAX : once;
            p.encoder_begin_callback_user_data = &listening;
            if (whisper_full(ctx, p, samples, int(left)) != 0) {
                failed = true;
                break;
            }
            int n = whisper_full_n_segments(ctx);
            bool wants_more = listening.begun > listening.allowed;
            if (wants_more && n == 0) {
                // It moved on without a word, so there is no part to say
                // where to: let it finish this stretch its own way.
                listening = Listening();
                listening.allowed = INT_MAX;
                if (whisper_full(ctx, p, samples, int(left)) != 0) {
                    failed = true;
                    break;
                }
                n = whisper_full_n_segments(ctx);
                wants_more = false;
            }
            passes += std::min(listening.begun, listening.allowed);
            parts += n;
            stretch_seconds.push_back(double(clip.size() - at) / SAMPLE_RATE);
            for (int i = 0; i < n; ++i) {
                const char *seg = whisper_full_get_segment_text(ctx, i);
                if (seg) {
                    text += seg;
                }
                tokens += whisper_full_n_tokens(ctx, i);
                no_speech = std::max(no_speech, double(whisper_full_get_segment_no_speech_prob(ctx, i)));
            }
            if (!wants_more) {
                break;
            }
            // Where its last part ended, in hundredths of a second from the
            // start of this stretch: where it was about to listen from.
            const int64_t ended = whisper_full_get_segment_t1(ctx, n - 1);
            const size_t advance = ended > 0 ? size_t(ended) * SAMPLE_RATE / 100 : 0;
            if (advance == 0 || at + advance >= clip.size()) {
                break;
            }
            at += advance;
        }
        if (failed) {
            set_error("transcription failed");
        }
        // Drop the audio now; only the text leaves this thread.
        std::fill(clip.begin(), clip.end(), 0.0f);
        clip.clear();
        clip.shrink_to_fit();
        busy_.store(false);
        {
            std::lock_guard<std::mutex> lock(stats_mutex_);
            stats_quiet_share_ = quiet_share;
            stats_zero_share_ = zero_share;
            stats_tokens_ = tokens;
            stats_parts_ = parts;
            stats_passes_ = passes;
            stats_stretches_ = stretch_seconds;
            stats_no_speech_ = no_speech;
            stats_trimmed_seconds_ = trimmed_seconds;
        }
        call_deferred("emit_signal", "transcribed", String::utf8(text.c_str()), rms, seconds);
    });
}

size_t VoiceTyper::compress_pauses(std::vector<float> &clip) {
    const size_t block = size_t(SAMPLE_RATE / 10);
    const size_t blocks = clip.size() / block;
    if (blocks == 0) {
        return 0;
    }
    std::vector<bool> quiet(blocks);
    for (size_t b = 0; b < blocks; ++b) {
        double sum = 0.0;
        for (size_t k = b * block; k < (b + 1) * block; ++k) {
            sum += double(clip[k]) * double(clip[k]);
        }
        quiet[b] = std::sqrt(sum / double(block)) * 32768.0 < QUIET_BLOCK_RMS;
    }
    std::vector<float> out;
    out.reserve(clip.size());
    size_t b = 0;
    while (b < blocks) {
        if (!quiet[b]) {
            out.insert(out.end(), clip.begin() + b * block, clip.begin() + (b + 1) * block);
            ++b;
            continue;
        }
        size_t end = b;
        while (end < blocks && quiet[end]) {
            ++end;
        }
        const size_t run = end - b;
        if (run <= PAUSE_KEPT_BLOCKS) {
            out.insert(out.end(), clip.begin() + b * block, clip.begin() + end * block);
        } else {
            // Keep the pause's first and last parts, next to the words.
            const size_t head = PAUSE_KEPT_BLOCKS / 2;
            const size_t tail = PAUSE_KEPT_BLOCKS - head;
            out.insert(out.end(), clip.begin() + b * block, clip.begin() + (b + head) * block);
            out.insert(out.end(), clip.begin() + (end - tail) * block, clip.begin() + end * block);
        }
        b = end;
    }
    // The last, incomplete block is kept as it is.
    out.insert(out.end(), clip.begin() + blocks * block, clip.end());
    const size_t removed = clip.size() - out.size();
    if (removed > 0) {
        std::fill(clip.begin(), clip.end(), 0.0f);
        clip = std::move(out);
    }
    return removed;
}

PackedFloat32Array VoiceTyper::compress_pauses_in(const PackedFloat32Array &samples) {
    std::vector<float> clip(samples.ptr(), samples.ptr() + samples.size());
    compress_pauses(clip);
    PackedFloat32Array out;
    out.resize(int64_t(clip.size()));
    std::copy(clip.begin(), clip.end(), out.ptrw());
    return out;
}

Dictionary VoiceTyper::get_last_clip_stats() const {
    std::lock_guard<std::mutex> lock(stats_mutex_);
    Dictionary stats;
    stats["quiet_share"] = stats_quiet_share_;
    stats["zero_share"] = stats_zero_share_;
    stats["tokens"] = stats_tokens_;
    stats["parts"] = stats_parts_;
    stats["passes"] = stats_passes_;
    PackedFloat32Array stretches;
    for (double seconds : stats_stretches_) {
        stretches.push_back(float(seconds));
    }
    stats["stretches"] = stretches;
    stats["no_speech"] = stats_no_speech_;
    stats["trimmed_seconds"] = stats_trimmed_seconds_;
    return stats;
}

void VoiceTyper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_model", "path", "threads"), &VoiceTyper::load_model);
    ClassDB::bind_method(D_METHOD("is_ready"), &VoiceTyper::is_ready);
    ClassDB::bind_method(D_METHOD("is_loading"), &VoiceTyper::is_loading);
    ClassDB::bind_method(D_METHOD("is_busy"), &VoiceTyper::is_busy);
    ClassDB::bind_method(D_METHOD("is_recording"), &VoiceTyper::is_recording);
    ClassDB::bind_method(D_METHOD("is_opening"), &VoiceTyper::is_opening);
    ClassDB::bind_method(D_METHOD("get_error"), &VoiceTyper::get_error);
    ClassDB::bind_method(D_METHOD("start_recording"), &VoiceTyper::start_recording);
    ClassDB::bind_method(D_METHOD("stop_recording", "transcribe"), &VoiceTyper::stop_recording);
    ClassDB::bind_method(D_METHOD("get_level"), &VoiceTyper::get_level);
    ClassDB::bind_method(D_METHOD("get_last_clip_stats"), &VoiceTyper::get_last_clip_stats);
    ClassDB::bind_static_method("VoiceTyper", D_METHOD("compress_pauses_in", "samples"), &VoiceTyper::compress_pauses_in);
    ClassDB::bind_method(D_METHOD("set_language", "language"), &VoiceTyper::set_language);
    ADD_SIGNAL(MethodInfo("model_loaded", PropertyInfo(Variant::BOOL, "ok"), PropertyInfo(Variant::STRING, "error")));
    ADD_SIGNAL(MethodInfo("recording_started", PropertyInfo(Variant::BOOL, "ok"), PropertyInfo(Variant::STRING, "error")));
    ADD_SIGNAL(MethodInfo("transcribed", PropertyInfo(Variant::STRING, "text"),
        PropertyInfo(Variant::FLOAT, "rms"), PropertyInfo(Variant::FLOAT, "seconds")));
}

} // namespace godot
