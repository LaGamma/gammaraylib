// Native WebSocket client backed by libcurl (supports ws:// and wss://)
#include <curl/curl.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>

static CURL* g_ws = NULL;
static curl_socket_t g_sockfd = CURL_SOCKET_BAD;
static int g_ws_state = 0; // 0 = closed, 1 = connecting, 2 = open, 3 = error

void grl_ws_close(void) {
    if (g_ws) {
        size_t sent = 0;
        curl_ws_send(g_ws, "", 0, &sent, 0, CURLWS_CLOSE);
        curl_easy_cleanup(g_ws);
        g_ws = NULL;
    }
    g_sockfd = CURL_SOCKET_BAD;
    g_ws_state = 0;
}

int32_t grl_ws_connect(const char* url) {
    grl_ws_close();
    curl_global_init(CURL_GLOBAL_DEFAULT);
    g_ws = curl_easy_init();
    if (!g_ws) {
        g_ws_state = 3;
        return -1;
    }
    curl_easy_setopt(g_ws, CURLOPT_URL, url);
    curl_easy_setopt(g_ws, CURLOPT_CONNECT_ONLY, 2L);
    CURLcode res = curl_easy_perform(g_ws);
    if (res != CURLE_OK) {
        curl_easy_cleanup(g_ws);
        g_ws = NULL;
        g_ws_state = 3;
        return -1;
    }
    curl_easy_getinfo(g_ws, CURLINFO_ACTIVESOCKET, &g_sockfd);
    g_ws_state = 2;
    return 0;
}

int32_t grl_ws_state(void) {
    return (int32_t)g_ws_state;
}

int32_t grl_ws_send(const char* data, int32_t len) {
    if (!g_ws || g_ws_state != 2 || len < 0) return -1;
    size_t sent = 0;
    CURLcode res = curl_ws_send(g_ws, data, (size_t)len, &sent, 0, CURLWS_TEXT);
    if (res != CURLE_OK) {
        g_ws_state = 3;
        return -1;
    }
    return (int32_t)sent;
}

int32_t grl_ws_poll(char* out_buf, int32_t max_len) {
    if (!g_ws || g_ws_state != 2 || !out_buf || max_len <= 1) return 0;

    // Non-blocking readiness check: return 0 immediately if no bytes are queued on the socket
    if (g_sockfd == CURL_SOCKET_BAD) {
        curl_easy_getinfo(g_ws, CURLINFO_ACTIVESOCKET, &g_sockfd);
        if (g_sockfd == CURL_SOCKET_BAD) return 0;
    }
    struct pollfd pfd;
    pfd.fd = g_sockfd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    if (poll(&pfd, 1, 0) <= 0) {
        return 0;
    }

    size_t recv_len = 0;
    const struct curl_ws_frame* meta = NULL;
    CURLcode res = curl_ws_recv(g_ws, out_buf, (size_t)(max_len - 1), &recv_len, &meta);
    if (res == CURLE_AGAIN) {
        return 0;
    }
    if (res != CURLE_OK) {
        g_ws_state = (res == CURLE_GOT_NOTHING) ? 0 : 3;
        return -1;
    }
    if (meta && (meta->flags & CURLWS_CLOSE)) {
        grl_ws_close();
        return -1;
    }
    out_buf[recv_len] = '\0';
    return (int32_t)recv_len;
}
