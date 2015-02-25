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

typedef struct thawed_network_s
{
    MMDBW_network_s *network;
    MMDBW_record_s *record;
}
thawed_network_s;

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

