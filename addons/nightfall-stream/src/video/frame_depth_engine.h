#pragma once

// On-headset depth for the Steam Frame: a depth model run on the processor
// (LiteRT, formerly TensorFlow Lite, with its XNNPACK delegate), fed straight
// from the video decoder.
//
// Why the processor and not the graphics chip: at 144 Hz Nightfall's drawing
// already uses most of each frame's graphics time, while most processor cores
// sit idle (decoding is done in hardware). Moonlight XR for Frame measured
// this route on the headset itself (its docs/dev/reports/depth.md): ZipDepth
// 512x288 at 27 maps a second on two threads once the arithmetic is half
// precision, the 256 pixel 8-bit model above 100. The half-precision switch
// and the thread count come from that work.
//
// Why from the decoder: the Frame's decoder hands each picture over in
// ordinary memory (NV12). Shrinking it there to the model's size costs a
// fraction of a millisecond and reads nothing back from the graphics chip.
// Nightfall's desktop Linux path reads the picture back instead (2 to 6 ms
// on the main thread each time, measured on the Frame in 5h).
//
// On the graphics chip as well (a test, 7j): the same picture from the decoder
// can go to ncnn's Vulkan backend, the engine upstream's desktop Linux build
// uses, running the EdgePad 512x288 model that Meteor runs on the PC. At 90 Hz
// the graphics chip has time to spare that it did not have at 144, and the
// processor model slows voice typing. Whether it is better is for the headset
// to say.
//
// The output is what the rest of Nightfall already expects from its other
// depth engines (DepthEstimator.java, MidasDepthEngine): one byte per texel,
// rows top first, 255 nearest, the range stretched robustly and smoothed over
// time with the same constants.

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class FrameDepthEngine {
public:
    struct ModelSpec {
        const char *key;    // for logs
        const char *name;   // for people
        const char *file;   // in the package's depth_models/ folder
        int width;
        int height;
        bool half_precision;   // run the arithmetic in 16-bit floats
        bool graphics;         // run on the graphics chip (ncnn on Vulkan); `file` is then the name both of its files start with
    };
    static constexpr int MODEL_COUNT = 3;
    // Whether this build can run a model on the graphics chip at all.
    static bool graphics_engine_built();
    // Whether a model's file is (or files are) in the models folder.
    bool model_present(int model_index) const;
    static constexpr int DEFAULT_MODEL = 0;
    static constexpr int DEFAULT_RATE = 20;
    static constexpr int DEFAULT_THREADS = 2;
    static const ModelSpec &model_spec(int index);

    FrameDepthEngine();
    ~FrameDepthEngine();
    FrameDepthEngine(const FrameDepthEngine &) = delete;
    FrameDepthEngine &operator=(const FrameDepthEngine &) = delete;

    // Remembers where the models are and starts the model's thread. The model
    // itself is loaded on that thread the first time it is needed.
    void initialize(const std::string &model_dir);

    // The same calls the other engines answer (see MidasDepthEngine).
    void set_active_model(int model_index);
    int configure(int model_index, int requested_backend);   // returns the backend in force: 1, the processor
    int get_backend_capabilities(int) const { return 1; }
    std::string get_backend_status() const;                  // empty while all is well
    void submit_frame(const uint8_t *rgba, size_t rgba_len, int width, int height);
    std::vector<uint8_t> get_latest_depth();                 // empty when there is nothing newer
    float get_last_inference_ms() const { return last_model_ms_.load(); }
    float get_last_inference_hz() const { return maps_per_second_.load(); }
    float get_last_age_ms() const { return last_age_ms_.load(); }
    // A picture is only taken when the model is free, so none is ever skipped.
    int get_last_skipped_frames() const { return 0; }
    int get_model_size() const { return get_model_width(); }
    int get_model_width() const;
    int get_model_height() const;

    // Maps a second to aim for (1 to 120).
    void set_rate(int per_second);
    // Processor threads for the model, 1 to 4. Takes effect when the model is
    // next loaded.
    void set_threads(int threads);
    // Whether the decoder should feed the model at all.
    void set_tap_enabled(bool enabled);
    // The part of each decoded picture to look at, as fractions of its width
    // and height (the primary screen's share of a multi-monitor stream).
    void set_region(float x, float y, float width, float height);

    // The decoder's side. frame_wanted() is cheap enough to ask every frame.
    bool frame_wanted() const;
    void offer_nv12(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch, int width, int height);
    // Offers a decoded picture to whichever engine is taking them (none: a
    // quick no-op). Safe against that engine going away meanwhile.
    static void tap_nv12(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch, int width, int height);

    // One line of figures since the last call, for the log.
    std::string take_report();

    // The two steps on their own, for tests.
    static void shrink_nv12_to_rgb(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch,
                                   int src_x, int src_y, int src_w, int src_h,
                                   int out_w, int out_h, uint8_t *rgb_out);
    struct Smoothing;   // the state post_process keeps between maps
    static std::vector<uint8_t> post_process(Smoothing &state, const float *raw, int count, int64_t now_ns);
    static std::unique_ptr<Smoothing, void (*)(Smoothing *)> make_smoothing();

    struct Loaded;   // a model in memory; its two kinds are in the .cpp

private:

    void worker_loop();
    void set_status(const std::string &status);

    std::string model_dir_;
    std::thread worker_;
    bool initialized_ = false;

    // What the app asked for.
    std::atomic<int> wanted_model_{DEFAULT_MODEL};
    std::atomic<int> failed_model_{-1};   // one that would not load
    std::atomic<int> threads_{DEFAULT_THREADS};
    std::atomic<int64_t> period_ns_{1000000000LL / DEFAULT_RATE};
    std::atomic<bool> tap_enabled_{false};
    std::atomic<float> region_[4];

    // The model in force, for the decoder's thread to size its picture by.
    std::atomic<int> width_{0};
    std::atomic<int> height_{0};
    std::atomic<bool> ready_{false};

    // The newest picture waiting for the model (RGB bytes at the model's size).
    mutable std::mutex pending_mutex_;
    std::condition_variable pending_cv_;
    std::vector<uint8_t> pending_rgb_;
    int pending_width_ = 0;
    int pending_height_ = 0;
    int64_t pending_capture_ns_ = 0;
    bool has_pending_ = false;
    bool shutdown_ = false;
    std::atomic<int64_t> next_due_ns_{0};

    // The newest finished map.
    std::mutex result_mutex_;
    std::vector<uint8_t> result_;
    bool has_result_ = false;

    mutable std::mutex status_mutex_;
    std::string status_;

    // Figures.
    std::atomic<float> last_model_ms_{0.0f};
    std::atomic<float> maps_per_second_{0.0f};
    std::atomic<float> last_age_ms_{0.0f};
    std::mutex report_mutex_;
    int report_maps_ = 0;
    int report_offered_ = 0;
    double report_model_ms_sum_ = 0.0;
    float report_model_ms_max_ = 0.0f;
    double report_shrink_ms_sum_ = 0.0;
    float report_shrink_ms_max_ = 0.0f;
    double report_age_ms_sum_ = 0.0;
    int64_t report_start_ns_ = 0;
    int64_t report_cpu_start_ns_ = 0;
};
