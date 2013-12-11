#!/bin/sh

uncrustify="uncrustify -c .uncrustify.cfg --replace --no-backup"

# We indent each thing twice because uncrustify is not idempotent - in some
# cases it will flip-flop between two indentation styles.
for dir in c; do
    c_files=`find $dir -maxdepth 1 -name '*.c'`
    if [ "$c_files" != "" ]; then
        $uncrustify $c_files;
        $uncrustify $c_files;
    fi
    
    h_files=`find $dir -maxdepth 1 -name '*.h' | grep -v ppport.h`
    if [ "$h_files" != "" ]; then
        $uncrustify $h_files
        $uncrustify $h_files
    fi
done

./dev-bin/regen-prototypes.pl
