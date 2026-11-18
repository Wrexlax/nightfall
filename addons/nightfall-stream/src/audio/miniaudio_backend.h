#pragma once

#include "platform_audio.h"
#include "spsc_ring.h"

struct ma_device;

namespace nightfall {

class MiniaudioBackend : public PlatformAudio {
public:
    MiniaudioBackend();
    ~MiniaudioBackend() override;

    bool initialize(int sample_rate, int channels, int buffer_frames) override;
    void shutdown() override;
    bool write_pcm(const float *data, size_t frames) override;
    void pause() override;
    void resume() override;
    int get_latency_ms() const override;
    std::string get_backend_name() const override;
    std::string get_debug_stats() const override;

private:
    static void _ma_data_callback(ma_device *pDevice, void *pOutput, const void *pInput, uint32_t frameCount);

    ma_device *device_ = nullptr;
    SpscRingBuffer<float> *ring_ = nullptr;
    int sample_rate_ = 48000;
    int channels_ = 2;
    std::atomic<bool> paused_{false};
    // Adaptive cap on queued audio: 40 ms normally (the original value), raised
    // to cover the gaps when packets arrive in bursts, then eased back down.
    std::atomic<int> target_ms_{40};
    int64_t last_write_us_ = 0;      // writer thread only
    int64_t last_decay_us_ = 0;      // writer thread only
    std::atomic<uint64_t> underruns_{0}, trims_{0}, overflows_{0};
    std::atomic<bool> initialized_{false};
};

} // namespace nightfall
