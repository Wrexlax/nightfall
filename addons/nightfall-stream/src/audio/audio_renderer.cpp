#include "audio_renderer.h"
#include "miniaudio_backend.h"
#include "android_audio_backend.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>
#include <cstring>
#include <chrono>
#include <cstdio>
#include "nf_log.h"

using namespace godot;

AudioRenderer *AudioRenderer::active_instance_ = nullptr;

AudioRenderer::AudioRenderer() {
    opus_decoder_.instantiate();
}

AudioRenderer::~AudioRenderer() {
    cleanup();
}

int AudioRenderer::_cb_init(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void *context, int arFlags) {
    auto *self = active_instance_;
    if (!self) return -1;
    return self->init(audioConfiguration, opusConfig, context, arFlags);
}

void AudioRenderer::_cb_start() {
    auto *self = active_instance_;
    if (self) self->start();
}

void AudioRenderer::_cb_stop() {
    auto *self = active_instance_;
    if (self) self->stop();
}

void AudioRenderer::_cb_cleanup() {
    auto *self = active_instance_;
    if (self) self->cleanup();
}

void AudioRenderer::_cb_decode_and_play_sample(char *sampleData, int sampleLength) {
    auto *self = active_instance_;
    if (self && !self->muted_.load()) self->decode_and_play_sample(sampleData, sampleLength);
}

int AudioRenderer::init(int audio_configuration, const POPUS_MULTISTREAM_CONFIGURATION opus_config, void * /*context*/, int /*ar_flags*/) {
    if (!opus_config) return -1;

    audio_configuration_ = audio_configuration;
    packets_received_.store(0);
    channels_ = opus_config->channelCount;
    sample_rate_ = opus_config->sampleRate;
    samples_per_frame_ = opus_config->samplesPerFrame;
    memcpy(channel_mapping_, opus_config->mapping, sizeof(channel_mapping_));

    NF_LOG("AudioRenderer",
        "init: audioCfg=0x%x channels=%d sampleRate=%d samplesPerFrame=%d streams=%d coupledStreams=%d mapping=[%d,%d,%d,%d,%d,%d,%d,%d]",
        audio_configuration, channels_, sample_rate_, samples_per_frame_,
        opus_config->streams, opus_config->coupledStreams,
        opus_config->mapping[0], opus_config->mapping[1], opus_config->mapping[2], opus_config->mapping[3],
        opus_config->mapping[4], opus_config->mapping[5], opus_config->mapping[6], opus_config->mapping[7]);

    PackedByteArray mapping;
    mapping.resize(channels_);
    for (int i = 0; i < channels_; i++) {
        mapping[i] = (uint8_t)channel_mapping_[i];
    }

    int ret = opus_decoder_->init(sample_rate_, channels_, opus_config->streams, opus_config->coupledStreams, mapping);
    if (ret != 0) {
        UtilityFunctions::printerr("[AudioRenderer] Opus init failed: ", ret);
        return -1;
    }

    int output_channels = (channels_ > 2) ? 2 : channels_;
    int period_frames = samples_per_frame_;

    audio_backend_ = std::make_unique<nightfall::MiniaudioBackend>();
#ifdef __ANDROID__
    if (android_output_.load() == 1) audio_backend_ = std::make_unique<nightfall::AndroidAudioBackend>();
#endif
    if (!audio_backend_->initialize(sample_rate_, output_channels, period_frames)) {
        UtilityFunctions::printerr("[AudioRenderer] Audio backend init failed");
        return -1;
    }

    initialized_.store(true);
    diagnostic_frames_ = diagnostic_failures_ = 0;
    memset(decoded_energy_, 0, sizeof(decoded_energy_));
    memset(output_energy_, 0, sizeof(output_energy_));
    memset(decoded_peak_, 0, sizeof(decoded_peak_));
    memset(output_peak_, 0, sizeof(output_peak_));
    NF_LOG("AudioRenderer", "output=%s requested=%d boost=%.1fdB channels=%d->%d rate=%d",
        audio_backend_->get_backend_name().c_str(), android_output_.load(), volume_boost_db_.load(), channels_, output_channels, sample_rate_);
    UtilityFunctions::print("[AudioRenderer] Initialized: ", sample_rate_, "Hz ", channels_, "ch (output ", output_channels, "ch), ", samples_per_frame_, " spf");
    return 0;
}

