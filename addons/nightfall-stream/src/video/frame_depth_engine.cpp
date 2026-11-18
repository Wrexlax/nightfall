#include "frame_depth_engine.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>

#include <cerrno>
#include <pthread.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "tensorflow/lite/c/c_api.h"
#include "tensorflow/lite/delegates/xnnpack/xnnpack_delegate.h"

#ifdef NIGHTFALL_FRAME_NCNN
#include "gpu.h"
#include "net.h"
// Added to ncnn by steam-frame/ncnn-low-priority.patch, which says why they
// are declared here and not in ncnn's own header.
namespace ncnn {
void frame_ask_low_queue_priority(int wanted);
int frame_low_queue_priority_state();
}
#endif

#include "nf_log.h"

namespace {

// Moonlight XR's exports of ZipDepth (Fabio Tosi, MIT), the same files its
// Steam Frame build ships. Both take plain RGB 0..1 and give relative inverse
// depth (larger is nearer) at the input's size.
//
// The third is upstream Nightfall's own export of the same network ("EdgePad",
// with a rebuilt output stage), in ncnn's format with full-precision weights:
// the file Meteor's Windows installer puts on the PC. Same input and output.
const FrameDepthEngine::ModelSpec MODELS[FrameDepthEngine::MODEL_COUNT] = {
    { "zipdepth-512", "ZipDepth 512x288", "zipdepth_512x288_fp16.tflite", 512, 288, true, false },
    { "zipdepth-256", "ZipDepth 256 (8-bit)", "zipdepth_256_int8dr.tflite", 256, 256, true, false },
    { "edgepad-512-gpu", "EdgePad 512x288 on the graphics chip", "zipdepth_wide_512x288", 512, 288, true, true },
};

// The smoothing the other engines use (DepthEstimator.java, MidasDepthEngine),
// so a map from here behaves in the warp as theirs do.
constexpr int HIST_BINS = 512;
constexpr float PERCENTILE_CLIP = 0.02f;
constexpr float RANGE_TAU_SECONDS = 0.89f;
constexpr float DEPTH_TAU_SECONDS = 0.158f;

constexpr int WARMUP_RUNS = 2;
// How far the model's threads stand back for the rest of the app (0 normal,
// 19 the most). In 6x they ran at 0, flat out: voice typing took 2.6 times as
// long as without (0.91 against 0.35 of the speech's length) and the longest
// frame each second went from 12-18 ms to 22-28.
constexpr int DEPTH_NICE = 10;
// Samples taken each way under one output pixel when shrinking: enough to
// keep thin lines from flickering in and out, cheap enough for the decoder's
// thread.
constexpr int MAX_TAPS = 3;

int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
}

// The processor's clocks, fastest group first, with any that heat has capped:
// "3302, 3148 (capped 2592), 2265 MHz".
std::string cpu_clocks() {
    std::string out;
    for (int policy = 7; policy >= 0; policy--) {
        const std::string base = "/sys/devices/system/cpu/cpufreq/policy" + std::to_string(policy) + "/";
        long now_khz = 0, limit_khz = 0, top_khz = 0;
        std::ifstream now_file(base + "scaling_cur_freq"), limit_file(base + "scaling_max_freq"), top_file(base + "cpuinfo_max_freq");
        if (!(now_file >> now_khz)) continue;
        limit_file >> limit_khz;
        top_file >> top_khz;
        if (!out.empty()) out += ", ";
        out += std::to_string(now_khz / 1000);
        if (limit_khz > 0 && top_khz > 0 && limit_khz < top_khz) out += " (capped " + std::to_string(limit_khz / 1000) + ")";
    }
    return out.empty() ? "not reported" : out + " MHz";
}

int64_t process_cpu_ns() {
    timespec ts;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) != 0) return 0;
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

// The decoder offers its pictures to this engine. Guarded so an engine can go
// away while the decoder's thread is mid-offer.
std::mutex g_tap_mutex;
FrameDepthEngine *g_tap = nullptr;
std::atomic<bool> g_tap_present{false};

thread_local std::string t_model_error;

void report_model_error(void *, const char *format, va_list args) {
    char text[512];
    vsnprintf(text, sizeof text, format, args);
    t_model_error = text;
}

} // namespace

// A model in memory. Two kinds: LiteRT on the processor, ncnn on the graphics chip.
struct FrameDepthEngine::Loaded {
    int index = -1;
    int width = 0;
    int height = 0;
    float load_ms = 0.0f;
    std::string where;   // for the log: "2 threads, half-precision arithmetic"

