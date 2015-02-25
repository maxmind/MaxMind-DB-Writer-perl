#include "tree.h"
#include "util.h"

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


#define LOCAL

#ifdef __GNUC__
#  define UNUSED(x) UNUSED_ ## x __attribute__((__unused__))
#else
#  define UNUSED(x) UNUSED_ ## x
#endif

#define NETWORK_BIT_VALUE(network, current_bit)                    \
    (network)->bytes[((network)->max_depth0 - (current_bit)) >> 3] \
    & (1U << (~((network)->max_depth0 - (current_bit)) & 7))

/* This is also defined in MaxMind::DB::Common but we don't want to have to
 * fetch it every time we need it. */
#define DATA_SECTION_SEPARATOR_SIZE (16)

#define SHA1_KEY_LENGTH (27)

#define NETWORK_IS_IPV6(network) (127 == network->max_depth0)

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

typedef struct thawed_network_s
{
    MMDBW_network_s *network;
    MMDBW_record_s *record;
}
thawed_network_s;

LOCAL void freeze_node
(
    MMDBW_tree_s *tree,
    MMDBW_node_s *node,
    mmdbw_uint128_t network,
    uint8_t depth
);

LOCAL void freeze_data_record
(
    MMDBW_tree_s *tree,
    mmdbw_uint128_t network,
    uint8_t depth,
    const char const *key
);

LOCAL void freeze_to_buffer
(
    freeze_args_s *args,
    void *data,
    size_t size,
    char *what
);

LOCAL void freeze_data_hash_to_fd
(
    int fd,
    freeze_args_s *args
);

LOCAL SV *freeze_hash(HV *hash);

LOCAL uint8_t thaw_uint8
(
    uint8_t **buffer
);

LOCAL uint32_t thaw_uint32
(
    uint8_t **buffer
);

LOCAL thawed_network_s *thaw_network
(
    MMDBW_tree_s *tree,
    uint8_t **buffer
);

LOCAL uint8_t *thaw_bytes
(
    uint8_t **buffer,
    size_t size
);

LOCAL mmdbw_uint128_t thaw_uint128
(
    uint8_t **buffer
);

LOCAL STRLEN thaw_strlen
(
    uint8_t **buffer
);

LOCAL const char const *thaw_data_key
(
    uint8_t **buffer
);

