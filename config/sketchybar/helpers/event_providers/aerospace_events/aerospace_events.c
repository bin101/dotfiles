#include "../sketchybar.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define PROTO_VERSION 1
#define BUF_SIZE      (64 * 1024)

static const char* SUBSCRIBE_REQ =
    "{\"args\":[\"subscribe\",\"--no-send-initial\",\"--all\"],\"stdin\":\"\","
    "\"windowId\":null,\"workspace\":null}";

static int recv_exact(int fd, char* buf, uint32_t n) {
    uint32_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, buf + got, n - got);
        if (r <= 0) return -1;
        got += (uint32_t)r;
    }
    return 0;
}

static int json_str(const char* json, const char* key, char* out, size_t len) {
    char needle[128];
    snprintf(needle, sizeof(needle), "\"%s\"", key);
    const char* p = strstr(json, needle);
    if (!p) return 0;
    p += strlen(needle);
    while (*p == ' ' || *p == ':') p++;
    if (*p != '"') return 0;
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i < len - 1) out[i++] = *p++;
    out[i] = '\0';
    return 1;
}

static int connect_socket(const char* path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    return fd;
}

int main(void) {
    char sock_path[256];
    const char* user = getenv("USER");
    if (!user) user = "unknown";
    snprintf(sock_path, sizeof(sock_path), "/tmp/bobko.aerospace-%s.sock", user);

    int fd = -1;
    for (int i = 0; i < 50 && fd < 0; i++) {
        fd = connect_socket(sock_path);
        if (fd < 0) usleep(200000);
    }
    if (fd < 0) { fprintf(stderr, "aerospace_events: could not connect\n"); return 1; }

    // Handshake
    uint32_t ver = PROTO_VERSION;
    if (write(fd, &ver, 4) != 4) { close(fd); return 1; }
    uint32_t srv_ver = 0;
    if (recv_exact(fd, (char*)&srv_ver, 4) < 0 || srv_ver != PROTO_VERSION) {
        fprintf(stderr, "aerospace_events: protocol version mismatch\n");
        close(fd); return 1;
    }

    // Subscribe
    uint32_t req_len = (uint32_t)strlen(SUBSCRIBE_REQ);
    if (write(fd, &req_len, 4) != 4) { close(fd); return 1; }
    if (write(fd, SUBSCRIBE_REQ, req_len) != (ssize_t)req_len) { close(fd); return 1; }

    char* buf = malloc(BUF_SIZE);
    if (!buf) { close(fd); return 1; }

    // Track current workspace to detect changes via focus-changed
    char current_workspace[64] = {0};
    char msg[512];

    for (;;) {
        uint32_t frame_len = 0;
        if (recv_exact(fd, (char*)&frame_len, 4) < 0) break;
        if (frame_len == 0 || frame_len >= BUF_SIZE) break;
        if (recv_exact(fd, buf, frame_len) < 0) break;
        buf[frame_len] = '\0';

        char event[64] = {0};
        if (!json_str(buf, "_event", event, sizeof(event))) continue;

        if (strcmp(event, "focused-workspace-changed") == 0) {
            char ws[64] = {0};
            json_str(buf, "workspace", ws, sizeof(ws));
            strncpy(current_workspace, ws, sizeof(current_workspace) - 1);
            snprintf(msg, sizeof(msg),
                     "--trigger aerospace_workspace_change FOCUSED_WORKSPACE='%s'", ws);
            sketchybar(msg);

        } else if (strcmp(event, "focus-changed") == 0) {
            // Catch workspace transitions that focused-workspace-changed may miss,
            // and initialize current_workspace from the initial state event.
            char ws[64] = {0};
            json_str(buf, "workspace", ws, sizeof(ws));
            if (strlen(ws) > 0 && strcmp(ws, current_workspace) != 0) {
                strncpy(current_workspace, ws, sizeof(current_workspace) - 1);
                snprintf(msg, sizeof(msg),
                         "--trigger aerospace_workspace_change FOCUSED_WORKSPACE='%s'", ws);
                sketchybar(msg);
            }
            // Always signal a focus change so the currently focused window can be
            // re-highlighted, including focus moves between windows of the same app
            // (which front_app_switched does not report).
            sketchybar("--trigger aerospace_focus_change");

        } else if (strcmp(event, "mode-changed") == 0) {
            char mode[64] = {0};
            json_str(buf, "mode", mode, sizeof(mode));
            snprintf(msg, sizeof(msg),
                     "--trigger aerospace_mode_change AEROSPACE_MODE='%s'", mode);
            sketchybar(msg);

        } else if (strcmp(event, "window-detected") == 0) {
            sketchybar("--trigger space_windows_change");
        }
    }

    free(buf);
    close(fd);
    return 0;
}
