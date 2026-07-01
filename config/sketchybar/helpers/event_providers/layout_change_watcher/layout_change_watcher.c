// layout_change_watcher: poll CGWindowList and fire space_layout_change whenever
// window positions settle after a change (debounce = 2 stable polls × 50ms = 100ms).
// No Screen Recording or Accessibility permissions required.
//
// Adaptive polling: idle at 250ms (≈0% CPU), switch to 50ms on any window move,
// revert to 250ms after ACTIVE_LINGER × 50ms of inactivity following a trigger.
#include "../sketchybar.h"
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WINDOWS    512
#define IDLE_US        250000  // 250 ms — normal poll interval (≈0% CPU)
#define ACTIVE_US       50000  // 50 ms  — fast poll while windows are moving
#define STABLE_POLLS        2  // fire after 2 consecutive stable ACTIVE_US polls (100 ms)
#define ACTIVE_LINGER      20  // 20 × 50 ms = 1 s of fast polling after trigger fires
#define MOVE_THRESH         4  // px — ignore sub-pixel compositor jitter

typedef struct { int64_t id; int x, y; } WinPos;

static WinPos prev[MAX_WINDOWS], cur[MAX_WINDOWS];
static int prev_n      = 0;
static int stable_cnt  = 0;
static int pending     = 0;

static int cmp_id(const void *a, const void *b) {
    int64_t da = ((const WinPos *)a)->id;
    int64_t db = ((const WinPos *)b)->id;
    return (da > db) - (da < db);
}

static int snapshot(WinPos *out) {
    CFArrayRef wins = CGWindowListCopyWindowInfo(
        kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!wins) return 0;
    int n = 0;
    CFIndex cnt = CFArrayGetCount(wins);
    for (CFIndex i = 0; i < cnt && n < MAX_WINDOWS; i++) {
        CFDictionaryRef w = (CFDictionaryRef)CFArrayGetValueAtIndex(wins, i);
        CFNumberRef nr    = (CFNumberRef)CFDictionaryGetValue(w, kCGWindowNumber);
        CFDictionaryRef bd = (CFDictionaryRef)CFDictionaryGetValue(w, kCGWindowBounds);
        if (!nr || !bd) continue;
        int64_t wid = 0;
        CFNumberGetValue(nr, kCFNumberSInt64Type, &wid);
        CGRect r = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation(bd, &r)) continue;
        out[n++] = (WinPos){ wid, (int)r.origin.x, (int)r.origin.y };
    }
    CFRelease(wins);
    qsort(out, n, sizeof(WinPos), cmp_id);
    return n;
}

static int changed(int n) {
    if (n != prev_n) return 1;
    for (int i = 0; i < n; i++) {
        if (cur[i].id != prev[i].id) return 1;
        if (abs(cur[i].x - prev[i].x) > MOVE_THRESH) return 1;
        if (abs(cur[i].y - prev[i].y) > MOVE_THRESH) return 1;
    }
    return 0;
}

int main(void) {
    prev_n = snapshot(prev);
    int poll_us       = IDLE_US;   // start slow
    int active_linger = 0;         // countdown to revert to IDLE_US after a trigger

    for (;;) {
        usleep(poll_us);
        int n = snapshot(cur);
        if (changed(n)) {
            // A window moved: switch to fast polling and arm debounce.
            memcpy(prev, cur, n * sizeof(WinPos));
            prev_n        = n;
            pending       = 1;
            stable_cnt    = 0;
            poll_us       = ACTIVE_US;
            active_linger = ACTIVE_LINGER;  // reset linger on every new change
        } else if (pending) {
            // Stable so far — wait for STABLE_POLLS consecutive quiet polls.
            if (++stable_cnt >= STABLE_POLLS) {
                sketchybar("--trigger space_layout_change");
                pending    = 0;
                stable_cnt = 0;
                // Keep ACTIVE_US for linger; active_linger already loaded.
            }
        } else {
            // Fully stable — count down linger before reverting to idle rate.
            if (active_linger > 0) {
                if (--active_linger == 0) {
                    poll_us = IDLE_US;
                }
            }
        }
    }
}