void AudioRenderer::start() {
    running_.store(true);
    if (audio_backend_) audio_backend_->resume();
    UtilityFunctions::print("[AudioRenderer] Started");
}

void AudioRenderer::stop() {
    running_.store(false);
    if (audio_backend_) audio_backend_->pause();
    UtilityFunctions::print("[AudioRenderer] Stopped");
}

void AudioRenderer::cleanup() {
    running_.store(false);
    initialized_.store(false);

    if (audio_backend_) {
        audio_backend_->shutdown();
        audio_backend_.reset();
    }

    if (opus_decoder_.is_valid()) {
        opus_decoder_->cleanup();
    }
}

void AudioRenderer::decode_and_play_sample(const char *sample_data, int sample_length) {
    if (!initialized_.load() || !running_.load()) return;
    if (sample_data != nullptr && sample_length > 0) packets_received_.fetch_add(1);

    int frames;
    if (sample_data == nullptr || sample_length <= 0) {
        // moonlight-common-c's placeholder for a lost packet: let Opus fill
        // the 5 ms hole instead of skipping it (a skip is an audible click).
        frames = opus_decoder_->decode_plc(samples_per_frame_);
        plc_frames_++;
    } else {
        const bool same = (int)prev_packet_.size() == sample_length &&
                          memcmp(prev_packet_.data(), sample_data, sample_length) == 0;
        if (same && sample_length > 16) {
            // Tiny packets (Opus digital silence) legitimately repeat; real
            // audio never produces the same packet twice in a row.
            repeat_run_++;
            repeated_packets_++;
            if (repeat_run_ == 4) {
                NF_LOG("AudioRenderer", "[AUDIO-REPEAT] sender is re-sending identical %d-byte audio packets (total %llu; playing them, muting is off)",
                       sample_length, (unsigned long long)repeated_packets_);
            }
            // Muting disabled for testing: the streaming-device setting fixed
            // the pause buzz, so play re-sent packets as they arrive.
            if (false && repeat_run_ >= 2 && audio_backend_ && running_.load()) {
                // Play silence for the re-sent packet instead of the loop.
                float zeros[960 * 2] = {};
                int n = samples_per_frame_ > 0 && samples_per_frame_ <= 960 ? samples_per_frame_ : 240;
                audio_backend_->write_pcm(zeros, n);
                return;
            }
        } else {
            if (repeat_run_ >= 4) {
                NF_LOG("AudioRenderer", "[AUDIO-REPEAT] run ended after %d identical packets", repeat_run_);
            }
            repeat_run_ = 0;
            prev_packet_.assign((const uint8_t *)sample_data, (const uint8_t *)sample_data + sample_length);
        }
        opus_data_buf_.resize(sample_length);
        memcpy(opus_data_buf_.ptrw(), sample_data, sample_length);
        frames = opus_decoder_->decode(opus_data_buf_, samples_per_frame_);
    }
    if (frames <= 0) return;

    {
        // Log gaps in the incoming audio and, for 3 s after one, the level of
        // every 100 ms - to tell host-side noise from local playback trouble.
        const int64_t now_us = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        if (last_packet_us_ != 0 && now_us - last_packet_us_ > 60000) {
            NF_LOG("AudioRenderer", "[AUDIO-GAP] %lld ms without audio packets (buffer %d ms, %s)",
                   (long long)((now_us - last_packet_us_) / 1000), audio_backend_ ? audio_backend_->get_latency_ms() : -1,
                   audio_backend_ ? audio_backend_->get_debug_stats().c_str() : "");
            if (now_us - last_packet_us_ > 500000) {
                char hist[30 * 12 + 1];
                int off = 0;
                for (int i = 0; i < 30; i++) {
                    float v = hist_peak_db_[(hist_pos_ + i) % 30];
                    float r = hist_rep_[(hist_pos_ + i) % 30];
                    off += snprintf(hist + off, sizeof(hist) - off, "%d/%02d ", (int)lroundf(v), (int)lroundf(r * 99.0f));
                    if (off >= (int)sizeof(hist)) break;
                }
                NF_LOG("AudioRenderer", "[AUDIO-BEFORE-GAP] peak dBFS/repetition%% per 100 ms, oldest first: %s", hist);
            }
            watch_until_us_ = now_us + 3000000;
            win_frames_ = 0; win_energy_ = 0.0; win_peak_ = 0.0f;
        }
        last_packet_us_ = now_us;
        {
            const PackedFloat32Array &p = opus_decoder_->get_last_pcm();
            const float *d = p.ptr();
            const int n = frames * channels_;
            if (p.size() >= n) {
                for (int i = 0; i < n; i++) {
                    win_energy_ += (double)d[i] * d[i];
                    win_peak_ = fmaxf(win_peak_, fabsf(d[i]));
                }
                for (int f = 0; f + 3 < frames && dec_len_ < 1300; f += 4) {
                    float m = 0.0f;
                    for (int k = 0; k < 4; k++)
                        for (int c = 0; c < channels_; c++) m += d[(f + k) * channels_ + c];
                    dec_buf_[dec_len_++] = m / (float)(4 * channels_);
                }
                win_frames_ += frames;
                if (win_frames_ >= (uint64_t)sample_rate_ / 10) {
                    double rms = 10.0 * log10(fmax(win_energy_ / (double)(win_frames_ * channels_), 1e-12));
                    double pk = 20.0 * log10(fmax((double)win_peak_, 1e-6));
                    // Self-similarity at 2-25 ms lags (12 kHz samples 24..300).
                    float rep = 0.0f;
                    if (dec_len_ > 600 && win_peak_ > 0.003f) {
                        const int len = dec_len_;
                        double e0 = 0.0;
                        for (int i = 0; i < len - 300; i++) e0 += (double)dec_buf_[i] * dec_buf_[i];
                        for (int lag = 24; lag <= 300; lag += 2) {
                            double num = 0.0, e1 = 0.0;
                            for (int i = 0; i < len - 300; i++) {
                                num += (double)dec_buf_[i] * dec_buf_[i + lag];
                                e1 += (double)dec_buf_[i + lag] * dec_buf_[i + lag];
                            }
                            double r = (e0 > 0 && e1 > 0) ? num / sqrt(e0 * e1) : 0.0;
                            if (r > rep) rep = (float)r;
                        }
                    }
                    dec_len_ = 0;
                    hist_rep_[hist_pos_] = rep;
                    // A loud window that repeats itself almost exactly is a
                    // stuck loop (the pause buzz), not music: log every one.
                    if (rep > 0.90f && pk > -40.0) {
                        NF_LOG("AudioRenderer", "[AUDIO-LOOP] incoming audio repeating: rep=%.2f peak=%.1fdBFS rms=%.1fdBFS", rep, pk, rms);
                    }
                    hist_peak_db_[hist_pos_] = (float)pk;
                    hist_pos_ = (hist_pos_ + 1) % 30;
                    if (now_us < watch_until_us_) {
                        NF_LOG("AudioRenderer", "[AUDIO-WATCH] rms=%.1fdBFS peak=%.1fdBFS rep=%.2f buffer=%dms", rms, pk, rep,
                               audio_backend_ ? audio_backend_->get_latency_ms() : -1);
                    }
                    win_frames_ = 0; win_energy_ = 0.0; win_peak_ = 0.0f;
                }
            }
        }
    }
    if (!audio_backend_) return;

    const PackedFloat32Array &pcm = opus_decoder_->get_last_pcm();
    int total_samples = frames * channels_;
    if (pcm.size() < total_samples) return;

    const float *pcm_ptr = pcm.ptr();
    bool boosted = volume_gain_.load(std::memory_order_relaxed) != 1.0f;

    if (channels_ == 2 && !boosted) {
        bool written = audio_backend_->write_pcm(pcm_ptr, frames);
        _record_audio(pcm_ptr, channels_, pcm_ptr, 2, frames, written);
        return;
    }

    float stereo_buf[2048];
    int out_frames = frames < 1024 ? frames : 1024;
    if (channels_ == 2) {
        memcpy(stereo_buf, pcm_ptr, (size_t)out_frames * 2 * sizeof(float));
    } else if (channels_ > 2) {
        for (int i = 0; i < out_frames; i++) {
            _downmix_to_stereo(pcm_ptr + i * channels_, stereo_buf + i * 2);
        }
    } else {
        for (int i = 0; i < out_frames; i++) {
            stereo_buf[i * 2] = pcm_ptr[i];
            stereo_buf[i * 2 + 1] = pcm_ptr[i];
        }
    }
    if (boosted) {
        _apply_volume_boost(stereo_buf, out_frames * 2);
    }
    bool written = audio_backend_->write_pcm(stereo_buf, out_frames);
    _record_audio(pcm_ptr, channels_, stereo_buf, 2, out_frames, written);
}

