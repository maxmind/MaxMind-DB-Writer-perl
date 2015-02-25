extern MMDBW_tree_s *thaw_tree
(
    char *filename,
    uint32_t initial_offset,
    uint8_t ip_version,
    uint8_t record_size,
    bool merge_record_collisions
);