    virtual ~Loaded() = default;
    // Runs the model on a picture (width x height RGB bytes). The raw map
    // (width x height floats, larger is nearer) or nullptr, with the reason
    // in `why`. The map stays valid until the next run.
    virtual const float *run(const uint8_t *rgb, std::string *why) = 0;
};

namespace {

bool read_file(const std::string &path, std::vector<char> *out) {
    FILE *file = fopen(path.c_str(), "rb");
    if (!file) return false;
    fseek(file, 0, SEEK_END);
    const long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    out->resize(size > 0 ? (size_t)size : 0);
    const bool ok = size > 0 && fread(out->data(), 1, (size_t)size, file) == (size_t)size;
    fclose(file);
    return ok;
}

bool holds_floats(const TfLiteTensor *tensor, size_t count) {
    return tensor != nullptr && TfLiteTensorType(tensor) == kTfLiteFloat32
            && TfLiteTensorByteSize(tensor) == count * sizeof(float);
}

struct ProcessorModel : FrameDepthEngine::Loaded {
    std::vector<char> bytes;
    TfLiteModel *model = nullptr;
    TfLiteDelegate *xnnpack = nullptr;
    TfLiteInterpreterOptions *options = nullptr;
    TfLiteInterpreter *interpreter = nullptr;
    TfLiteTensor *input = nullptr;
    const TfLiteTensor *output = nullptr;

    ~ProcessorModel() override {
        if (interpreter) TfLiteInterpreterDelete(interpreter);
        if (options) TfLiteInterpreterOptionsDelete(options);
        if (xnnpack) TfLiteXNNPackDelegateDelete(xnnpack);
        if (model) TfLiteModelDelete(model);
    }

    // Empty when loaded, else why not.
    std::string load(const FrameDepthEngine::ModelSpec &spec, const std::string &model_dir, int threads) {
        const std::string path = model_dir + "/" + spec.file;
        t_model_error.clear();
        if (!read_file(path, &bytes)) return "the model file is missing (" + path + ")";
        model = TfLiteModelCreate(bytes.data(), bytes.size());
        if (model == nullptr) return std::string(spec.file) + " is not a model LiteRT can read";
        TfLiteXNNPackDelegateOptions xnn = TfLiteXNNPackDelegateOptionsDefault();
        xnn.num_threads = threads;
        if (spec.half_precision) xnn.flags |= TFLITE_XNNPACK_DELEGATE_FLAG_FORCE_FP16;
        xnnpack = TfLiteXNNPackDelegateCreate(&xnn);
        options = TfLiteInterpreterOptionsCreate();
        TfLiteInterpreterOptionsSetNumThreads(options, threads);
        TfLiteInterpreterOptionsSetErrorReporter(options, report_model_error, nullptr);
        if (xnnpack) TfLiteInterpreterOptionsAddDelegate(options, xnnpack);
        interpreter = TfLiteInterpreterCreate(model, options);
        if (xnnpack == nullptr) return "the fast processor path (XNNPACK) could not start";
        if (interpreter == nullptr) return "the model could not be set up: " + t_model_error;
        if (TfLiteInterpreterAllocateTensors(interpreter) != kTfLiteOk) return "the model's memory could not be set up: " + t_model_error;
        input = TfLiteInterpreterGetInputTensor(interpreter, 0);
        output = TfLiteInterpreterGetOutputTensor(interpreter, 0);
        if (input == nullptr || TfLiteTensorType(input) != kTfLiteFloat32 || TfLiteTensorNumDims(input) != 4
                || TfLiteTensorDim(input, 0) != 1 || TfLiteTensorDim(input, 3) != 3) {
            return "the model's input is not one RGB picture";
        }
        height = TfLiteTensorDim(input, 1);
        width = TfLiteTensorDim(input, 2);
        if (width != spec.width || height != spec.height) return std::string(spec.file) + " is not the size expected of it";
        if (!holds_floats(output, (size_t)width * height)) return "the model's output is not a depth map the size of its input";
        where = std::to_string(threads) + " threads, " + (spec.half_precision ? "half-precision" : "full-precision") + " arithmetic";
        return "";
    }