void AudioRenderer::set_android_output(int output) {
    android_output_.store(output == 1 ? 1 : 0);
}

// Signal statistics only; no samples or recordings leave the audio callback.
// Summarize every five seconds of audio, including independent left/right levels.
void AudioRenderer::_record_audio(const float *decoded, int decoded_channels, const float *output, int output_channels, int frames, bool written) {
    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < 2; ++c) {
            float d = decoded[i * decoded_channels + (c < decoded_channels ? c : 0)];
            float o = output[i * output_channels + (c < output_channels ? c : 0)];
            decoded_energy_[c] += double(d) * d;
            output_energy_[c] += double(o) * o;
            decoded_peak_[c] = fmaxf(decoded_peak_[c], fabsf(d));
            output_peak_[c] = fmaxf(output_peak_[c], fabsf(o));
        }
    }
    diagnostic_frames_ += frames;
    if (!written) ++diagnostic_failures_;
    if (diagnostic_frames_ < uint64_t(sample_rate_) * 5) return;
    auto rms = [&](double energy) { return 10.0 * log10(fmax(energy / diagnostic_frames_, 1e-12)); };
    auto peak = [](float value) { return 20.0 * log10(fmax(double(value), 1e-6)); };
    char message[1024];
    snprintf(message, sizeof(message), "[AUDIO-LEVEL] backend=%s channels=%d->2 rate=%d boost=%.1fdB decoded_rms_LR=%.2f/%.2fdBFS decoded_peak_LR=%.2f/%.2fdBFS output_rms_LR=%.2f/%.2fdBFS output_peak_LR=%.2f/%.2fdBFS write_failures=%llu latency_ms=%d plc=%llu %s",
        audio_backend_->get_backend_name().c_str(), channels_, sample_rate_, volume_boost_db_.load(),
        rms(decoded_energy_[0]), rms(decoded_energy_[1]), peak(decoded_peak_[0]), peak(decoded_peak_[1]),
        rms(output_energy_[0]), rms(output_energy_[1]), peak(output_peak_[0]), peak(output_peak_[1]),
        static_cast<unsigned long long>(diagnostic_failures_), audio_backend_->get_latency_ms(), (unsigned long long)plc_frames_, audio_backend_->get_debug_stats().c_str());
