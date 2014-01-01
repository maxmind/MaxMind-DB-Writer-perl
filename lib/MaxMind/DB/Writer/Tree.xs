/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

int call_int_method(SV *self, char *method)
{
    dSP;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(self);
    PUTBACK;

    int count = call_method(method, G_SCALAR);

    SPAGAIN;

    if (count != 1) {
        croak("Expected one item back from ->%s() call", method);
    }

    int value = POPi;

    PUTBACK;
    FREETMPS;
    LEAVE;

    return value;
}

MMDBW_tree_s *tree_from_self(SV *self)
{
    /* This is a bit wrong since we're looking in the $self hash
       rather than calling a method. I couldn't get method calling
       to work. */
    return *(MMDBW_tree_s **)
           SvPV_nolen(*( hv_fetchs((HV *)SvRV(self), "_tree", 0)));
}

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
    PUSHs((SV *)tree->iteration_args);
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
                          FLIP_NETWORK_BIT(network, max_depth0, depth),
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
_build_tree(self)
    SV *self;

    CODE:
        RETVAL = new_tree((uint8_t)call_int_method(self, "ip_version"),
                          (uint8_t)call_int_method(self, "record_size"),
                          (bool)call_int_method(self, "merge_record_collisions"));

    OUTPUT:
        RETVAL

void
_insert_network(self, network, mask_length, key, data)
    SV *self;
    char *network;
    uint8_t mask_length;
    SV *key;
    SV *data;

    CODE:
        insert_network(tree_from_self(self), network, mask_length, key, data);

void
_write_search_tree(self, output, alias_ipv6, root_data_type, serializer)
    SV *self;
    SV *output;
    bool alias_ipv6;
    SV *root_data_type;
    SV *serializer;

    CODE:
        write_search_tree(tree_from_self(self), output, alias_ipv6, root_data_type, serializer);

uint32_t
_build_node_count(self)
    SV * self;

    CODE:
        MMDBW_tree_s *tree = tree_from_self(self);
        finalize_tree(tree);
        RETVAL = tree->node_count;

    OUTPUT:
        RETVAL

void
iterate(self, object)
    SV *self;
    SV *object;

    CODE:
        MMDBW_tree_s *tree = tree_from_self(self);
        finalize_tree(tree);
        tree->iteration_args = (void *)object;
        start_iteration(tree, &call_perl_object);
        tree->iteration_args = NULL;

void
_create_ipv4_aliases(self)
    SV *self;

    CODE:
        alias_ipv4_networks(tree_from_self(self));

SV *
lookup_ip_address(self, address)
    SV *self;
    char *address;

    CODE:
        RETVAL = lookup_ip_address(tree_from_self(self), address);

    OUTPUT:
        RETVAL

void
_free_tree(self)
    SV *self;

    CODE:
        free_tree(tree_from_self(self));

HV *
_data(self)
    SV *self;

    CODE:
        MMDBW_tree_s *tree = tree_from_self(self);
        RETVAL = tree->data_hash;

    OUTPUT:
        RETVAL
