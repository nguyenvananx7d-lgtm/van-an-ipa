//
//  ghost_hook.c — arm64 inline hook + trampoline.
//

#include "ghost_hook.h"

#include <mach/mach.h>
#include <sys/mman.h>
#include <string.h>
#include <libkern/OSCacheControl.h>

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

/* The iOS 26 SDK hides <mach/mach_vm.h>; the symbols are still exported. */
extern kern_return_t mach_vm_allocate(mach_port_t task, uint64_t *address,
                                      uint64_t size, int flags);
extern kern_return_t mach_vm_deallocate(mach_port_t task, uint64_t address,
                                        uint64_t size);
extern kern_return_t mach_vm_protect(mach_port_t task, uint64_t address,
                                     uint64_t size, boolean_t set_maximum,
                                     vm_prot_t new_protection);

#define GHOST_PATCH_LEN 16
#define GHOST_TRAMP_SIZE 32
#define GHOST_SLOT_COUNT 16

typedef struct {
    void *target;
    uint8_t saved[GHOST_PATCH_LEN];
    void *trampoline;
    size_t trampolineSize;
    int trampolineIsMach;
    int installed;
} GhostHookSlot;

static GhostHookSlot slots[GHOST_SLOT_COUNT];
static int slotCount;

/* `movz x16, #lo16; movk x16, #mid16, lsl #16;
   movk x16, #hi16, lsl #32; br x16`

   The four-instruction form is deliberate: a literal load would need the
   `.quad` at offset 8 to be naturally aligned, and an arm64 function is only
   guaranteed 4-byte aligned. movz/movk has no alignment requirement. iOS user
   addresses fit in 48 bits, so three immediates cover the whole pointer. */
static void write_branch(uint8_t *at, void *destination) {
    uint64_t dest = (uint64_t)(uintptr_t)destination;
    uint32_t movz = 0xD2800000u | (uint32_t)((dest & 0xFFFFu) << 5) | 16u;
    uint32_t movk1 = 0xF2800000u | (1u << 21) |
                     (uint32_t)(((dest >> 16) & 0xFFFFu) << 5) | 16u;
    uint32_t movk2 = 0xF2800000u | (2u << 21) |
                     (uint32_t)(((dest >> 32) & 0xFFFFu) << 5) | 16u;
    uint32_t br = 0xD61F0200u; /* br x16 */
    memcpy(at, &movz, 4);
    memcpy(at + 4, &movk1, 4);
    memcpy(at + 8, &movk2, 4);
    memcpy(at + 12, &br, 4);
}

static int make_writable(void *address, size_t size) {
    uintptr_t start = (uintptr_t)address & ~(uintptr_t)0x3FFF;
    uintptr_t end = ((uintptr_t)address + size + 0x3FFF) & ~(uintptr_t)0x3FFF;
    size_t length = end - start;

    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)start, length,
                                  FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr == KERN_SUCCESS) return 1;

    /* On a code-signed mapping the kernel may refuse a plain writable request
       but accept a private copy-on-write one; the target keeps its own page. */
    kr = vm_protect(mach_task_self(), (vm_address_t)start, length,
                    FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) return 1;

    /* Some builds answer mprotect but refuse vm_protect; try the libc spelling
       before giving up. */
    if (mprotect((void *)start, length, PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
        return 1;
    }
    return 0;
}

/* Trampoline pages are allocated read/write, filled, then flipped to RX. mmap
   is the normal path; mach_vm_allocate covers a process where anonymous
   executable mappings are refused at mmap time. */