    const float *run(const uint8_t *rgb, std::string *why) override {
        float *in = (float *)TfLiteTensorData(input);
        const float k = 1.0f / 255.0f;
        for (size_t i = 0, n = (size_t)width * height * 3; i < n; i++) in[i] = rgb[i] * k;
        if (TfLiteInterpreterInvoke(interpreter) != kTfLiteOk) {
            *why = t_model_error;
            return nullptr;
        }
        return (const float *)TfLiteTensorData(output);
    }
};

#ifdef NIGHTFALL_FRAME_NCNN
// ncnn keeps one Vulkan instance for the whole program, apart from Godot's.
// Set NIGHTFALL_NCNN_PROCESSOR_OK=1 to let the model run on the processor
// where there is no graphics chip to use (the build machine's tests); on the
// headset that would only mislead, so there it is an error.
struct GraphicsModel : FrameDepthEngine::Loaded {
    ncnn::Net net;
    ncnn::Mat input;
    ncnn::Mat output;

    std::string load(const FrameDepthEngine::ModelSpec &spec, const std::string &model_dir) {
        const std::string base = model_dir + "/" + spec.file;
        const bool processor_ok = getenv("NIGHTFALL_NCNN_PROCESSOR_OK") != nullptr;
        // The model shares the graphics chip with Nightfall's own drawing,
        // which must come first: ask the driver to rank the model's work low.
        // It has to be asked before ncnn first sets the chip up.
        ncnn::frame_ask_low_queue_priority(1);
        bool graphics = ncnn::create_gpu_instance() == 0 && ncnn::get_gpu_count() > 0;
        if (!graphics && !processor_ok) return "no graphics chip that Vulkan can use was found";
        net.opt.use_vulkan_compute = graphics;
        // As Meteor runs this file: weights and pictures stored in half
        // precision, the sums done in full (its models/README.md measured
        // that against the full-precision model).
        net.opt.use_fp16_packed = true;
        net.opt.use_fp16_storage = true;
        net.opt.use_fp16_arithmetic = false;
        net.opt.num_threads = 1;
        if (graphics) net.set_vulkan_device(ncnn::get_default_gpu_index());
        if (net.load_param((base + ".ncnn.param").c_str()) != 0) return "the model's description is missing or unreadable (" + base + ".ncnn.param)";
        if (net.load_model((base + ".ncnn.bin").c_str()) != 0) return "the model's weights are missing or unreadable (" + base + ".ncnn.bin)";
        width = spec.width;
        height = spec.height;
        input.create(width, height, 3);
        if (input.empty()) return "no memory for the model's input";
        where = graphics ? std::string("graphics chip: ") + ncnn::get_gpu_info(ncnn::get_default_gpu_index()).device_name() + ", " + low_priority_answer()
                         : std::string("processor (no graphics chip found; test only)");
        return "";
    }

    // What the driver made of the request for low priority, for the log.
    static const char *low_priority_answer() {
        switch (ncnn::frame_low_queue_priority_state()) {
            case 1: return "low priority: taken by the driver";
            case -1: return "low priority: not offered by the driver";
            case -2: return "low priority: refused by the driver";
            default: return "low priority: not asked";
        }
    }

    const float *run(const uint8_t *rgb, std::string *why) override {
        // Three planes, red, green, blue, each 0 to 1.
        const size_t count = (size_t)width * height;
        float *r = input.channel(0);
        float *g = input.channel(1);
        float *b = input.channel(2);
        const float k = 1.0f / 255.0f;
        for (size_t i = 0; i < count; i++) {
            r[i] = rgb[i * 3] * k;
            g[i] = rgb[i * 3 + 1] * k;
            b[i] = rgb[i * 3 + 2] * k;
        }
        ncnn::Extractor run = net.create_extractor();
        if (run.input("in0", input) != 0 || run.extract("out0", output) != 0) {
            *why = "the model did not run";
            return nullptr;
        }
        if (output.w != width || output.h != height || output.c != 1 || output.elemsize != sizeof(float)) {
            *why = "the model's output is not a depth map the size of its input";
            return nullptr;
        }
        return (const float *)output.data;
    }
};
#endif

} // namespace

bool FrameDepthEngine::graphics_engine_built() {
#ifdef NIGHTFALL_FRAME_NCNN
    return true;
#else
    return false;
#endif
}

bool FrameDepthEngine::model_present(int model_index) const {
    if (model_index < 0 || model_index >= MODEL_COUNT) return false;
    const ModelSpec &spec = MODELS[model_index];
    if (spec.graphics && !graphics_engine_built()) return false;
    const std::string path = model_dir_ + "/" + spec.file + (spec.graphics ? ".ncnn.param" : "");
    return access(path.c_str(), R_OK) == 0;
}

