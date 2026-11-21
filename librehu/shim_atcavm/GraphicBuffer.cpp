// Copyright (C) 2026 LibreHU
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// atcavm_server (Android 9) calls android::GraphicBuffer::lock(uint32_t inUsage, void** vaddr). Android 10 replaced it
// with lock(uint32_t inUsage, void** vaddr, int32_t* outBytesPerPixel = nullptr, int32_t* outBytesPerStride = nullptr)
// (frameworks/native libs/ui/include/ui/GraphicBuffer.h): the old symbol is gone and the linker refused the binary at
// each start ("cannot locate symbol _ZN7android13GraphicBuffer4lockEjPPv", LineageOS 17.1, 21/11/2026). It was the
// only undefined symbol of atcavm_server and of its stock libraries missing from the 17.1 system image (checked
// against the libraries of lineage-17.1-20261121-1132-8027ca6). Same call, the two new outputs not asked for.

#include <ui/GraphicBuffer.h>

extern "C" android::status_t _ZN7android13GraphicBuffer4lockEjPPv(android::GraphicBuffer* buffer, uint32_t inUsage,
                                                                  void** vaddr) {
    return buffer->lock(inUsage, vaddr, nullptr, nullptr);
}
