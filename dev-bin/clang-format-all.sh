#!/bin/sh

format="clang-format -i -style=file"

for file in "c/tree.c" "c/tree.h" "lib/MaxMind/DB/Writer/Tree.xs"; do
    $format $file
done