struct FrameDepthEngine::Smoothing {
    std::vector<float> depth;
    float lo = 0.0f;
    float hi = 1.0f;
    bool range_valid = false;
    int64_t last_ns = 0;
};

std::unique_ptr<FrameDepthEngine::Smoothing, void (*)(FrameDepthEngine::Smoothing *)> FrameDepthEngine::make_smoothing() {
    return std::unique_ptr<Smoothing, void (*)(Smoothing *)>(new Smoothing(), [](Smoothing *s) { delete s; });
}

const FrameDepthEngine::ModelSpec &FrameDepthEngine::model_spec(int index) {
    return MODELS[std::max(0, std::min(MODEL_COUNT - 1, index))];
}

FrameDepthEngine::FrameDepthEngine() {
    region_[0].store(0.0f);
    region_[1].store(0.0f);
    region_[2].store(1.0f);
    region_[3].store(1.0f);
}

FrameDepthEngine::~FrameDepthEngine() {
    {
        std::lock_guard<std::mutex> lock(g_tap_mutex);
        if (g_tap == this) {
            g_tap = nullptr;
            g_tap_present.store(false);
        }
    }
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        shutdown_ = true;
    }
    pending_cv_.notify_all();
    if (worker_.joinable()) worker_.join();
}

void FrameDepthEngine::initialize(const std::string &model_dir) {
    if (initialized_) return;
    initialized_ = true;
    model_dir_ = model_dir;
    worker_ = std::thread(&FrameDepthEngine::worker_loop, this);
    std::lock_guard<std::mutex> lock(g_tap_mutex);
    g_tap = this;
    g_tap_present.store(true);
}

void FrameDepthEngine::set_active_model(int model_index) {
    wanted_model_.store(std::max(0, std::min(MODEL_COUNT - 1, model_index)));
    failed_model_.store(-1);
    pending_cv_.notify_all();
}

int FrameDepthEngine::configure(int model_index, int) {
    set_active_model(model_index);
    return 1;
}

std::string FrameDepthEngine::get_backend_status() const {
    std::lock_guard<std::mutex> lock(status_mutex_);
    return status_;
}

void FrameDepthEngine::set_status(const std::string &status) {
    std::lock_guard<std::mutex> lock(status_mutex_);
    status_ = status;
}

// The chosen model's size, not the size of whichever is still in memory: the
// app sizes its depth texture by this the moment it switches models, before
// the new one has loaded. (6x answered with the loaded model's size; after a
// switch the app then waited for maps of the old size and showed none.)
int FrameDepthEngine::get_model_width() const {
    return model_spec(wanted_model_.load()).width;
}

int FrameDepthEngine::get_model_height() const {
    return model_spec(wanted_model_.load()).height;
}

void FrameDepthEngine::set_rate(int per_second) {
    period_ns_.store(1000000000LL / std::max(1, std::min(120, per_second)));
}

void FrameDepthEngine::set_threads(int threads) {
    threads_.store(std::max(1, std::min(4, threads)));
}

void FrameDepthEngine::set_tap_enabled(bool enabled) {
    if (tap_enabled_.exchange(enabled) != enabled) {
        NF_LOG("FrameDepth", "on-headset depth %s", enabled ? "wanted" : "not wanted");
        // Switching it on again is a reason to try a model that failed before.
        if (enabled) failed_model_.store(-1);
        pending_cv_.notify_all();
    }
}

void FrameDepthEngine::set_region(float x, float y, float width, float height) {
    region_[0].store(std::max(0.0f, std::min(1.0f, x)));
    region_[1].store(std::max(0.0f, std::min(1.0f, y)));
    region_[2].store(std::max(0.0f, std::min(1.0f, width)));
    region_[3].store(std::max(0.0f, std::min(1.0f, height)));
}

// ---------------------------------------------------------------------------
// The decoder's side

void FrameDepthEngine::tap_nv12(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch, int width, int height) {
    if (!g_tap_present.load(std::memory_order_relaxed)) return;
    std::lock_guard<std::mutex> lock(g_tap_mutex);
    if (g_tap && g_tap->frame_wanted()) g_tap->offer_nv12(y, y_pitch, uv, uv_pitch, width, height);
}

