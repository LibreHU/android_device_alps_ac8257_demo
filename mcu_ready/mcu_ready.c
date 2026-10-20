/*
 * Copyright (C) 2026 LibreHU
 * SPDX-License-Identifier: Apache-2.0
 *
 * mcu_ready : envoie PC_READY au MCU Jancar des le demarrage.
 *
 * Le MCU coupe le SoC une dizaine de secondes apres le demarrage s'il ne recoit pas PC_READY. Sur la ROM stock
 * c'est com.jancar.services qui l'envoie, sur TWRP touchfix, avec LibreHU-service le service (et au reveil de
 * veille). Sans les applis Jancar, LineageOS a besoin de cet envoi avant le demarrage des applis.
 *
 * Protocole JAC_V1 sur /dev/ttyS1 (115200 8N1), comme touchfix de la branche twrp :
 *   trame EE FA <len = donnees + 1> <cmd> <donnees> <somme de tous les octets precedents>
 *   PC_READY = cmd 0x1F, donnee 0x01
 * Envoi toutes les 4 s jusqu'a la premiere trame valide recue du MCU (au plus 2 minutes), puis fin.
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define LOG_TAG "mcu_ready"
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define MCU_TTY "/dev/ttyS1"
#define RETRY_MS 4000
#define GIVE_UP_MS 120000

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void mcu_send(int fd, unsigned char cmd, const unsigned char *d, int n) {
    unsigned char f[32];
    int k = 0, sum = 0;
    f[k++] = 0xEE;
    f[k++] = 0xFA;
    f[k++] = (unsigned char)(n + 1);
    f[k++] = cmd;
    for (int i = 0; i < n; i++) f[k++] = d[i];
    for (int i = 0; i < k; i++) sum += f[i];
    f[k++] = (unsigned char)sum;
    if (write(fd, f, k) != k) LOGE("write: %s", strerror(errno));
}

/* Cherche une trame valide (en-tete EE FA et somme juste) dans buf ; renvoie 1 si trouvee. */
static int has_valid_frame(const unsigned char *buf, int len) {
    for (int i = 0; i + 4 < len; i++) {
        if (buf[i] != 0xEE || buf[i + 1] != 0xFA) continue;
        int tot = 3 + buf[i + 2] + 1; /* en-tete + len + (cmd + donnees) + somme */
        if (i + tot > len) return 0;
        int sum = 0;
        for (int j = 0; j < tot - 1; j++) sum += buf[i + j];
        if ((unsigned char)sum == buf[i + tot - 1]) return 1;
    }
    return 0;
}

int main(void) {
    int fd = -1;
    for (int t = 0; t < 100 && fd < 0; t++) {
        fd = open(MCU_TTY, O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (fd < 0) usleep(100 * 1000);
    }
    if (fd < 0) {
        LOGE("%s introuvable: %s", MCU_TTY, strerror(errno));
        return 1;
    }

    struct termios tio;
    if (tcgetattr(fd, &tio) == 0) {
        cfmakeraw(&tio);
        cfsetispeed(&tio, B115200);
        cfsetospeed(&tio, B115200);
        tio.c_cflag &= ~(PARENB | CSTOPB | CRTSCTS);
        tio.c_cflag |= CS8 | CREAD | CLOCAL;
        tcsetattr(fd, TCSANOW, &tio);
    }

    const unsigned char ready[1] = {0x01};
    unsigned char buf[256];
    int len = 0;
    long long start = now_ms(), last = -RETRY_MS;

    while (now_ms() - start < GIVE_UP_MS) {
        if (now_ms() - last >= RETRY_MS) {
            mcu_send(fd, 0x1F, ready, 1);
            last = now_ms();
            LOGI("PC_READY envoye");
        }
        struct pollfd p = {.fd = fd, .events = POLLIN};
        if (poll(&p, 1, 200) > 0) {
            int n = read(fd, buf + len, sizeof(buf) - len);
            if (n > 0) {
                len += n;
                if (has_valid_frame(buf, len)) {
                    LOGI("le MCU repond : fin");
                    close(fd);
                    return 0;
                }
                if (len > (int)sizeof(buf) - 32) len = 0;
            }
        }
    }
    LOGE("pas de reponse du MCU apres %d s", GIVE_UP_MS / 1000);
    close(fd);
    return 1;
}
