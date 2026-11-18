// Checks for the Steam Frame's on-headset depth engine (frame_depth_engine.h)
// that need no headset: the picture shrink, the smoothing, and each model
// loaded and run on a made-up scene. Not part of the library; built only with
// -DNIGHTFALL_BUILD_FRAME_DEPTH_TEST=ON.
//
//   frame_depth_test <folder with the .tflite models> [seconds to run each model]

#include "frame_depth_engine.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <vector>

namespace {

int failures = 0;

void check(bool ok, const char *what) {
    if (!ok) {
        failures++;
        printf("FAILED: %s\n", what);
    }
}

// An NV12 picture (BT.709 video range) with a pitch wider than the picture,
// as a decoder's buffers have.
struct Nv12 {
    int width, height, pitch;
    std::vector<uint8_t> y, uv;
    Nv12(int w, int h) : width(w), height(h), pitch(w + 64), y((size_t)(w + 64) * h, 99), uv((size_t)(w + 64) * (h / 2), 99) {}
    void set(int px, int py, int r, int g, int b) {
        const double yy = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        const double cb = (b - yy) / 1.8556, cr = (r - yy) / 1.5748;
        y[(size_t)py * pitch + px] = (uint8_t)std::lround(16.0 + 219.0 * yy / 255.0);
        uint8_t *c = &uv[(size_t)(py / 2) * pitch + (px & ~1)];
        c[0] = (uint8_t)std::lround(128.0 + 224.0 * cb / 255.0);
        c[1] = (uint8_t)std::lround(128.0 + 224.0 * cr / 255.0);
    }
    void fill(int x0, int y0, int x1, int y1, int r, int g, int b) {
        for (int py = y0; py < y1; py++)
            for (int px = x0; px < x1; px++) set(px, py, r, g, b);
    }
};

bool near(int a, int b, int tolerance) { return std::abs(a - b) <= tolerance; }

void test_shrink() {
    // Four coloured quarters: each must come out in its place and its colour.
    Nv12 pic(1920, 1080);
    pic.fill(0, 0, 960, 540, 200, 30, 30);         // red, top left
    pic.fill(960, 0, 1920, 540, 30, 200, 30);      // green, top right
    pic.fill(0, 540, 960, 1080, 30, 30, 200);      // blue, bottom left
    pic.fill(960, 540, 1920, 1080, 220, 220, 220); // light grey, bottom right
    const int w = 512, h = 288;
    std::vector<uint8_t> rgb((size_t)w * h * 3);
    FrameDepthEngine::shrink_nv12_to_rgb(pic.y.data(), pic.pitch, pic.uv.data(), pic.pitch, 0, 0, 1920, 1080, w, h, rgb.data());
    auto at = [&](int x, int y) { return &rgb[((size_t)y * w + x) * 3]; };
    const uint8_t *tl = at(100, 60), *tr = at(400, 60), *bl = at(100, 220), *br = at(400, 220);
    check(near(tl[0], 200, 6) && near(tl[1], 30, 6) && near(tl[2], 30, 6), "shrink: top left is red");
    check(near(tr[0], 30, 6) && near(tr[1], 200, 6) && near(tr[2], 30, 6), "shrink: top right is green");
    check(near(bl[0], 30, 6) && near(bl[1], 30, 6) && near(bl[2], 200, 6), "shrink: bottom left is blue (rows top first)");
    check(near(br[0], 220, 6) && near(br[1], 220, 6) && near(br[2], 220, 6), "shrink: bottom right is light grey");
    // Black and white stay black and white (video range stretched to full).
    Nv12 bw(640, 360);
    bw.fill(0, 0, 320, 360, 0, 0, 0);
    bw.fill(320, 0, 640, 360, 255, 255, 255);
    std::vector<uint8_t> small((size_t)256 * 256 * 3);
    FrameDepthEngine::shrink_nv12_to_rgb(bw.y.data(), bw.pitch, bw.uv.data(), bw.pitch, 0, 0, 640, 360, 256, 256, small.data());
    check(small[(128 * 256 + 20) * 3] <= 2 && small[(128 * 256 + 230) * 3] >= 253, "shrink: black is 0 and white is 255");
    // A region: the right half of a two-screen frame is all green here.
    Nv12 two(3840, 1080);
    two.fill(0, 0, 1920, 1080, 200, 30, 30);
    two.fill(1920, 0, 3840, 1080, 30, 200, 30);
    FrameDepthEngine::shrink_nv12_to_rgb(two.y.data(), two.pitch, two.uv.data(), two.pitch, 1920, 0, 1920, 1080, w, h, rgb.data());
    check(near(at(2, 140)[1], 200, 6) && near(at(509, 140)[1], 200, 6) && near(at(2, 140)[0], 30, 6), "shrink: a region takes only its own screen");
    // Thin lines survive: a one-pixel white line every 4 pixels is 25% grey,
    // not black or white, once several samples are averaged.
    Nv12 lines(1920, 1080);
    lines.fill(0, 0, 1920, 1080, 0, 0, 0);
    for (int x = 0; x < 1920; x += 4) lines.fill(x, 0, x + 1, 1080, 255, 255, 255);
    FrameDepthEngine::shrink_nv12_to_rgb(lines.y.data(), lines.pitch, lines.uv.data(), lines.pitch, 0, 0, 1920, 1080, w, h, rgb.data());
    int low = 255, high = 0;
    for (int x = 8; x < w - 8; x++) {
        low = std::min<int>(low, at(x, 100)[1]);
        high = std::max<int>(high, at(x, 100)[1]);
    }
    check(high < 200 && high - low <= 120, "shrink: fine lines are averaged, not picked or dropped whole");
    // A picture smaller than the model is stretched, not read out of bounds.
    Nv12 tiny(320, 180);
    tiny.fill(0, 0, 320, 180, 30, 200, 30);
    FrameDepthEngine::shrink_nv12_to_rgb(tiny.y.data(), tiny.pitch, tiny.uv.data(), tiny.pitch, 0, 0, 320, 180, w, h, rgb.data());
    check(near(at(511, 287)[1], 200, 6) && near(at(0, 0)[1], 200, 6), "shrink: a small picture is stretched");
}

void test_post_process() {
    const int count = 1000;
    std::vector<float> raw(count);
    for (int i = 0; i < count; i++) raw[i] = 5.0f + 0.01f * i;   // larger is nearer, arbitrary scale
    auto state = FrameDepthEngine::make_smoothing();
    std::vector<uint8_t> first = FrameDepthEngine::post_process(*state, raw.data(), count, 1000000000LL);
    check(first.size() == (size_t)count, "post-process: one byte per texel");
    check(first[0] == 0 && first[count - 1] == 255, "post-process: farthest 0, nearest 255");
    check(first[count / 2] > 100 && first[count / 2] < 155, "post-process: the middle stays in the middle");
    // The same scene with one wild value: the range holds (2% is clipped).
    raw[10] = 1000.0f;
    auto fresh = FrameDepthEngine::make_smoothing();
    std::vector<uint8_t> clipped = FrameDepthEngine::post_process(*fresh, raw.data(), count, 1000000000LL);
    // (Not exactly unmoved: the range is read off a 512-step histogram that
    // the wild value stretches, as in Nightfall's other engines.)
    check(std::abs((int)clipped[count / 2] - (int)first[count / 2]) < 25, "post-process: one wild texel doesn't squash the rest");
    // A sudden change is eased in, not jumped to.
    std::vector<float> flipped(count);
    for (int i = 0; i < count; i++) flipped[i] = 5.0f + 0.01f * (count - 1 - i);
    std::vector<uint8_t> eased = FrameDepthEngine::post_process(*state, flipped.data(), count, 1050000000LL);
    check(eased[count - 1] < 255 && eased[count - 1] > 120, "post-process: a change is eased in over time");
    std::vector<uint8_t> later = eased;
    for (int i = 1; i <= 40; i++) later = FrameDepthEngine::post_process(*state, flipped.data(), count, 1050000000LL + i * 50000000LL);
    check(later[count - 1] < 25 && later[0] > 230, "post-process: and gets there");
}

// A scene with an obvious near and far: a chequered floor running to a
// horizon under a plain sky. Whatever else a depth model thinks, the bottom of
// the floor is nearer than the sky.
Nv12 floor_scene(int width, int height) {
    Nv12 pic(width, height);
    const int horizon = height * 45 / 100;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            if (y < horizon) {
                pic.set(x, y, 120, 170, 235 - y * 40 / horizon);
                continue;
            }
            // Perspective: rows near the horizon are far away.
            const double depth = (double)(height - horizon) / (y - horizon + 1);
            const double world_x = (x - width / 2.0) * depth / width * 6.0;
            const bool dark = (((int)std::floor(world_x) + (int)std::floor(depth * 3.0)) & 1) != 0;
            const int shade = dark ? 60 : 200;
            pic.set(x, y, shade, shade - 10, shade - 30);
        }
    }
    return pic;
}

