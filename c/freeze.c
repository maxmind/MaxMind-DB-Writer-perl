#include "tree.h"

#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <errno.h>
#include <inttypes.h>
#include <netdb.h>
#include <stdbool.h>
#include <stdio.h>

#ifdef __GNUC__
#  define UNUSED(x) UNUSED_ ## x __attribute__((__unused__))
#else
#  define UNUSED(x) UNUSED_ ## x
#endif

/* 16 bytes for an IP address, 1 byte for the prefix length */
#define FROZEN_RECORD_MAX_SIZE (16 + 1 + SHA1_KEY_LENGTH)
#define FROZEN_NODE_MAX_SIZE (FROZEN_RECORD_MAX_SIZE * 2)

/* 17 bytes of NULLs followed by something that cannot be an SHA1 key are a
   clear indicator that there are no more frozen networks in the buffer. */
#define SEVENTEEN_NULLS "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
#define FREEZE_SEPARATOR "not an SHA1 key"

typedef struct freeze_args_s
{
    uint8_t *buffer;
    size_t buffer_used;
    size_t max_size;
    uint8_t *buffer_start;
    HV *data_hash;
}
freeze_args_s;

static void freeze_node
(
    MMDBW_tree_s *tree,
    MMDBW_node_s *node,
    mmdbw_uint128_t network,
    uint8_t depth
);

static void freeze_data_record
(
    MMDBW_tree_s *tree,
    mmdbw_uint128_t network,
    uint8_t depth,
    const char const *key
);

static void freeze_to_buffer
(
    freeze_args_s *args,
    void *data,
    size_t size,
    char *what
);

static void freeze_data_hash_to_fd
(
    int fd,
    freeze_args_s *args
);

static SV *freeze_hash
(
    HV *hash
);

void freeze_tree
(
    MMDBW_tree_s *tree,
    char *filename,
    char *frozen_params,
    size_t frozen_params_size
)
{
    finalize_tree(tree);

    int fd = open(filename, O_CREAT | O_TRUNC | O_RDWR, (mode_t)0644);
    if (-1 == fd) {
        croak("Could not open file %s: %s", filename, strerror(errno));
    }

    /* This is much larger than we need, because it assumes that every node in
       the tree contains two data records, which will never happen. It's a lot
       simpler to allocate this and then truncate it later. */
    size_t buffer_size = 4 /* the size of the frozen constructor params (uint32_t) */
                         + frozen_params_size
                         + (tree->node_count * FROZEN_NODE_MAX_SIZE)
                         + 17 /* seventeen null separator */
                         + strlen(FREEZE_SEPARATOR);
    resize_file(fd, filename, buffer_size);

    uint8_t *buffer =
        (uint8_t *)mmap(NULL, buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED,
                        fd, 0);
    if (MAP_FAILED == buffer) {
        close(fd);
        croak("mmap() failed: %s", strerror(errno));
    }

    /* We want to save this so we can do some error checking later and make
       sure we don't exceed our buffer size while freezing things. */
    uint8_t *buffer_start = buffer;

    freeze_args_s args = {
        .buffer       = buffer,
        .buffer_used  = 0,
        .max_size     = buffer_size,
        .buffer_start = buffer_start,
        .data_hash    = newHV()
    };

    freeze_to_buffer(&args, &frozen_params_size, 4, "frozen_params_size");
    freeze_to_buffer(&args, frozen_params, frozen_params_size, "frozen_params");

    tree->iteration_args = (void *)&args;
    start_iteration(tree, false, &freeze_node);
    tree->iteration_args = NULL;

    freeze_to_buffer(&args, SEVENTEEN_NULLS, 17, "SEVENTEEN_NULLS");
    freeze_to_buffer(&args, FREEZE_SEPARATOR,
                     strlen(FREEZE_SEPARATOR), "FREEZE_SEPARATOR");

    if (-1 == msync(buffer_start, buffer_size, MS_SYNC)) {
        close(fd);
        croak("msync() failed: %s", strerror(errno));
    }

    if (-1 == munmap(buffer_start, buffer_size)) {
        close(fd);
        croak("munmap() failed: %s", strerror(errno));
    }

    if (-1 == ftruncate(fd, args.buffer_used)) {
        croak("Could not truncate file %s: %s", filename, strerror(errno));
    }

    if (-1 == close(fd)) {
        croak("Could not close file %s: %s", filename, strerror(errno));
    }

    fd = open(filename, O_WRONLY | O_APPEND, (mode_t)0);
    if (-1 == fd) {
        croak("Could not append to file %s: %s", filename, strerror(errno));
    }

    freeze_data_hash_to_fd(fd, &args);

    if (-1 == close(fd)) {
        croak("Could not close file %s: %s", filename, strerror(errno));
    }

    /* When the hash is _freed_, Perl decrements the ref count for each value
     * so we don't need to mess with them. */
    SvREFCNT_dec((SV *)args.data_hash);
}

