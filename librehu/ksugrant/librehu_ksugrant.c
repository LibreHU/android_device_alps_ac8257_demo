/*
 * Copyright (C) 2026 LibreHU
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Accorde le root de KernelSU Next a LibreHU-service des le premier demarrage de la ROM, comme si l'utilisateur
 * l'avait autorise dans le gestionnaire (sans quoi tactile hors cadre, boutons tactiles, passage de main de l'ARM2,
 * calibration ou reglages du service ne marchent pas tant que personne n'a ouvert KernelSU).
 *
 * Interface du noyau LibreHU (drivers/kernelsu, KernelSU Next legacy, API 5) : reboot(KSU_INSTALL_MAGIC1,
 * KSU_INSTALL_MAGIC2, 0, &fd) installe le descripteur du pilote (root, gestionnaire ou appli deja autorisee :
 * supercall/supercall.c), puis KSU_IOCTL_GET_APP_PROFILE / KSU_IOCTL_SET_APP_PROFILE (manager_or_root :
 * supercall/dispatch.c, supercall/perm.c). Le profil est celui que pose le gestionnaire pour « Superuser » (profil
 * root par defaut, domaine u:r:ksu:s0) ; le noyau l'enregistre dans /data/adb/ksu/.allowlist.
 * Un profil deja present pour l'appli (choix de l'utilisateur, autorise ou refuse) n'est jamais modifie. Lance par
 * librehu_ksugrant.rc une fois Android demarre (liste d'autorisations du noyau deja chargee, uid de l'appli connu).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <dirent.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG(prio, ...) __android_log_print(prio, "LibreHU-KSU", __VA_ARGS__)
#define INFO ANDROID_LOG_INFO
#define WARN ANDROID_LOG_WARN
#else
#define LOG(prio, ...) (fprintf(stderr, __VA_ARGS__), fputc('\n', stderr))
#define INFO 0
#define WARN 1
#endif

/* include/uapi/supercall.h et include/uapi/app_profile.h du noyau (meme disposition en LP64) */
#define KSU_INSTALL_MAGIC1 0xDEADBEEF
#define KSU_INSTALL_MAGIC2 0xCAFEBABE
#define KSU_APP_PROFILE_VER 4
#define KSU_MAX_PACKAGE_NAME 256
#define KSU_MAX_GROUPS 32
#define KSU_SELINUX_DOMAIN 64
#define KSU_IOCTL_GET_APP_PROFILE _IOC(_IOC_READ | _IOC_WRITE, 'K', 11, 0)
#define KSU_IOCTL_SET_APP_PROFILE _IOC(_IOC_WRITE, 'K', 12, 0)

struct root_profile {
    int32_t uid;
    int32_t gid;
    uint32_t groups_count;
    int32_t groups[KSU_MAX_GROUPS];
    struct {
        uint64_t effective;
        uint64_t permitted;
        uint64_t inheritable;
    } capabilities;
    char selinux_domain[KSU_SELINUX_DOMAIN];
    int32_t namespaces;
    uint64_t flags;
};

struct non_root_profile {
    bool umount_modules;
};

struct app_profile {
    uint32_t version;
    char key[KSU_MAX_PACKAGE_NAME];
    int32_t curr_uid;
    bool allow_su;
    union {
        struct {
            bool use_default;
            char template_name[KSU_MAX_PACKAGE_NAME];
            struct root_profile profile;
        } rp_config;
        struct {
            bool use_default;
            struct non_root_profile profile;
        } nrp_config;
    };
};

/* Root par defaut pour [pkg] s'il est installe et n'a encore aucun profil ; 1 en cas d'echec du noyau. */
static int grant(int fd, const char *pkg) {
    char dir[KSU_MAX_PACKAGE_NAME + 16];
    struct stat st;
    struct app_profile p;

    snprintf(dir, sizeof(dir), "/data/data/%s", pkg);
    if (stat(dir, &st) != 0) {
        LOG(INFO, "%s not installed, nothing to grant", pkg);
        return 0;
    }

    memset(&p, 0, sizeof(p));
    p.curr_uid = (int32_t)st.st_uid;
    if (ioctl(fd, KSU_IOCTL_GET_APP_PROFILE, &p) == 0) {
        LOG(INFO, "%s (uid %d) already has a KernelSU profile (root %s): kept", pkg, (int)st.st_uid,
            p.allow_su ? "allowed" : "denied");
        return 0;
    }

    memset(&p, 0, sizeof(p));
    p.version = KSU_APP_PROFILE_VER;
    strncpy(p.key, pkg, sizeof(p.key) - 1);
    p.curr_uid = (int32_t)st.st_uid;
    p.allow_su = true;
    p.rp_config.use_default = true;
    p.rp_config.profile.uid = 0;
    p.rp_config.profile.gid = 0;
    p.rp_config.profile.groups_count = 1;
    p.rp_config.profile.groups[0] = 0;
    p.rp_config.profile.capabilities.effective = ~0ULL;
    p.rp_config.profile.capabilities.permitted = ~0ULL;
    strncpy(p.rp_config.profile.selinux_domain, "u:r:ksu:s0", sizeof(p.rp_config.profile.selinux_domain) - 1);
    if (ioctl(fd, KSU_IOCTL_SET_APP_PROFILE, &p) != 0) {
        LOG(WARN, "granting root to %s (uid %d) failed: %s", pkg, (int)st.st_uid, strerror(errno));
        return 1;
    }
    LOG(INFO, "root granted to %s (uid %d)", pkg, (int)st.st_uid);
    return 0;
}

/* Paquets en arguments (librehu_ksugrant.rc) ; « prefixe* » = tous les paquets installes dont le nom commence par
 * prefixe (dossiers de /data/data) ; LibreHU-service sans argument. */
int main(int argc, char **argv) {
    int fd = -1, failed = 0;

    /* Le noyau ecrit le numero du descripteur dans fd au retour de l'appel (task_work) ; reboot rend -EINVAL. */
    syscall(__NR_reboot, KSU_INSTALL_MAGIC1, KSU_INSTALL_MAGIC2, 0, &fd);
    if (fd < 0) {
        LOG(WARN, "KernelSU driver not available (kernel without KernelSU?)");
        return 0;
    }
    if (argc < 2) {
        return grant(fd, "org.librehu.service");
    }
    for (int i = 1; i < argc; i++) {
        size_t n = strlen(argv[i]);
        if (n > 1 && argv[i][n - 1] == '*') {
            DIR *d = opendir("/data/data");
            struct dirent *e;
            if (d == NULL) {
                LOG(WARN, "/data/data unreadable: %s", strerror(errno));
                failed = 1;
                continue;
            }
            while ((e = readdir(d)) != NULL) {
                if (strncmp(e->d_name, argv[i], n - 1) == 0) {
                    failed |= grant(fd, e->d_name);
                }
            }
            closedir(d);
        } else {
            failed |= grant(fd, argv[i]);
        }
    }
    return failed;
}