static void *alloc_rw_page(size_t size, int *isMach) {
    if (isMach != NULL) *isMach = 0;
    void *page = mmap(NULL, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    if (page != MAP_FAILED) return page;

    mach_vm_address_t address = 0;
    kern_return_t kr = mach_vm_allocate(mach_task_self(), &address, size,
                                        VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS || address == 0) return NULL;
    if (isMach != NULL) *isMach = 1;
    return (void *)(uintptr_t)address;
}

static int protect_exec(void *page, size_t size, int isMach) {
    if (!isMach) {
        if (mprotect(page, size, PROT_READ | PROT_EXEC) == 0) return 1;
    }
    kern_return_t kr = mach_vm_protect(mach_task_self(),
                                       (mach_vm_address_t)(uintptr_t)page,
                                       size, FALSE,
                                       VM_PROT_READ | VM_PROT_EXECUTE);
    return kr == KERN_SUCCESS;
}

static void free_page(void *page, size_t size, int isMach) {
    if (page == NULL) return;
    if (isMach) {
        mach_vm_deallocate(mach_task_self(), (mach_vm_address_t)(uintptr_t)page,
                           size);
    } else {
        munmap(page, size);
    }
}

int ghost_make_writable(void *address, size_t size) {
    return make_writable(address, size);
}

int ghost_hook_pointer(void **slot, void *replacement, void **original_out) {
    if (slot == NULL || replacement == NULL) return -1;
    void *target = *slot;
    if (target == NULL) return -1;

    void *trampoline = NULL;
    int rc = ghost_hook_install(target, replacement, &trampoline);
    if (rc == 0) {
        if (original_out != NULL) *original_out = trampoline;
        return 0;
    }

    /* The prologue opens with an ADRP/ADDR/LDR-literal, so the displaced
       bytes cannot be replayed from a different address. Swapping the slot is
       data-only and always works, at the cost of missing direct calls that
       cached the pointer before we ran. */
    if (!make_writable(slot, sizeof(void *))) return rc;
    if (original_out != NULL) *original_out = target;
    *slot = replacement;
    return 0;
}

/* Instructions that encode an address relative to PC cannot be replayed from a
   different address. A prologue that opens with one of them is not hookable
   this way. */
static int prologue_is_relocatable(const uint8_t *code) {
    for (int i = 0; i < 4; i++) {
        uint32_t insn;
        memcpy(&insn, code + i * 4, 4);
        if ((insn & 0x1F000000u) == 0x10000000u) return 0; /* adr / adrp   */
        if ((insn & 0x7C000000u) == 0x14000000u) return 0; /* b / bl       */
        if ((insn & 0x3B000000u) == 0x18000000u) return 0; /* ldr literal  */
        if ((insn & 0x7E000000u) == 0x34000000u) return 0; /* cbz / cbnz   */
        if ((insn & 0x7E000000u) == 0x36000000u) return 0; /* tbz / tbnz   */
        if ((insn & 0xFFFFFC1Fu) == 0xD61F0000u) return 0; /* br           */
        if ((insn & 0xFFFFFC1Fu) == 0xD63F0000u) return 0; /* blr          */
        if (insn == 0xD65F03C0u) return 0;                 /* ret          */
    }
    return 1;
}

int ghost_hook_install(void *target, void *replacement, void **original_out) {
    if (target == NULL || replacement == NULL) return -1;
    if (slotCount >= GHOST_SLOT_COUNT) return -1;

    uint8_t *code = (uint8_t *)target;
    if (!prologue_is_relocatable(code)) return -2;

    int isMach = 0;
    void *page = alloc_rw_page(0x4000, &isMach);
    if (page == NULL) return -1;

    uint8_t *trampoline = (uint8_t *)page;
    memcpy(trampoline, code, GHOST_PATCH_LEN);
    write_branch(trampoline + GHOST_PATCH_LEN, code + GHOST_PATCH_LEN);

    if (!protect_exec(page, 0x4000, isMach)) {
        free_page(page, 0x4000, isMach);
        return -1;
    }
    sys_icache_invalidate(page, GHOST_TRAMP_SIZE);

    if (!make_writable(target, GHOST_PATCH_LEN)) {
        free_page(page, 0x4000, isMach);
        return -1;
    }

    GhostHookSlot *slot = &slots[slotCount];
    memcpy(slot->saved, code, GHOST_PATCH_LEN);
    slot->target = target;
    slot->trampoline = page;
    slot->trampolineSize = 0x4000;
    slot->trampolineIsMach = isMach;
    slot->installed = 1;

    write_branch(code, replacement);
    sys_icache_invalidate(code, GHOST_PATCH_LEN);
    slotCount++;

    if (original_out != NULL) *original_out = trampoline;
    return 0;
}

int ghost_hook_remove(void *target) {
    for (int i = 0; i < slotCount; i++) {
        GhostHookSlot *slot = &slots[i];
        if (slot->target != target || !slot->installed) continue;
        if (!make_writable(target, GHOST_PATCH_LEN)) return -1;
        memcpy(target, slot->saved, GHOST_PATCH_LEN);
        sys_icache_invalidate(target, GHOST_PATCH_LEN);
        slot->installed = 0;
        if (slot->trampoline != NULL) {
            free_page(slot->trampoline, slot->trampolineSize,
                      slot->trampolineIsMach);
            slot->trampoline = NULL;
        }
        return 0;
    }
    return -1;
}
