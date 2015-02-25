#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdbool.h>
#include <stdint.h>
#include <uthash.h>
#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"
#include "perl_math_int128.h"

#define MMDBW_RECORD_TYPE_EMPTY (0)
#define MMDBW_RECORD_TYPE_DATA (1)
#define MMDBW_RECORD_TYPE_NODE (2)
#define MMDBW_RECORD_TYPE_ALIAS (3)

#define FLIP_NETWORK_BIT(network, max_depth0, depth) \
    ((network) | ((uint128_t)1 << ((max_depth0) - (depth))))

#define MAX_RECORD_VALUE(record_size) \
    (record_size == 32 ? UINT32_MAX : (1 << record_size) - 1)

extern void freeze_tree
(
    MMDBW_tree_s *tree,
    char *filename,
    char *frozen_params,
    size_t frozen_params_size
);