void test_model(const std::string &dir, int index, double seconds) {
    const FrameDepthEngine::ModelSpec &spec = FrameDepthEngine::model_spec(index);
    FrameDepthEngine engine;
    engine.initialize(dir);
    engine.configure(index, 0);
    engine.set_rate(120);
    check(engine.get_model_width() == spec.width && engine.get_model_height() == spec.height, "model: its size is known before it loads");
    check(!engine.frame_wanted(), "model: no pictures wanted while switched off");
    engine.set_tap_enabled(true);
    for (int i = 0; i < 400 && !engine.frame_wanted() && engine.get_backend_status().empty(); i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    if (!engine.get_backend_status().empty()) {
        failures++;
        printf("FAILED: %s did not load: %s\n", spec.key, engine.get_backend_status().c_str());
        return;
    }
    check(engine.frame_wanted(), "model: ready and asking for a picture");
    // Switching model: the size the app is told changes at once (it sizes its
    // texture by it), and no map of the old size is handed out afterwards.
    {
        // The next model of another size (two of the three share one).
        int other = index;
        for (int step = 1; step < FrameDepthEngine::MODEL_COUNT; step++) {
            const int candidate = (index + step) % FrameDepthEngine::MODEL_COUNT;
            const FrameDepthEngine::ModelSpec &c = FrameDepthEngine::model_spec(candidate);
            if (engine.model_present(candidate) && (c.width != spec.width || c.height != spec.height)) {
                other = candidate;
                break;
            }
        }
        const FrameDepthEngine::ModelSpec &other_spec = FrameDepthEngine::model_spec(other);
        Nv12 warm = floor_scene(1280, 720);
        for (int i = 0; i < 200 && engine.get_last_inference_ms() <= 0.0f; i++) {
            FrameDepthEngine::tap_nv12(warm.y.data(), warm.pitch, warm.uv.data(), warm.pitch, warm.width, warm.height);
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(150));   // a map of this model is waiting
        engine.configure(other, 0);
        check(engine.get_model_width() == other_spec.width && engine.get_model_height() == other_spec.height, "switch: the new model's size is reported at once");
        bool wrong = false, right = false;
        for (int i = 0; i < 400 && !right; i++) {
            FrameDepthEngine::tap_nv12(warm.y.data(), warm.pitch, warm.uv.data(), warm.pitch, warm.width, warm.height);
            std::vector<uint8_t> got = engine.get_latest_depth();
            if (!got.empty()) {
                if (got.size() == (size_t)other_spec.width * other_spec.height) right = true;
                else wrong = true;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        check(!wrong, "switch: no map of the old model's size afterwards");
        check(right, "switch: maps of the new model's size arrive");
        engine.configure(index, 0);
        for (int i = 0; i < 400 && !(engine.frame_wanted() && engine.get_model_width() == spec.width); i++) {
            std::this_thread::sleep_for(std::chrono::milliseconds(25));
        }
        while (!engine.get_latest_depth().empty()) {}
    }

    Nv12 scene = floor_scene(1920, 1080);
    engine.take_report();
    std::vector<uint8_t> map;
    int maps = 0;
    const auto end = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
    while (std::chrono::steady_clock::now() < end) {
        // The decoder's side: offer a picture whenever one is wanted.
        FrameDepthEngine::tap_nv12(scene.y.data(), scene.pitch, scene.uv.data(), scene.pitch, scene.width, scene.height);
        std::vector<uint8_t> got = engine.get_latest_depth();
        if (!got.empty()) {
            map.swap(got);
            maps++;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    printf("%s: %s\n", spec.key, engine.take_report().c_str());
    check(maps >= 2, "model: maps arrive");
    check(map.size() == (size_t)spec.width * spec.height, "model: a map is the model's size");
    if (map.size() != (size_t)spec.width * spec.height) return;
    auto mean = [&](int y0, int y1) {
        double sum = 0.0;
        for (int y = y0; y < y1; y++)
            for (int x = 0; x < spec.width; x++) sum += map[(size_t)y * spec.width + x];
        return sum / ((double)(y1 - y0) * spec.width);
    };
    const double sky = mean(0, spec.height / 4);
    const double far_floor = mean(spec.height * 50 / 100, spec.height * 60 / 100);
    const double near_floor = mean(spec.height * 85 / 100, spec.height);
    printf("%s: sky %.0f, far floor %.0f, near floor %.0f (255 = nearest)\n", spec.key, sky, far_floor, near_floor);
    check(near_floor > sky + 60.0, "model: the near floor is nearer than the sky");
    check(near_floor > far_floor + 20.0, "model: the floor comes nearer toward the bottom (rows top first)");
    engine.set_tap_enabled(false);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    check(!engine.frame_wanted(), "model: switched off, no pictures wanted");
}

// The decoder's thread keeps offering pictures while the app switches the
// model, the thread count and the whole thing on and off, and throws engines
// away: nothing may crash, hang or hand out a map of the wrong size.
void test_churn(const std::string &dir, double seconds) {
    Nv12 scene = floor_scene(1280, 720);
    std::atomic<bool> stop{false};
    std::thread decoder([&] {
        while (!stop.load()) {
            FrameDepthEngine::tap_nv12(scene.y.data(), scene.pitch, scene.uv.data(), scene.pitch, scene.width, scene.height);
            std::this_thread::sleep_for(std::chrono::microseconds(500));
        }
    });
    const auto end = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
    int rounds = 0, maps = 0, wrong = 0;
    while (std::chrono::steady_clock::now() < end) {
        FrameDepthEngine engine;
        engine.initialize(dir);
        engine.set_rate(120);
        engine.set_tap_enabled(true);
        for (int step = 0; step < 6; step++) {
            int model = (rounds + step) % FrameDepthEngine::MODEL_COUNT;
            if (!engine.model_present(model)) model = 0;
            engine.configure(model, 0);
            engine.set_threads(1 + (rounds + step) % 3);
            engine.set_region(0.25f * (step % 2), 0.0f, 0.5f, 1.0f);
            if (step == 3) engine.set_tap_enabled(false);
            if (step == 4) engine.set_tap_enabled(true);
            std::this_thread::sleep_for(std::chrono::milliseconds(40 + 35 * step));
            std::vector<uint8_t> map = engine.get_latest_depth();
            if (!map.empty()) {
                maps++;
                bool known = false;
                for (int i = 0; i < FrameDepthEngine::MODEL_COUNT; i++) {
                    const FrameDepthEngine::ModelSpec &spec = FrameDepthEngine::model_spec(i);
                    known = known || map.size() == (size_t)spec.width * spec.height;
                }
                if (!known) wrong++;
            }
        }
        rounds++;
        // The engine goes away here with the decoder still offering.
    }
    stop.store(true);
    decoder.join();
    printf("churn: %d engines made and dropped, %d maps, %d of a wrong size\n", rounds, maps, wrong);
    check(rounds >= 2 && maps >= 1, "churn: engines came and went and maps still arrived");
    check(wrong == 0, "churn: no map of a size no model has");
}

} // namespace

int main(int argc, char **argv) {
    test_shrink();
    test_post_process();
    if (argc >= 2) {
        const double seconds = argc >= 3 ? atof(argv[2]) : 3.0;
        FrameDepthEngine probe;
        probe.initialize(argv[1]);
        for (int i = 0; i < FrameDepthEngine::MODEL_COUNT; i++) {
            if (probe.model_present(i)) {
                test_model(argv[1], i, seconds);
            } else {
                printf("(%s: not in this build or its file is not here; skipped)\n", FrameDepthEngine::model_spec(i).key);
            }
        }
        test_churn(argv[1], seconds * 3.0);
    } else {
        printf("(no model folder given: the models were not run)\n");
    }
    printf(failures == 0 ? "All frame depth tests passed\n" : "%d frame depth checks FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
