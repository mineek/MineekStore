//
//  MineekStore-Bridging-Header.h
//  MineekStore
//
//  Created by Mineek on 02/07/2023.
//

#ifndef MineekStore_Bridging_Header_h
#define MineekStore_Bridging_Header_h

#include <spawn.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

#endif /* MineekStore_Bridging_Header_h */
