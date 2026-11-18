#include <cstdio>
#include <chrono>
#include <thread>
#include <string>
#include "miniaudio_backend.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>
#pragma GCC diagnostic pop

#include "nf_log.h"

namespace nightfall {

MiniaudioBackend::MiniaudioBackend() {}

MiniaudioBackend::~MiniaudioBackend() {
    shutdown();
}

void MiniaudioBackend::_ma_data_callback(ma_device *pDevice, void *pOutput, const void * /*pInput*/, uint32_t frameCount) {
    auto *self = static_cast<MiniaudioBackend *>(pDevice->pUserData);
    if (!self || !self->ring_ || self->paused_.load(std::memory_order_relaxed)) {
        memset(pOutput, 0, frameCount * 2 * sizeof(float));
        return;
    }

    // Same behaviour as the original backend (play what is buffered, fill
    // any shortfall with silence, keep at most ~40 ms queued), except the
    // 40 ms trim now happens here on the reading side: trimming from the
    // network thread raced with this callback over the read position.
    const int ch = self->channels_ > 0 ? self->channels_ : 2;
    float *out = static_cast<float *>(pOutput);
    const size_t total_samples = (size_t)frameCount * ch;
    const size_t max_buffered = (size_t)self->sample_rate_ * ch * (size_t)self->target_ms_.load(std::memory_order_relaxed) / 1000;

    size_t avail = self->ring_->read_available();
    if (avail > max_buffered + total_samples) {
        self->ring_->discard(avail - max_buffered - total_samples);
        self->trims_.fetch_add(1, std::memory_order_relaxed);
    }

    size_t read = self->ring_->read(out, total_samples);
    if (read < total_samples) {
        memset(out + read, 0, (total_samples - read) * sizeof(float));
        if (read > 0) self->underruns_.fetch_add(1, std::memory_order_relaxed);
    }
}

bool MiniaudioBackend::initialize(int sample_rate, int channels, int buffer_frames) {
    if (initialized_.load()) return true;

    sample_rate_ = sample_rate;
    channels_ = channels;

    size_t ring_size = (size_t)(sample_rate * channels * 0.2);
    size_t pow2 = 1;
    while (pow2 < ring_size) pow2 <<= 1;
    ring_ = new SpscRingBuffer<float>(pow2);

    device_ = new ma_device();
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = (ma_uint32)channels;
    config.sampleRate = (ma_uint32)sample_rate;
    config.periodSizeInFrames = (ma_uint32)buffer_frames;
    config.dataCallback = _ma_data_callback;
    config.pUserData = this;
    // "virtual" + "sink" in the name: SteamOS leaves the stream out of its
    // system spatializer (see the node.name patch in miniaudio.h).
    // Plain stream name (test, 2026-11-08): "Nightfall virtual sink" made
    // SteamOS skip Valve's spatializer (Moonlight XR's trick), but installing a
    // build then left the headset volume buttons running away. Let SteamOS
    // treat Nightfall like any other app and judge the sound by ear.
    config.pulse.pStreamNamePlayback = "Nightfall";

    ma_result result = ma_device_init(nullptr, &config, device_);
    if (result != MA_SUCCESS) {
        NF_LOG("MiniaudioBackend", "Init failed: %d", result);
        delete device_;
        device_ = nullptr;
        delete ring_;
        ring_ = nullptr;
        return false;
    }

    result = ma_device_start(device_);
    if (result != MA_SUCCESS) {
        NF_LOG("MiniaudioBackend", "Start failed: %d", result);
        ma_device_uninit(device_);
        delete device_;
        device_ = nullptr;
        delete ring_;
        ring_ = nullptr;
        return false;
    }

    initialized_.store(true);
#if defined(__linux__) && !defined(__ANDROID__)
    {
        // Diagnostics: 10 s after playback starts, log how PipeWire routes our
        // audio (is SteamOS's spatializer filter chain in the path?).
        std::thread([] {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            const char *cmd =
                "(command -v pw-cli >/dev/null && pw-cli ls Node | grep -E 'id [0-9]+,|node.name|node.description|media.class|application.name|application.process.id|target.object'); "
                "(command -v wpctl >/dev/null && wpctl status | sed -n '/^Audio/,/^Video/p'); "
                "echo \"pid=$PPID\"";
            FILE *f = popen(cmd, "r");
            if (!f) { NF_LOG("MiniaudioBackend", "[AUDIO-NODES] popen failed"); return; }
            char line[512];
            int n = 0;
            while (fgets(line, sizeof(line), f) && n < 400) {
                size_t len = strlen(line);
                while (len && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = 0;
                NF_LOG("MiniaudioBackend", "[AUDIO-NODES] %s", line);
                n++;
            }
            pclose(f);
        }).detach();
    }
#endif
    NF_LOG("MiniaudioBackend", "Initialized: %dHz %dch, period=%d, backend=%s",
           sample_rate, channels, buffer_frames, ma_get_backend_name(device_->pContext->backend));
    return true;
}

void MiniaudioBackend::shutdown() {
    if (!initialized_.load()) return;

    initialized_.store(false);

    if (device_) {
        ma_device_stop(device_);
        ma_device_uninit(device_);
        delete device_;
        device_ = nullptr;
    }

    if (ring_) {
        delete ring_;
        ring_ = nullptr;
    }
}

bool MiniaudioBackend::write_pcm(const float *data, size_t frames) {
    if (!ring_ || !initialized_.load()) return false;

    const int64_t now_us = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    if (last_write_us_ != 0) {
        const int gap_ms = (int)((now_us - last_write_us_) / 1000);
        int target = target_ms_.load(std::memory_order_relaxed);
        // 20-300 ms gaps are network bursts; longer ones are the host going
        // quiet (e.g. a paused video) and say nothing about jitter.
        if (gap_ms >= 20 && gap_ms <= 300 && gap_ms + 25 > target) {
            target = gap_ms + 25 > 200 ? 200 : gap_ms + 25;
            target_ms_.store(target, std::memory_order_relaxed);
            last_decay_us_ = now_us;
        } else if (target > 40 && now_us - last_decay_us_ > 1000000) {
            // Ease back 5 ms a second once things are calm.
            target_ms_.store(target - 5 < 40 ? 40 : target - 5, std::memory_order_relaxed);
            last_decay_us_ = now_us;
        }
    }
    last_write_us_ = now_us;

    size_t samples = frames * (size_t)channels_;
    size_t written = ring_->write(data, samples);
    if (written != samples) overflows_.fetch_add(1, std::memory_order_relaxed);
    return written == samples;
}

void MiniaudioBackend::pause() {
    paused_.store(true);
    if (device_) ma_device_stop(device_);
}

void MiniaudioBackend::resume() {
    paused_.store(false);
    if (device_) ma_device_start(device_);
}

int MiniaudioBackend::get_latency_ms() const {
    if (!ring_ || !initialized_.load()) return 0;
    size_t avail = ring_->read_available();
    int frames = (int)(avail / (size_t)channels_);
    if (sample_rate_ > 0) {
        return frames * 1000 / sample_rate_;
    }
    return 0;
}

std::string MiniaudioBackend::get_debug_stats() const {
    char buf[128];
    snprintf(buf, sizeof(buf), "target=%dms underruns=%llu trims=%llu overflows=%llu", target_ms_.load(),
             (unsigned long long)underruns_.load(), (unsigned long long)trims_.load(),
             (unsigned long long)overflows_.load());
    return buf;
}

std::string MiniaudioBackend::get_backend_name() const {
    if (device_ && device_->pContext) {
        return ma_get_backend_name(device_->pContext->backend);
    }
    return "miniaudio";
}

} // namespace nightfall
