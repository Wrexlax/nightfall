#pragma once

#include <cstdint>
#include <string>

namespace nightfall {

class PlatformAudio {
public:
    virtual ~PlatformAudio() = default;

    virtual bool initialize(int sample_rate, int channels, int buffer_frames) = 0;
    virtual void shutdown() = 0;
    virtual bool write_pcm(const float* data, size_t frames) = 0;
    virtual void pause() = 0;
    virtual void resume() = 0;
    virtual int get_latency_ms() const = 0;

    virtual std::string get_backend_name() const = 0;
    // Optional one-line buffer diagnostics (underruns etc.) for the log.
    virtual std::string get_debug_stats() const { return std::string(); }
};

} // namespace nightfall