#ifdef __ANDROID__
    nightfall::log_audio_diagnostic(message);
#else
    NF_LOG("AudioRenderer", "%s", message);
#endif
    diagnostic_frames_ = diagnostic_failures_ = 0;
    memset(decoded_energy_, 0, sizeof(decoded_energy_)); memset(output_energy_, 0, sizeof(output_energy_));
    memset(decoded_peak_, 0, sizeof(decoded_peak_)); memset(output_peak_, 0, sizeof(output_peak_));
}

// Some hosts send noticeably quiet audio (the same stream is equally quiet in
// Moonlight XR), so the user can boost it. Samples within the knee pass
// through unchanged; louder ones are compressed smoothly towards full scale
// instead of hard clipping.
void AudioRenderer::_apply_volume_boost(float *samples, int count) const {
    const float gain = volume_gain_.load(std::memory_order_relaxed);
    const float knee = 0.8f;
    for (int i = 0; i < count; i++) {
        float s = samples[i] * gain;
        float mag = fabsf(s);
        if (mag > knee) {
            mag = knee + (1.0f - knee) * tanhf((mag - knee) / (1.0f - knee));
            s = copysignf(mag, s);
        }
        samples[i] = s;
    }
}

void AudioRenderer::_downmix_to_stereo(const float *multi, float *stereo) {
    float left = 0.0f;
    float right = 0.0f;

    if (channels_ >= 1) left += multi[0];
    if (channels_ >= 2) right += multi[1];

    if (channels_ >= 3) {
        float center = multi[2];
        left += center * 0.7071f;
        right += center * 0.7071f;
    }
    if (channels_ >= 4) {
        float lfe = multi[3];
        left += lfe * 0.5f;
        right += lfe * 0.5f;
    }
    if (channels_ >= 5) left += multi[4] * 0.7071f;
    if (channels_ >= 6) right += multi[5] * 0.7071f;
    if (channels_ >= 7) left += multi[6] * 0.7071f;
    if (channels_ >= 8) right += multi[7] * 0.7071f;

    stereo[0] = left;
    stereo[1] = right;
}

