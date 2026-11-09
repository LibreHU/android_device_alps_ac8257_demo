/*
 * Copyright (C) 2026 LibreHU
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * mcu_ready : envoie PC_READY au MCU Jancar des le demarrage.
 *
 * Le MCU attend PC_READY apres avoir alimente le SoC (MCU-tools-app, docs/mcu_firmware.md, section 5) : 15 min au
 * plus au demarrage a froid, 10 s seulement a la sortie de veille ; sans lui il coupe le SoC. Sur la ROM stock c'est
 * com.jancar.services qui l'envoie, sur TWRP touchfix, avec LibreHU-service le service (et au reveil de veille).
 * Sans les applis Jancar, LineageOS a besoin de cet envoi avant le demarrage des applis.
 *
 * Protocole JAC_V1 sur /dev/ttyS1 (115200 8N1), comme touchfix de la branche twrp :
 *   trame EE FA <len = donnees + 1> <cmd> <donnees> <somme de tous les octets precedents>
 *   PC_READY = cmd 0x1F, donnee 0x01
 * Le MCU acquitte toute trame valide par C0 <cmd> <d0> <d1> et repond a PC_READY par ACC (00), puis sa version
 * (0A, +200 ms) et la date / l'heure (09, +400 ms). Fin quand l'une de ces reponses arrive : acquittement C0 1F ou
 * version 0A. Une autre trame (octets du boitier CAN 10, touches 20...) ne prouve pas que PC_READY a ete recu : le
 * MCU les relaie sans lui. Envoi toutes les secondes les 5 premieres fois (comme ivi-services : 500 ms, 5 essais),
 * puis toutes les 4 s, au plus 2 minutes. Journal dans logcat (tag mcu_ready) et dans le journal du noyau (dmesg,
 * console-ramoops) : logd n'est pas encore lance a « on init ».
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define LOG_TAG "mcu_ready"
#include <android/log.h>

#define MCU_TTY "/dev/ttyS1"
#define FAST_TRIES 5
#define FAST_MS 1000
#define RETRY_MS 4000
#define GIVE_UP_MS 120000

#define CMD_VERSION 0x0A
#define CMD_PC_READY 0x1F
#define CMD_ACK 0xC0

static int kmsg_fd = -1;

/* Journal : logcat et /dev/kmsg (niveau 6 = info, 3 = erreur). */
static void say(int err, const char *fmt, ...) {
    char msg[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);
    __android_log_print(err ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, LOG_TAG, "%s", msg);
    if (kmsg_fd >= 0) {
        char line[192];
        int n = snprintf(line, sizeof(line), "<%d>mcu_ready: %s\n", err ? 3 : 6, msg);
        if (n > 0 && write(kmsg_fd, line, n < (int)sizeof(line) ? n : (int)sizeof(line) - 1) < 0) {
            /* rien de plus a faire */
        }
    }
}

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
    if (write(fd, f, k) != k) say(1, "write: %s", strerror(errno));
}

/*
 * Parcourt les trames valides (en-tete EE FA et somme juste) de buf. Renvoie 1 si l'une repond a PC_READY
 * (acquittement C0 1F ou version 0A), 0 sinon ; *used = octets entierement lus (a retirer du tampon), *frames =
 * nombre de trames valides vues.
 */
static int scan_frames(const unsigned char *buf, int len, int *used, int *frames) {
    int i = 0;
    *used = 0;
    while (i + 4 < len) {
        if (buf[i] != 0xEE || buf[i + 1] != 0xFA) {
            i++;
            *used = i;
            continue;
        }
        int tot = 3 + buf[i + 2] + 1; /* en-tete + len + (cmd + donnees) + somme */
        if (i + tot > len) break;     /* trame incomplete : attendre la suite */
        int sum = 0;
        for (int j = 0; j < tot - 1; j++) sum += buf[i + j];
        if ((unsigned char)sum != buf[i + tot - 1]) {
            i++;
            *used = i;
            continue;
        }
        (*frames)++;
        unsigned char cmd = buf[i + 3];
        if ((cmd == CMD_ACK && buf[i + 2] >= 2 && buf[i + 4] == CMD_PC_READY) || cmd == CMD_VERSION) {
            *used = i + tot;
            return 1;
        }
        i += tot;
        *used = i;
    }
    return 0;
}

int main(void) {
    kmsg_fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);

    int fd = -1;
    for (int t = 0; t < 100 && fd < 0; t++) {
        fd = open(MCU_TTY, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) usleep(100 * 1000);
    }
    if (fd < 0) {
        say(1, "%s introuvable: %s", MCU_TTY, strerror(errno));
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
    unsigned char buf[512];
    int len = 0, sent = 0, frames = 0;
    long long start = now_ms(), last = 0;

    while (now_ms() - start < GIVE_UP_MS) {
        long long gap = sent < FAST_TRIES ? FAST_MS : RETRY_MS;
        if (sent == 0 || now_ms() - last >= gap) {
            mcu_send(fd, CMD_PC_READY, ready, 1);
            last = now_ms();
            sent++;
            say(0, "PC_READY envoye (%d)", sent);
        }
        struct pollfd p = {.fd = fd, .events = POLLIN};
        if (poll(&p, 1, 100) > 0) {
            int n = read(fd, buf + len, sizeof(buf) - len);
            if (n > 0) {
                len += n;
                int used = 0;
                if (scan_frames(buf, len, &used, &frames)) {
                    say(0, "le MCU a recu PC_READY apres %lld ms (%d envoi(s)) : fin", now_ms() - start, sent);
                    close(fd);
                    return 0;
                }
                if (used > 0) {
                    memmove(buf, buf + used, len - used);
                    len -= used;
                }
                if (len > (int)sizeof(buf) - 64) len = 0;
            }
        }
    }
    say(1, "pas de reponse du MCU a PC_READY apres %d s (%d envois, %d trames recues)", GIVE_UP_MS / 1000, sent,
        frames);
    close(fd);
    return 1;
}
