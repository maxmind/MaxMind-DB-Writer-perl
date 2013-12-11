/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

/* *INDENT-OFF* */

MODULE = MaxMind::DB::Writer::Tree::InMemory    PACKAGE = MaxMind::DB::Writer::Tree::InMemory

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

int64_t
_node_count(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        finalize_tree(tree);
        RETVAL = tree->node_count;

    OUTPUT:
        RETVAL

void
_free_tree(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        free_tree(tree);