LOCAL HV *thaw_data_hash
(
    SV *data_to_decode
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

LOCAL void freeze_node
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

LOCAL void freeze_data_record
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

LOCAL void freeze_to_buffer(freeze_args_s *args, void *data, size_t size,
                            char *what)
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

LOCAL void freeze_data_hash_to_fd(int fd, freeze_args_s *args)
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

LOCAL SV *freeze_hash(HV *hash)
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

MMDBW_tree_s *thaw_tree(char *filename, uint32_t initial_offset,
                        uint8_t ip_version, uint8_t record_size,
                        bool merge_record_collisions)
{
    int fd = open(filename, O_RDONLY, 0);
    if (-1 == fd) {
        croak("Could not open file %s: %s", filename, strerror(errno));
    }

    struct stat fileinfo;
    if (-1 == fstat(fd, &fileinfo)) {
        croak("Could not stat file: %s: %s", filename, strerror(errno));
    }

    uint8_t *buffer =
        (uint8_t *)mmap(NULL, fileinfo.st_size, PROT_READ, MAP_SHARED, fd,
                        0);
    buffer += initial_offset;

    MMDBW_tree_s *tree = new_tree(ip_version, record_size,
                                  merge_record_collisions);

    thawed_network_s *thawed;
    while (NULL != (thawed = thaw_network(tree, &buffer))) {
        insert_record_for_network(tree, thawed->network, thawed->record,
                                  tree->merge_record_collisions);
        free_network(thawed->network);
        free(thawed->network);
        free(thawed->record);
        free(thawed);
    }

    STRLEN frozen_data_size = thaw_strlen(&buffer);

    /* per-perlapi newSVpvn copies the string */
    SV *data_to_decode =
        sv_2mortal(newSVpvn((char *)buffer, frozen_data_size));
    HV *data_hash = thaw_data_hash(data_to_decode);

    hv_iterinit(data_hash);
    char *key;
    I32 keylen;
    SV *value;
    while (NULL != (value = hv_iternextsv(data_hash, &key, &keylen))) {
        (void)store_data_in_tree(tree, key, value);
    }

    SvREFCNT_dec((SV *)data_hash);

    finalize_tree(tree);

    return tree;
}

LOCAL uint8_t thaw_uint8(uint8_t **buffer)
{
    uint8_t value;
    memcpy(&value, *buffer, 1);
    *buffer += 1;
    return value;
}

LOCAL uint32_t thaw_uint32(uint8_t **buffer)
{
    uint32_t value;
    memcpy(&value, *buffer, 4);
    *buffer += 4;
    return value;
}

LOCAL thawed_network_s *thaw_network(MMDBW_tree_s *tree, uint8_t **buffer)
{
    mmdbw_uint128_t start_ip = thaw_uint128(buffer);
    uint8_t prefix_length = thaw_uint8(buffer);

    if (0 == start_ip && 0 == prefix_length) {
        uint8_t *maybe_separator = thaw_bytes(buffer, strlen(FREEZE_SEPARATOR));
        if (memcmp(maybe_separator, FREEZE_SEPARATOR,
                   strlen(FREEZE_SEPARATOR)) == 0) {

            buffer -= strlen(FREEZE_SEPARATOR);
            buffer -= 17;
            free(maybe_separator);
            return NULL;
        }
        free(maybe_separator);
    }

    uint8_t *start_ip_bytes = (uint8_t *)&start_ip;
    uint8_t temp;
    for (int i = 0; i < 8; i++) {
        temp = start_ip_bytes[i];
        start_ip_bytes[i] = start_ip_bytes[15 - i];
        start_ip_bytes[15 - i] = temp;
    }

    thawed_network_s *thawed = checked_malloc(sizeof(thawed_network_s));

    uint8_t *bytes;
    if (tree->ip_version == 4) {
        bytes = checked_malloc(4);
        memcpy(bytes, start_ip_bytes + 12, 4);
    } else {
        bytes = checked_malloc(16);
        memcpy(bytes, &start_ip, 16);
    }

    MMDBW_network_s network = {
        .bytes          = bytes,
        .prefix_length  = prefix_length,
        .max_depth0     = 4 == tree->ip_version ? 31 : 127,
        .address_string = "thawed network",
    };

    thawed->network = checked_malloc(sizeof(MMDBW_network_s));
    memcpy(thawed->network, &network, sizeof(MMDBW_network_s));

    MMDBW_record_s *record = checked_malloc(sizeof(MMDBW_record_s));
    record->type = MMDBW_RECORD_TYPE_DATA;
    record->value.key = thaw_data_key(buffer);
    thawed->record = record;

    return thawed;
}

LOCAL uint8_t *thaw_bytes(uint8_t **buffer, size_t size)
{
    uint8_t *value = checked_malloc(size);
    memcpy(value, *buffer, size);
    *buffer += size;
    return value;
}

LOCAL mmdbw_uint128_t thaw_uint128(uint8_t **buffer)
{
    mmdbw_uint128_t value;
    memcpy(&value, *buffer, 16);
    *buffer += 16;
    return value;
}

LOCAL STRLEN thaw_strlen(uint8_t **buffer)
{
    STRLEN value;
    memcpy(&value, *buffer, sizeof(STRLEN));
    *buffer += sizeof(STRLEN);
    return value;
}

LOCAL const char const *thaw_data_key(uint8_t **buffer)
{
    /* Note that we do _not_ free this data when we free the thawed_record_s
       structures. We'll copy this pointer directly into the tree->data_hash
       struct as our key, and it will be freed when the tree itself is
       freed. */
    char *value = checked_malloc(SHA1_KEY_LENGTH + 1);
    memcpy(value, *buffer, SHA1_KEY_LENGTH);
    *buffer += SHA1_KEY_LENGTH;
    value[SHA1_KEY_LENGTH] = '\0';
    return (const char const *)value;
}

LOCAL HV *thaw_data_hash(SV *data_to_decode)
{
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(data_to_decode);
    PUTBACK;

    int count = call_pv("Sereal::Decoder::decode_sereal", G_SCALAR);

    SPAGAIN;

    if (count != 1) {
        croak("Expected 1 item back from Sereal::Decoder::decode_sereal call");
    }

    SV *thawed = POPs;
    if (!SvROK(thawed)) {
        croak(
            "The Sereal::Decoder::decode_sereal sub returned an SV which is not SvROK!");
    }

    SvREFCNT_inc_simple_void_NN(thawed);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return (HV *)SvRV(thawed);
}

