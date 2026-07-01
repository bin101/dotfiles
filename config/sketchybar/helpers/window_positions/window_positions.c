// window_positions: print all on-screen window ids and their origin (X Y)
// Output: one line per window: "<window-id> <x> <y>"
// Uses CGWindowListCopyWindowInfo — no Screen Recording permission required
// (only window titles are redacted without it; bounds + ids are always available).
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

int main(void) {
    CFArrayRef windows = CGWindowListCopyWindowInfo(
        kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (!windows) return 1;

    CFIndex n = CFArrayGetCount(windows);
    for (CFIndex i = 0; i < n; i++) {
        CFDictionaryRef win = (CFDictionaryRef)CFArrayGetValueAtIndex(windows, i);

        CFNumberRef numRef = (CFNumberRef)CFDictionaryGetValue(win, kCGWindowNumber);
        if (!numRef) continue;
        int64_t wid = 0;
        CFNumberGetValue(numRef, kCFNumberSInt64Type, &wid);

        CFDictionaryRef boundsDict = (CFDictionaryRef)CFDictionaryGetValue(win, kCGWindowBounds);
        if (!boundsDict) continue;

        CGRect rect = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation(boundsDict, &rect)) continue;

        printf("%lld %d %d\n", (long long)wid, (int)rect.origin.x, (int)rect.origin.y);
    }

    CFRelease(windows);
    return 0;
}
