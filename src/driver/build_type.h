/* driver/build_type.h: the native build levels, in the CMake spelling. */
#ifndef MS_DRIVER_BUILD_TYPE_H
#define MS_DRIVER_BUILD_TYPE_H

#include "driver/pipeline.h"

/* "Debug", "Release" or "MinSizeRel". */
const char *ms_build_type_name(MsBuildType type);

/* The level `name` spells, ignoring case; an empty name is `fallback`. False for any other name. */
MS_NODISCARD bool ms_build_type_parse(MsSpan name, MsBuildType fallback, MsBuildType *out);

#endif
