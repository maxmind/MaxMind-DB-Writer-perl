/* *INDENT-ON* */
#ifdef __cplusplus
extern "C" {
#endif

#include "tree.h"

#ifdef __cplusplus
}
#endif

typedef struct perl_iterator_args_s {
    SV *empty_method;
    SV *node_method;
    SV *data_method;
    SV *receiver;
} perl_iterator_args_s;

MMDBW_tree_s *tree_from_self(SV *self)
{
    /* This is a bit wrong since we're looking in the $self hash
       rather than calling a method. I couldn't get method calling
       to work. */
    return *(MMDBW_tree_s **)
           SvPV_nolen(*( hv_fetchs((HV *)SvRV(self), "_tree", 0)));
}

void call_iteration_method(MMDBW_tree_s *tree, perl_iterator_args_s *args,
                           SV *method,
                           const uint64_t node_number,
                           MMDBW_record_s *record,
                           const uint128_t node_ip_num,
                           const uint8_t node_prefix_length,
                           const uint128_t record_ip_num,
                           const uint8_t record_prefix_length,
                           const bool is_right)
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
    PUSHs((SV *)args->receiver);
    mPUSHs(newSVu64(node_number));
    mPUSHi((int)is_right);
    mPUSHs(newSVu128(node_ip_num));
    mPUSHi(node_prefix_length);
    mPUSHs(newSVu128(record_ip_num));
    mPUSHi(record_prefix_length);
    if (MMDBW_RECORD_TYPE_DATA == record->type) {
        mPUSHs(newSVsv(data_for_key(tree, record->value.key)));
    } else if (MMDBW_RECORD_TYPE_NODE == record->type ||
               MMDBW_RECORD_TYPE_ALIAS == record->type) {
        mPUSHi(record->value.node->number);
    }
    PUTBACK;

    int count = call_sv(method, G_VOID);

    SPAGAIN;

    if (count != 0) {
        croak("Expected no items back from ->%s() call", SvPV_nolen(method));
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return;
}

SV *method_for_record_type(perl_iterator_args_s *args, const int record_type)
{
    return MMDBW_RECORD_TYPE_EMPTY == record_type
           ? args->empty_method
           : MMDBW_RECORD_TYPE_NODE == record_type ||
           MMDBW_RECORD_TYPE_ALIAS == record_type
           ? args->node_method
           : args->data_method;
}

void call_perl_object(MMDBW_tree_s *tree, MMDBW_node_s *node,
                      const uint128_t node_ip_num,
                      const uint8_t node_prefix_length,
                      void *void_args)
{
    perl_iterator_args_s *args = (perl_iterator_args_s *)void_args;

    SV *left_method = method_for_record_type(args, node->left_record.type);

    if (NULL != left_method) {
        call_iteration_method(tree,
                              args,
                              left_method,
                              node->number,
                              &(node->left_record),
                              node_ip_num,
                              node_prefix_length,
                              node_ip_num,
                              node_prefix_length + 1,
                              false);
    }

    SV *right_method = method_for_record_type(args, node->right_record.type);
    if (NULL != right_method) {
        const uint8_t max_depth0 = tree->ip_version == 6 ? 127 : 31;
        call_iteration_method(tree,
                              args,
                              right_method,
                              node->number,
                              &(node->right_record),
                              node_ip_num,
                              node_prefix_length,
                              FLIP_NETWORK_BIT(node_ip_num, max_depth0,
                                               node_prefix_length),
                              node_prefix_length + 1,
                              true);
    }
    return;
}

/* It'd be nice to return the CV instead but there's no exposed API for
 * calling a CV directly. */
SV *maybe_method(HV *package, const char *const method)
{
    GV *gv = gv_fetchmethod_autoload(package, method, 1);
    if (NULL != gv) {
        CV *cv = GvCV(gv);
        if (NULL != cv) {
            return newRV_noinc((SV *)cv);
        }
    }

    return NULL;
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
_create_tree(ip_version, record_size, merge_strategy)
    uint8_t ip_version;
    uint8_t record_size;
    MMDBW_merge_strategy merge_strategy;

    CODE:
        RETVAL = new_tree(ip_version, record_size, merge_strategy);

    OUTPUT:
        RETVAL

void
_insert_network(self, ip_address, prefix_length, key, data, force_overwrite)
    SV *self;
    char *ip_address;
    uint8_t prefix_length;
    SV *key;
    SV *data;
    bool force_overwrite;

    CODE:
        insert_network(tree_from_self(self), ip_address, prefix_length, key, data, force_overwrite);

void
_insert_range(self, start_ip_address, end_ip_address, key, data, force_overwrite)
    SV *self;
    char *start_ip_address;
    char *end_ip_address;
    SV *key;
    SV *data;
    bool force_overwrite;

    CODE:
        insert_range(tree_from_self(self), start_ip_address, end_ip_address, key, data, force_overwrite);

void
_remove_network(self, ip_address, prefix_length)
    SV *self;
    char *ip_address;
    uint8_t prefix_length;

    CODE:
        remove_network(tree_from_self(self), ip_address, prefix_length);

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
        if (tree->node_count > MAX_RECORD_VALUE(tree->record_size)) {
            croak("Node count of %u exceeds record size limit of %u bits",
                tree->node_count, tree->record_size);
        }
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
        HV *package;
        /* It's a blessed object */
        if (sv_isobject(object)) {
            package = SvSTASH(SvRV(object));
        /* It's a package name */
        } else if (SvPOK(object) && !SvROK(object)) {
            package = gv_stashsv(object, 0);
        } else {
            croak("The argument passed to iterate (%s) is not an object or class name", SvPV_nolen(object));
        }

        perl_iterator_args_s args = {
            .empty_method = maybe_method(package, "process_empty_record"),
            .node_method = maybe_method(package, "process_node_record"),
            .data_method = maybe_method(package, "process_data_record"),
            .receiver = object
        };
        if (!(NULL != args.empty_method
              || NULL != args.node_method
              || NULL != args.data_method)) {

            croak("The object or class passed to iterate must implement "
                  "at least one method of process_empty_record, "
                  "process_node_record, or process_data_record");
        }

        start_iteration(tree, true, (void *)&args, &call_perl_object);

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
_freeze_tree(self, filename, frozen_params, frozen_params_size)
    SV *self;
    char *filename;
    char *frozen_params;
    int frozen_params_size;

    CODE:
        freeze_tree(tree_from_self(self), filename, frozen_params, frozen_params_size);

MMDBW_tree_s *
_thaw_tree(filename, initial_offset, ip_version, record_size, merge_strategy)
    char *filename;
    int initial_offset;
    int ip_version;
    int record_size;
    MMDBW_merge_strategy merge_strategy;

    CODE:
    RETVAL = thaw_tree(filename, initial_offset, ip_version, record_size, merge_strategy);

    OUTPUT:
        RETVAL

void
_free_tree(self)
    SV *self;

    CODE:
        free_tree(tree_from_self(self));
