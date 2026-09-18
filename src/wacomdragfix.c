/* Wacom pen window-drag fix for macOS Golden Gate (v4 — canonical interpose).
 * Interpose CGEventPost; for mouse button/drag events, rebuild via
 * CGEventCreateMouseEvent (which WindowServer's drag gesture accepts) and post
 * the rebuild. Non-button events pass through unchanged.
 *
 * v1-v3 crashed trying to obtain the "real" CGEventPost via dlsym: modern dyld
 * returns the INTERPOSED function from dlsym, so every variant recursed (stack
 * overflow → SIGSEGV). The canonical dyld interpose pattern instead calls the
 * symbol BY NAME inside the replacement — dyld exempts the interposing image's
 * own call from redirection, so this reaches the REAL CGEventPost. No dlsym. */
#include <ApplicationServices/ApplicationServices.h>
#include <stddef.h>

static int is_button_event(CGEventType t){
    return t==kCGEventLeftMouseDown  || t==kCGEventLeftMouseUp  || t==kCGEventLeftMouseDragged
        || t==kCGEventRightMouseDown || t==kCGEventRightMouseUp || t==kCGEventRightMouseDragged
        || t==kCGEventOtherMouseDown || t==kCGEventOtherMouseUp || t==kCGEventOtherMouseDragged;
}
static int is_down_or_up(CGEventType t){
    return t==kCGEventLeftMouseDown  || t==kCGEventLeftMouseUp
        || t==kCGEventRightMouseDown || t==kCGEventRightMouseUp
        || t==kCGEventOtherMouseDown || t==kCGEventOtherMouseUp;
}
static const CGEventField IFIELDS[] = {
    kCGMouseEventSubtype,
    kCGTabletEventPointX, kCGTabletEventPointY, kCGTabletEventPointZ,
    kCGTabletEventPointButtons, kCGTabletEventDeviceID,
    kCGTabletEventVendor1, kCGTabletEventVendor2, kCGTabletEventVendor3,
};
static const CGEventField DFIELDS[] = {
    kCGTabletEventPointPressure, kCGTabletEventTiltX, kCGTabletEventTiltY,
    kCGTabletEventRotation, kCGTabletEventTangentialPressure,
};

static void wdf_CGEventPost(CGEventTapLocation tap, CGEventRef event){
    CGEventType t = CGEventGetType(event);
    if (is_button_event(t)) {
        CGPoint loc = CGEventGetLocation(event);
        CGMouseButton btn = (CGMouseButton)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        CGEventRef m = CGEventCreateMouseEvent(NULL, t, loc, btn);
        if (m) {
            for (size_t i=0;i<sizeof(IFIELDS)/sizeof(IFIELDS[0]);i++)
                CGEventSetIntegerValueField(m, IFIELDS[i], CGEventGetIntegerValueField(event, IFIELDS[i]));
            for (size_t i=0;i<sizeof(DFIELDS)/sizeof(DFIELDS[0]);i++)
                CGEventSetDoubleValueField(m, DFIELDS[i], CGEventGetDoubleValueField(event, DFIELDS[i]));
            if (is_down_or_up(t))   /* preserve single/double click-count; NOT on drags */
                CGEventSetIntegerValueField(m, kCGMouseEventClickState,
                    CGEventGetIntegerValueField(event, kCGMouseEventClickState));
            CGEventSetFlags(m, CGEventGetFlags(event));   /* preserve modifier keys (cmd/shift/etc.) */
            CGEventPost(tap, m);       /* real CGEventPost (dyld exempts our own call) */
            CFRelease(m);
            return;
        }
    }
    CGEventPost(tap, event);           /* real CGEventPost */
}

__attribute__((used))
static struct { const void *replacement; const void *replacee; }
_interpose_cgeventpost __attribute__((section("__DATA,__interpose"))) =
    { (const void*)&wdf_CGEventPost, (const void*)&CGEventPost };
