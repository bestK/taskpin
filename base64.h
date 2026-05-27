#ifndef TASKPIN_BASE64_H
#define TASKPIN_BASE64_H

/* Encode binary data to base64 string. Returns malloc'd string, caller frees. */
char *base64_encode(const char *data, int len);

/* Decode base64 string to binary. Returns malloc'd buffer, caller frees.
   out_len receives decoded length. */
char *base64_decode(const char *b64, int *out_len);

#endif