// Non-blocking POSIX TCP + RFC 6455 WebSocket client (ws://host:port/path)
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int g_fd = -1;
static int g_ws_state = 0; // 0 = closed, 1 = connecting, 2 = open, 3 = error
static uint8_t g_rx_stream[65536];
static size_t g_rx_len = 0;

void grl_ws_close(void) {
    if (g_fd >= 0) {
        uint8_t close_frame[6] = {0x88, 0x80, 0x12, 0x34, 0x56, 0x78};
        send(g_fd, close_frame, 6, MSG_NOSIGNAL);
        close(g_fd);
        g_fd = -1;
    }
    g_rx_len = 0;
    g_ws_state = 0;
}

int32_t grl_ws_connect(const char* url) {
    grl_ws_close();
    if (!url) { g_ws_state = 3; return -1; }

    // Parse "ws://host[:port][/path]"
    const char* p = url;
    if (strncmp(p, "ws://", 5) == 0) p += 5;
    else if (strncmp(p, "wss://", 6) == 0) p += 6;

    char host[256] = {0};
    char port_str[16] = "80";
    char path[256] = "/";

    const char* slash = strchr(p, '/');
    size_t hostport_len = slash ? (size_t)(slash - p) : strlen(p);
    if (slash) snprintf(path, sizeof(path), "%s", slash);

    const char* colon = memchr(p, ':', hostport_len);
    if (colon) {
        size_t hlen = (size_t)(colon - p);
        if (hlen >= sizeof(host)) hlen = sizeof(host) - 1;
        memcpy(host, p, hlen);
        size_t plen = hostport_len - hlen - 1;
        if (plen >= sizeof(port_str)) plen = sizeof(port_str) - 1;
        memcpy(port_str, colon + 1, plen);
    } else {
        if (hostport_len >= sizeof(host)) hostport_len = sizeof(host) - 1;
        memcpy(host, p, hostport_len);
    }

    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        g_ws_state = 3;
        return -1;
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        g_ws_state = 3;
        return -1;
    }

    if (connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
        close(fd);
        freeaddrinfo(res);
        g_ws_state = 3;
        return -1;
    }
    freeaddrinfo(res);

    // Send RFC 6455 HTTP Upgrade handshake
    char req[1024];
    int req_len = snprintf(
        req, sizeof(req),
        "GET %s HTTP/1.1\r\n"
        "Host: %s:%s\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n",
        path, host, port_str
    );
    if (send(fd, req, (size_t)req_len, MSG_NOSIGNAL) != req_len) {
        close(fd);
        g_ws_state = 3;
        return -1;
    }

    // Read HTTP 101 response headers
    char hdr[2048] = {0};
    size_t htotal = 0;
    while (htotal < sizeof(hdr) - 1) {
        ssize_t r = recv(fd, hdr + htotal, 1, 0);
        if (r <= 0) { close(fd); g_ws_state = 3; return -1; }
        htotal += (size_t)r;
        if (htotal >= 4 && memcmp(hdr + htotal - 4, "\r\n\r\n", 4) == 0) break;
    }
    if (!strstr(hdr, "101")) {
        close(fd);
        g_ws_state = 3;
        return -1;
    }

    // Switch socket to non-blocking mode for gameplay
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    g_fd = fd;
    g_rx_len = 0;
    g_ws_state = 2;
    return 0;
}

int32_t grl_ws_state(void) {
    return (int32_t)g_ws_state;
}

int32_t grl_ws_send(const char* data, int32_t len) {
    if (g_fd < 0 || g_ws_state != 2 || len < 0) return -1;

    uint8_t header[14];
    size_t hlen = 0;
    header[0] = 0x81; // FIN + Text frame
    if (len <= 125) {
        header[1] = 0x80 | (uint8_t)len; // Masked
        hlen = 2;
    } else if (len <= 65535) {
        header[1] = 0x80 | 126;
        header[2] = (uint8_t)((len >> 8) & 0xFF);
        header[3] = (uint8_t)(len & 0xFF);
        hlen = 4;
    } else {
        return -1;
    }

    uint8_t mask[4] = {0x37, 0xFA, 0x21, 0x3D};
    memcpy(header + hlen, mask, 4);
    hlen += 4;

    uint8_t* frame = (uint8_t*)malloc(hlen + (size_t)len);
    if (!frame) return -1;
    memcpy(frame, header, hlen);
    for (int32_t i = 0; i < len; i++) {
        frame[hlen + i] = ((uint8_t)data[i]) ^ mask[i & 3];
    }

    ssize_t sent = send(g_fd, frame, hlen + (size_t)len, MSG_NOSIGNAL);
    free(frame);
    if (sent < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) return 0;
        grl_ws_close();
        return -1;
    }
    return len;
}

int32_t grl_ws_poll(char* out_buf, int32_t max_len) {
    if (g_fd < 0 || g_ws_state != 2 || !out_buf || max_len <= 1) return 0;

    // Drain any newly arrived bytes into g_rx_stream without blocking
    if (g_rx_len < sizeof(g_rx_stream)) {
        ssize_t n = recv(g_fd, g_rx_stream + g_rx_len, sizeof(g_rx_stream) - g_rx_len, 0);
        if (n > 0) {
            g_rx_len += (size_t)n;
        } else if (n == 0) {
            grl_ws_close();
            return -1;
        } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
            grl_ws_close();
            return -1;
        }
    }

    // Parse one complete RFC 6455 frame if buffered
    if (g_rx_len < 2) return 0;
    uint8_t opcode = g_rx_stream[0] & 0x0F;
    uint8_t masked = (g_rx_stream[1] >> 7) & 1;
    uint64_t plen = g_rx_stream[1] & 0x7F;
    size_t offset = 2;

    if (plen == 126) {
        if (g_rx_len < 4) return 0;
        plen = ((uint64_t)g_rx_stream[2] << 8) | g_rx_stream[3];
        offset = 4;
    } else if (plen == 127) {
        if (g_rx_len < 10) return 0;
        plen = 0;
        for (int i = 0; i < 8; i++) plen = (plen << 8) | g_rx_stream[2 + i];
        offset = 10;
    }
    if (masked) offset += 4;

    if (g_rx_len < offset + plen) return 0; // Wait for rest of frame

    size_t total_frame = offset + (size_t)plen;
    if (opcode == 0x8) { // Close frame
        grl_ws_close();
        return -1;
    }

    int32_t copy_len = (int32_t)plen;
    if (copy_len >= max_len) copy_len = max_len - 1;
    memcpy(out_buf, g_rx_stream + offset, (size_t)copy_len);
    out_buf[copy_len] = '\0';

    // Shift remaining buffered bytes forward
    if (g_rx_len > total_frame) {
        memmove(g_rx_stream, g_rx_stream + total_frame, g_rx_len - total_frame);
    }
    g_rx_len -= total_frame;

    return copy_len;
}