bool AudioRenderer::is_initialized() const {
    return initialized_.load();
}

int AudioRenderer::get_channels() const {
    return channels_;
}

int AudioRenderer::get_sample_rate() const {
    return sample_rate_;
}

float AudioRenderer::get_latency_ms() const {
    if (audio_backend_) {
        return (float)audio_backend_->get_latency_ms();
    }
    return 0.0f;
}

String AudioRenderer::get_backend_name() const {
    if (audio_backend_) {
        return String(audio_backend_->get_backend_name().c_str());
    }
    return "none";
}

void AudioRenderer::play_local_pcm(const float *data, size_t frames) {
    if (audio_backend_ && running_.load()) {
        audio_backend_->write_pcm(data, frames);
    }
}

void AudioRenderer::set_muted(bool muted) {
    muted_.store(muted);
}

bool AudioRenderer::is_muted() const {
    return muted_.load();
}

void AudioRenderer::set_volume_boost_db(float db) {
    // Below -59 dB is mute (Steam Frame controller volume buttons go down too).
    if (db < -60.0f) db = -60.0f;
    if (db > 24.0f) db = 24.0f;
    volume_boost_db_.store(db);
    volume_gain_.store(db == 0.0f ? 1.0f : (db <= -59.0f ? 0.0f : powf(10.0f, db / 20.0f)));
}

float AudioRenderer::get_volume_boost_db() const {
    return volume_boost_db_.load();
}

void AudioRenderer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_android_output", "output"), &AudioRenderer::set_android_output);
    ClassDB::bind_method(D_METHOD("is_initialized"), &AudioRenderer::is_initialized);
    ClassDB::bind_method(D_METHOD("get_packets_received"), &AudioRenderer::get_packets_received);
    ClassDB::bind_method(D_METHOD("get_channels"), &AudioRenderer::get_channels);
    ClassDB::bind_method(D_METHOD("get_sample_rate"), &AudioRenderer::get_sample_rate);
    ClassDB::bind_method(D_METHOD("get_latency_ms"), &AudioRenderer::get_latency_ms);
    ClassDB::bind_method(D_METHOD("get_backend_name"), &AudioRenderer::get_backend_name);
    ClassDB::bind_method(D_METHOD("set_volume_boost_db", "db"), &AudioRenderer::set_volume_boost_db);
    ClassDB::bind_method(D_METHOD("get_volume_boost_db"), &AudioRenderer::get_volume_boost_db);
}
