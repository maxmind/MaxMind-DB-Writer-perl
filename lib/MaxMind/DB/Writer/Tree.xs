/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

void call_iteration_method(MMDBW_tree_s *tree, char *method,
                           uint64_t node_number, MMDBW_record_s *record,
                           uint128_t network, uint8_t depth,
                           uint128_t next_network, uint8_t next_depth,
                           bool is_right)
{
    dSP;

    ENTER;
    SAVETMPS;

    int stack_size =
        MMDBW_RECORD_TYPE_EMPTY == record->type
        ? 7
        : 8;

    PUSHMARK(SP);
    EXTEND(SP, stack_size);
    PUSHs(tree->iteration_receiver);
    PUSHs(sv_2mortal(newSVu64(node_number)));
    PUSHs(sv_2mortal(newSViv((int)is_right)));
    PUSHs(sv_2mortal(newSVu128(network)));
    PUSHs(sv_2mortal(newSViv(depth)));
    PUSHs(sv_2mortal(newSVu128(next_network)));
    PUSHs(sv_2mortal(newSViv(next_depth)));
    if (MMDBW_RECORD_TYPE_DATA == record->type) {
        PUSHs(sv_2mortal(newSVsv(
                             data_for_key(tree, record->value.key))));
    } else if (MMDBW_RECORD_TYPE_NODE == record->type) {
        PUSHs(sv_2mortal(newSViv(record->value.node->number)));
    }
    PUTBACK;

    int count = call_method(method, G_VOID);

    SPAGAIN;

    if (count != 0) {
        croak("Expected no items back from ->%s() call", method);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return;
}

char *method_for_record_type(int record_type)
{
    return MMDBW_RECORD_TYPE_EMPTY == record_type
           ? "process_empty_record"
           : MMDBW_RECORD_TYPE_NODE == record_type
           ? "process_node_record"
           : "process_data_record";
}

void call_perl_object(MMDBW_tree_s *tree, MMDBW_node_s *node,
                      uint128_t network, uint8_t depth)
{
    call_iteration_method(tree,
                          method_for_record_type(node->left_record.type),
                          node->number,
                          &(node->left_record),
                          network,
                          depth,
                          network,
                          depth + 1,
                          false);

    uint8_t max_depth0 = tree->ip_version == 6 ? 127 : 31;
    call_iteration_method(tree,
                          method_for_record_type(node->right_record.type),
                          node->number,
                          &(node->right_record),
                          network,
                          depth,
                          network | (1 << (max_depth0 - depth)),
                          depth + 1,
                          true);
    return;
}

/* *INDENT-OFF* */

/* XXX - it'd be nice to find a way to get the tree from the XS code so we
 * don't have to pass it in all over place - it'd also let us remove at least
 * a few shim methods on the Perl code. */

MODULE = MaxMind::DB::Writer::Tree    PACKAGE = MaxMind::DB::Writer::Tree

#include <stdint.h>

BOOT:
    PERL_MATH_INT128_LOAD_OR_CROAK;

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
_write_search_tree(self, tree, output, alias_ipv6, root_data_type, serializer)
    MMDBW_tree_s *tree;
    SV *output;
    bool alias_ipv6;
    SV *root_data_type;
    SV *serializer;

    CODE:
        write_search_tree(tree, output, alias_ipv6, root_data_type, serializer);

int64_t
_node_count(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        finalize_tree(tree);
        RETVAL = tree->node_count;

    OUTPUT:
        RETVAL

void
_iterate(self, tree, object)
    MMDBW_tree_s *tree;
    SV *object;

    CODE:
        finalize_tree(tree);
        tree->iteration_receiver = object;
        start_iteration(tree, &call_perl_object);
        tree->iteration_receiver = NULL;

void
__create_ipv4_aliases(self, tree)
    MMDBW_tree_s *tree;

    CODE:
        alias_ipv4_networks(tree);

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