static void freeze_node
(
    MMDBW_tree_s *tree,
    MMDBW_node_s *node,
    mmdbw_uint128_t network,
    uint8_t depth
)
{
    const uint8_t max_depth0 = tree->ip_version == 6 ? 127 : 31;
    const uint8_t next_depth = depth + 1;

    if (MMDBW_RECORD_TYPE_DATA == node->left_record.type) {
        freeze_data_record(tree, network, next_depth,
                           node->left_record.value.key);
    }

    if (MMDBW_RECORD_TYPE_DATA == node->right_record.type) {
        mmdbw_uint128_t right_network =
            FLIP_NETWORK_BIT(network, max_depth0, depth);
        freeze_data_record(tree, right_network, next_depth,
                           node->right_record.value.key);
    }
}

static void freeze_data_record
(
    MMDBW_tree_s *tree,
    mmdbw_uint128_t network,
    uint8_t depth,
    const char const *key
)
{
    freeze_args_s *args = tree->iteration_args;

    /* It'd save some space to shrink this to 4 bytes for IPv4-only trees, but
     * that would also complicated thawing quite a bit. */
    freeze_to_buffer(args, &network, 16, "network");
    freeze_to_buffer(args, &(depth), 1, "depth");

    SV *data_sv = data_for_key(tree, key);
    SvREFCNT_inc_simple_void_NN(data_sv);

    freeze_to_buffer(args, (char *)key, SHA1_KEY_LENGTH, "key");
    (void)hv_store(args->data_hash, key, SHA1_KEY_LENGTH, data_sv, 0);
}

static void freeze_to_buffer
(
    freeze_args_s *args,
    void *data,
    size_t size,
    char *what
)
{
    if ((args->buffer - args->buffer_start) + size >= args->max_size) {
        croak(
            "About to write past end of mmap buffer with %s - (%p - %p) + %zu = %tu > %zu\n",
            what,
            args->buffer,
            args->buffer_start,
            size,
            (args->buffer - args->buffer_start) + size,
            args->max_size);
    }
    memcpy(args->buffer, data, size);
    args->buffer += size;
    args->buffer_used += size;
}

static void freeze_data_hash_to_fd
(
    int fd,
    freeze_args_s *args
)
{
    SV *frozen_data = freeze_hash(args->data_hash);
    STRLEN frozen_data_size;
    char *frozen_data_chars = SvPV(frozen_data, frozen_data_size);

    ssize_t written = write(fd, &frozen_data_size, sizeof(STRLEN));
    if (-1 == written) {
        croak("Could not write frozen data size to file: %s", strerror(errno));
    }
    if (written != sizeof(STRLEN)) {
        croak("Could not write frozen data size to file: %zd != %zu", written,
              sizeof(STRLEN));
    }

    written = write(fd, frozen_data_chars, frozen_data_size);
    if (-1 == written) {
        croak("Could not write frozen data size to file: %s", strerror(errno));
    }
    if (written != frozen_data_size) {
        croak("Could not write frozen data to file: %zd != %zu", written,
              frozen_data_size);
    }

    SvREFCNT_dec(frozen_data);
}

static SV *freeze_hash
(
    HV *hash
)
{
    dSP;
    ENTER;
    SAVETMPS;

    SV *hashref = sv_2mortal(newRV_inc((SV *)hash));

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(hashref);
    PUTBACK;

    int count = call_pv("Sereal::Encoder::encode_sereal", G_SCALAR);

    SPAGAIN;

    if (count != 1) {
        croak("Expected 1 item back from Sereal::Encoder::encode_sereal call");
    }

    SV *frozen = POPs;
    if (!SvPOK(frozen)) {
        croak(
            "The Sereal::Encoder::encode_sereal sub returned an SV which is not SvPOK!");
    }

    /* The SV will be mortal so it's about to lose a ref with the FREETMPS
       call below. */
    SvREFCNT_inc_simple_void_NN(frozen);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return frozen;
}
