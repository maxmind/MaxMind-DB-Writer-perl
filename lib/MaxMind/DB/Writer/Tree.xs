/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

/* *INDENT-OFF* */

/* XXX - it'd be nice to find a way to get the tree from the XS code so we
 * don't have to pass it in all over place - it'd also let us remove at least
 * a few shim methods on the Perl code. */

MODULE = MaxMind::DB::Writer::Tree    PACKAGE = MaxMind::DB::Writer::Tree

#include <stdint.h>

MMDBW_tree_s *
_new_tree(self, ip_version, record_size)
    uint8_t ip_version;
    uint8_t record_size;

    CODE:
        RETVAL = new_tree(ip_version, record_size, 0);

    OUTPUT:
        RETVAL

void
_insert_network(self, tree, network, mask_length, key, data)
    MMDBW_tree_s *tree;
    char *network;
    uint8_t mask_length;
    SV *key;
    SV *data;

    CODE:
        insert_network(tree, network, mask_length, key, data);

void
_write_search_tree(self, tree, output, root_data_type, serializer)
    MMDBW_tree_s *tree;
    SV *output;
    SV *root_data_type;
    SV *serializer;

    CODE:
        write_search_tree(tree, output, root_data_type, serializer);

int64_t
_node_count(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        finalize_tree(tree);
        RETVAL = tree->node_count;

    OUTPUT:
        RETVAL

SV *
_lookup_ip_address(self, tree, address)
    MMDBW_tree_s *tree;
    char *address;

    CODE:
        RETVAL = lookup_ip_address(tree, address);

    OUTPUT:
        RETVAL

void
_free_tree(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        free_tree(tree);

HV *
_data(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        RETVAL = tree->data_hash;

    OUTPUT:
        RETVAL