// A picture is taken only when the model is free to start on it at once (so
// it never works on a stale one) and the rate allows another map.
bool FrameDepthEngine::frame_wanted() const {
    if (!tap_enabled_.load(std::memory_order_relaxed) || !ready_.load(std::memory_order_relaxed)) return false;
    if (now_ns() < next_due_ns_.load(std::memory_order_relaxed)) return false;
    std::lock_guard<std::mutex> lock(pending_mutex_);
    return !has_pending_;
}

void FrameDepthEngine::offer_nv12(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch, int width, int height) {
    const int out_w = width_.load();
    const int out_h = height_.load();
    if (out_w <= 0 || out_h <= 0 || width < 2 || height < 2) return;
    const int64_t start = now_ns();

    // The region in whole, even pixels (the colour plane is half size).
    int src_x = (int)std::lround(region_[0].load() * width) & ~1;
    int src_y = (int)std::lround(region_[1].load() * height) & ~1;
    int src_w = (int)std::lround(region_[2].load() * width) & ~1;
    int src_h = (int)std::lround(region_[3].load() * height) & ~1;
    src_x = std::max(0, std::min(width - 2, src_x));
    src_y = std::max(0, std::min(height - 2, src_y));
    src_w = std::max(2, std::min(width - src_x, src_w));
    src_h = std::max(2, std::min(height - src_y, src_h));

    std::vector<uint8_t> rgb((size_t)out_w * out_h * 3);
    shrink_nv12_to_rgb(y, y_pitch, uv, uv_pitch, src_x, src_y, src_w, src_h, out_w, out_h, rgb.data());
    const int64_t done = now_ns();
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        pending_rgb_.swap(rgb);
        pending_width_ = out_w;
        pending_height_ = out_h;
        pending_capture_ns_ = start;
        has_pending_ = true;
    }
    next_due_ns_.store(start + period_ns_.load());
    pending_cv_.notify_all();

    const float ms = (float)(done - start) / 1e6f;
    std::lock_guard<std::mutex> lock(report_mutex_);
    report_offered_++;
    report_shrink_ms_sum_ += ms;
    report_shrink_ms_max_ = std::max(report_shrink_ms_max_, ms);
}

// Shrinks a region of an NV12 picture (BT.709, video range: what the Frame's
// decoder delivers) to out_w x out_h RGB bytes, averaging a few samples under
// each output pixel.
void FrameDepthEngine::shrink_nv12_to_rgb(const uint8_t *y, int y_pitch, const uint8_t *uv, int uv_pitch,
                                          int src_x, int src_y, int src_w, int src_h,
                                          int out_w, int out_h, uint8_t *rgb_out) {
    const int taps_x = std::max(1, std::min(MAX_TAPS, src_w / out_w));
    const int taps_y = std::max(1, std::min(MAX_TAPS, src_h / out_h));
    // Where each output column samples the source (taps_x columns apiece).
    std::vector<int> columns((size_t)out_w * taps_x);
    for (int ox = 0; ox < out_w; ox++) {
        for (int t = 0; t < taps_x; t++) {
            // Sample points spread evenly across the pixel's share of the source.
            int64_t pos = ((int64_t)(2 * (ox * taps_x + t) + 1) * src_w) / ((int64_t)2 * out_w * taps_x);
            columns[(size_t)ox * taps_x + t] = src_x + (int)std::min<int64_t>(pos, src_w - 1);
        }
    }
    const int taps = taps_x * taps_y;
    for (int oy = 0; oy < out_h; oy++) {
        const uint8_t *rows[MAX_TAPS];
        for (int t = 0; t < taps_y; t++) {
            int64_t pos = ((int64_t)(2 * (oy * taps_y + t) + 1) * src_h) / ((int64_t)2 * out_h * taps_y);
            rows[t] = y + (size_t)(src_y + (int)std::min<int64_t>(pos, src_h - 1)) * y_pitch;
        }
        // Colour: one sample from the middle of the pixel's share.
        const int centre_row = src_y + (int)(((int64_t)(2 * oy + 1) * src_h) / ((int64_t)2 * out_h));
        const uint8_t *uv_row = uv + (size_t)(std::min(centre_row, src_y + src_h - 1) / 2) * uv_pitch;
        uint8_t *out = rgb_out + (size_t)oy * out_w * 3;
        const int *col = columns.data();
        for (int ox = 0; ox < out_w; ox++, col += taps_x) {
            int sum = 0;
            for (int ty = 0; ty < taps_y; ty++) {
                const uint8_t *row = rows[ty];
                for (int tx = 0; tx < taps_x; tx++) sum += row[col[tx]];
            }
            const int luma = sum / taps;
            const int centre_col = col[taps_x / 2] & ~1;
            const int u = uv_row[centre_col] - 128;
            const int v = uv_row[centre_col + 1] - 128;
            // BT.709, video range (16..235 luma), in 1/1024ths.
            const int c = (luma - 16) * 1192;
            const int r = (c + 1836 * v) >> 10;
            const int g = (c - 218 * u - 546 * v) >> 10;
            const int b = (c + 2163 * u) >> 10;
            out[ox * 3 + 0] = (uint8_t)std::max(0, std::min(255, r));
            out[ox * 3 + 1] = (uint8_t)std::max(0, std::min(255, g));
            out[ox * 3 + 2] = (uint8_t)std::max(0, std::min(255, b));
        }
    }
}

