#include "base64.h"
#include <stdlib.h>
#include <string.h>

static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

char *base64_encode(const char *data, int len) {
    int out_len = 4 * ((len + 2) / 3);
    char *out = (char *)malloc(out_len + 1);
    if (!out) return NULL;

    int i, j;
    for (i = 0, j = 0; i < len - 2; i += 3) {
        unsigned char a = data[i], b = data[i+1], c = data[i+2];
        out[j++] = b64_table[a >> 2];
        out[j++] = b64_table[((a & 3) << 4) | (b >> 4)];
        out[j++] = b64_table[((b & 0xF) << 2) | (c >> 6)];
        out[j++] = b64_table[c & 0x3F];
    }
    if (i < len) {
        unsigned char a = data[i];
        unsigned char b = (i + 1 < len) ? data[i+1] : 0;
        out[j++] = b64_table[a >> 2];
        out[j++] = b64_table[((a & 3) << 4) | (b >> 4)];
        out[j++] = (i + 1 < len) ? b64_table[((b & 0xF) << 2)] : '=';
        out[j++] = '=';
    }
    out[j] = '\0';
    return out;
}

static int b64_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

char *base64_decode(const char *b64, int *out_len) {
    int len = (int)strlen(b64);
    int pad = 0;
    if (len > 0 && b64[len-1] == '=') pad++;
    if (len > 1 && b64[len-2] == '=') pad++;

    int decoded_len = (len / 4) * 3 - pad;
    char *out = (char *)malloc(decoded_len + 1);
    if (!out) { *out_len = 0; return NULL; }

    int i, j = 0;
    for (i = 0; i < len; i += 4) {
        int a = b64_val(b64[i]);
        int b = (i+1 < len) ? b64_val(b64[i+1]) : 0;
        int c = (i+2 < len) ? b64_val(b64[i+2]) : 0;
        int d = (i+3 < len) ? b64_val(b64[i+3]) : 0;
        if (a < 0) a = 0; if (b < 0) b = 0;
        if (c < 0) c = 0; if (d < 0) d = 0;

        out[j++] = (char)((a << 2) | (b >> 4));
        if (j < decoded_len) out[j++] = (char)(((b & 0xF) << 4) | (c >> 2));
        if (j < decoded_len) out[j++] = (char)(((c & 3) << 6) | d);
    }
    out[j] = '\0';
    *out_len = decoded_len;
    return out;
}