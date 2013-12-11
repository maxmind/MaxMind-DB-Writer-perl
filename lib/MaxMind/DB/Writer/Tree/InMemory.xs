/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

/* *INDENT-OFF* */

MODULE = MaxMind::DB::Reader::Tree::InMemory    PACKAGE = MaxMind::DB::Reader::Tree::InMemory

#include <stdint.h>

MMDBW_tree_s *
_new_tree(ip_version)
    uint8_t ip_version;

    CODE:
        RETVAL = new_tree(ip_version, 0);

    OUTPUT:
        RETVAL

void
_insert_network(tree, network, mask_length, key, data)
    MMDBW_tree_s *tree;
    char *network;
    uint8_t mask_length;
    SV *key;
    SV *data;

    CODE:
        insert_network(tree, network, mask_length, key, data);

void
_free_tree(tree)
    MMDBW_tree_s *tree;

    CODE:
        free_tree(tree);