// A picture already at the model's size, as RGBA bytes with rows top first
// (what the other engines are given). Lets the app feed the model itself.
void FrameDepthEngine::submit_frame(const uint8_t *rgba, size_t rgba_len, int width, int height) {
    if (!ready_.load() || width != width_.load() || height != height_.load()) return;
    if (rgba == nullptr || rgba_len < (size_t)width * height * 4) return;
    std::vector<uint8_t> rgb((size_t)width * height * 3);
    for (size_t i = 0, n = (size_t)width * height; i < n; i++) {
        rgb[i * 3 + 0] = rgba[i * 4 + 0];
        rgb[i * 3 + 1] = rgba[i * 4 + 1];
        rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    {
        std::lock_guard<std::mutex> lock(pending_mutex_);
        pending_rgb_.swap(rgb);
        pending_width_ = width;
        pending_height_ = height;
        pending_capture_ns_ = now_ns();
        has_pending_ = true;
    }
    pending_cv_.notify_all();
}

std::vector<uint8_t> FrameDepthEngine::get_latest_depth() {
    std::lock_guard<std::mutex> lock(result_mutex_);
    if (!has_result_) return {};
    has_result_ = false;
    // A map finished by the model that was just switched away from is no use
    // to anyone.
    if (result_.size() != (size_t)get_model_width() * get_model_height()) return {};
    return std::move(result_);
}

// ---------------------------------------------------------------------------
// The model's thread

void FrameDepthEngine::worker_loop() {
    pthread_setname_np(pthread_self(), "nf-depth");
    // Depth is the one job here that can wait: a map a few milliseconds later
    // costs nothing, a late frame or a slow voice typing does. On Linux a
    // thread has its own nice value and threads it starts inherit it
    // (sched(7)), so XNNPACK's workers, started from this thread when a model
    // loads, get the same.
    if (setpriority(PRIO_PROCESS, (id_t)syscall(SYS_gettid), DEPTH_NICE) != 0) {
        NF_LOG("FrameDepth", "the depth threads keep normal priority (%s)", strerror(errno));
    }
    std::unique_ptr<Loaded> loaded;
    int loaded_threads = 0;
    auto smoothing = make_smoothing();
    int64_t rate_window_start = 0;
    int rate_window_maps = 0;

    for (;;) {
        std::vector<uint8_t> rgb;
        int64_t capture_ns = 0;
        bool have_frame = false;
        {
            std::unique_lock<std::mutex> lock(pending_mutex_);
            pending_cv_.wait(lock, [&] {
                if (shutdown_ || has_pending_) return true;
                const int wanted = wanted_model_.load();
                const bool want_loaded = tap_enabled_.load();
                if (want_loaded && wanted != failed_model_.load()
                        && (!loaded || loaded->index != wanted || loaded_threads != threads_.load())) return true;
                return !want_loaded && loaded != nullptr;
            });
            if (shutdown_) break;
            if (has_pending_) {
                rgb.swap(pending_rgb_);
                capture_ns = pending_capture_ns_;
                // Kept set until the run is over: the decoder offers the next
                // picture only once the model is free again.
                have_frame = true;
            }
        }

        const int wanted = wanted_model_.load();
        if (!tap_enabled_.load() && !have_frame) {
            // Nothing wants maps: give the memory and the threads back.
            if (loaded) {
                ready_.store(false);
                loaded.reset();
                NF_LOG("FrameDepth", "model unloaded");
            }
            continue;
        }

        if (!loaded || loaded->index != wanted || loaded_threads != threads_.load()) {
            ready_.store(false);
            loaded.reset();
            if (wanted != failed_model_.load()) {
                const ModelSpec &spec = model_spec(wanted);
                const int threads = threads_.load();
                const int64_t start = now_ns();
                std::unique_ptr<Loaded> next;
                std::string why;
                if (spec.graphics) {
#ifdef NIGHTFALL_FRAME_NCNN
                    auto model = std::make_unique<GraphicsModel>();
                    why = model->load(spec, model_dir_);
                    next = std::move(model);
#else
                    why = "this build has no engine for the graphics chip";
#endif
                } else {
                    auto model = std::make_unique<ProcessorModel>();
                    why = model->load(spec, model_dir_, threads);
                    next = std::move(model);
                }
                if (why.empty()) {
                    // The first runs set up caches (and, on the graphics chip,
                    // build its programs) and are much slower; do them on a
                    // grey picture before any real one waits.
                    const std::vector<uint8_t> grey((size_t)next->width * next->height * 3, 128);
                    for (int i = 0; i < WARMUP_RUNS && why.empty(); i++) {
                        std::string failed;
                        if (next->run(grey.data(), &failed) == nullptr) why = "the model failed on its first run: " + failed;
                    }
                }
                if (why.empty()) {
                    next->index = wanted;
                    next->load_ms = (float)(now_ns() - start) / 1e6f;
                    loaded = std::move(next);
                    loaded_threads = threads;
                    smoothing = make_smoothing();
                    width_.store(loaded->width);
                    height_.store(loaded->height);
                    set_status("");
                    ready_.store(true);
                    NF_LOG("FrameDepth", "model %s ready: %dx%d, %s, loaded and warmed up in %.0f ms",
                           spec.key, loaded->width, loaded->height, loaded->where.c_str(), loaded->load_ms);
                } else {
                    // Not tried again until the model or the switch changes.
                    failed_model_.store(wanted);
                    set_status("On-headset depth can't start: " + why);
                    NF_LOGE("FrameDepth", "model %s not loaded: %s", spec.key, why.c_str());
                }
            }
        }

        if (have_frame) {
            if (loaded && rgb.size() == (size_t)loaded->width * loaded->height * 3) {
                const size_t count = (size_t)loaded->width * loaded->height;
                std::string failed;
                const int64_t start = now_ns();
                const float *raw = loaded->run(rgb.data(), &failed);
                const int64_t ran = now_ns();
                if (raw != nullptr) {
                    std::vector<uint8_t> map = post_process(*smoothing, raw, (int)count, ran);
                    const int64_t published = now_ns();
                    {
                        std::lock_guard<std::mutex> lock(result_mutex_);
                        result_ = std::move(map);
                        has_result_ = true;
                    }
                    const float model_ms = (float)(ran - start) / 1e6f;
                    const float age_ms = (float)(published - capture_ns) / 1e6f;
                    last_model_ms_.store(model_ms);
                    last_age_ms_.store(age_ms);
                    if (rate_window_start == 0) rate_window_start = published;
                    rate_window_maps++;
                    if (published - rate_window_start >= 1000000000LL) {
                        maps_per_second_.store((float)rate_window_maps * 1e9f / (float)(published - rate_window_start));
                        rate_window_start = published;
                        rate_window_maps = 0;
                    }
                    std::lock_guard<std::mutex> lock(report_mutex_);
                    report_maps_++;
                    report_model_ms_sum_ += model_ms;
                    report_model_ms_max_ = std::max(report_model_ms_max_, model_ms);
                    report_age_ms_sum_ += age_ms;
                } else {
                    set_status("On-headset depth stopped: " + failed);
                }
            }
            std::lock_guard<std::mutex> lock(pending_mutex_);
            // A picture offered by the app itself during the run stays queued.
            if (pending_rgb_.empty()) has_pending_ = false;
        }
    }
}

// Raw model output (larger is nearer, any scale) to bytes, 255 nearest: the
// range between the 2nd and 98th percentile, itself eased over time so one
// bright corner doesn't make the whole scene jump, then each texel eased
// toward its new value.
std::vector<uint8_t> FrameDepthEngine::post_process(Smoothing &state, const float *raw, int count, int64_t now) {
    float lo = raw[0], hi = raw[0];
    for (int i = 1; i < count; i++) {
        lo = std::min(lo, raw[i]);
        hi = std::max(hi, raw[i]);
    }
    float robust_lo = lo, robust_hi = lo + 1.0f;
    if (hi > lo) {
        int hist[HIST_BINS] = { 0 };
        const float bin_scale = HIST_BINS / (hi - lo);
        for (int i = 0; i < count; i++) {
            const int b = (int)((raw[i] - lo) * bin_scale);
            hist[std::max(0, std::min(HIST_BINS - 1, b))]++;
        }
        const int lo_target = (int)(count * PERCENTILE_CLIP);
        const int hi_target = (int)(count * (1.0f - PERCENTILE_CLIP));
        int lo_bin = 0, hi_bin = HIST_BINS - 1;
        for (int b = 0, acc = 0; b < HIST_BINS; b++) {
            acc += hist[b];
            if (acc >= lo_target) { lo_bin = b; break; }
        }
        for (int b = 0, acc = 0; b < HIST_BINS; b++) {
            acc += hist[b];
            if (acc >= hi_target) { hi_bin = b; break; }
        }
        const float bin_width = (hi - lo) / HIST_BINS;
        robust_lo = lo + lo_bin * bin_width;
        robust_hi = std::max(lo + (hi_bin + 1) * bin_width, robust_lo + 1e-3f);
    }

    const float dt = state.last_ns == 0
            ? DEPTH_TAU_SECONDS
            : std::max(1.0f / 60.0f, std::min((float)(now - state.last_ns) / 1e9f, 1.0f));
    state.last_ns = now;
    if (!state.range_valid) {
        state.lo = robust_lo;
        state.hi = robust_hi;
        state.range_valid = true;
    } else {
        const float alpha = 1.0f - std::exp(-dt / RANGE_TAU_SECONDS);
        state.lo += alpha * (robust_lo - state.lo);
        state.hi += alpha * (robust_hi - state.hi);
    }
    const float scale = 1.0f / std::max(state.hi - state.lo, 1e-6f);

    const bool fresh = (int)state.depth.size() != count;
    if (fresh) state.depth.resize((size_t)count);
    const float alpha = fresh ? 1.0f : 1.0f - std::exp(-dt / DEPTH_TAU_SECONDS);
    std::vector<uint8_t> out((size_t)count);
    for (int i = 0; i < count; i++) {
        const float v = std::max(0.0f, std::min(1.0f, (raw[i] - state.lo) * scale));
        float &kept = state.depth[i];
        kept = fresh ? v : kept + alpha * (v - kept);
        out[i] = (uint8_t)(std::max(0.0f, std::min(1.0f, kept)) * 255.0f);
    }
    return out;
}

std::string FrameDepthEngine::take_report() {
    const int64_t now = now_ns();
    const int64_t cpu = process_cpu_ns();
    std::lock_guard<std::mutex> lock(report_mutex_);
    char text[400];
    const double seconds = report_start_ns_ == 0 ? 0.0 : (double)(now - report_start_ns_) / 1e9;
    if (seconds <= 0.0) {
        snprintf(text, sizeof text, "starting");
    } else {
        const ModelSpec &spec = model_spec(wanted_model_.load());
        const int maps = std::max(report_maps_, 1);
        const int offered = std::max(report_offered_, 1);
        snprintf(text, sizeof text,
                 "%s %s, %.1f maps/s (aim %.0f), model %.1f ms (worst %.1f), shrink %.2f ms (worst %.2f), age %.0f ms, %d threads, whole app %.2f cores, cpu clocks %s",
                 spec.key, ready_.load() ? "running" : "not ready", (double)report_maps_ / seconds,
                 1e9 / (double)period_ns_.load(), report_model_ms_sum_ / maps, (double)report_model_ms_max_,
                 report_shrink_ms_sum_ / offered, (double)report_shrink_ms_max_, report_age_ms_sum_ / maps,
                 threads_.load(), (double)(cpu - report_cpu_start_ns_) / 1e9 / seconds, cpu_clocks().c_str());
    }
    report_maps_ = 0;
    report_offered_ = 0;
    report_model_ms_sum_ = 0.0;
    report_model_ms_max_ = 0.0f;
    report_shrink_ms_sum_ = 0.0;
    report_shrink_ms_max_ = 0.0f;
    report_age_ms_sum_ = 0.0;
    report_start_ns_ = now;
    report_cpu_start_ns_ = cpu;
    return text;
}
