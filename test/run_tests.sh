#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of increasing difficulty. The result is compared to references.
#  - Test compiling generated code with gcc. Generated binary and execute.
#  Stage 2. Distributed.
#  - Test stub generation when the interface to stub is recursive and in more than one file.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

function check_status() {
    CHECK_STATUS_RVAL=$?
    MSG=$1
    if [[ $CHECK_STATUS_RVAL -eq 0 ]]; then
        echo -e "${C_GREEN}=== $MSG OK ===${C_NONE}"
    else
        echo -e "${C_RED}=== $MSG ERROR ===${C_NONE}"
    fi
}

function test_compl_code() {
    outdir=$1
    inclpath=$2
    impl=$3
    main=$4

    echo -e "${C_YELLOW}=== Compile $impl  ===${C_NONE}"
    echo "g++ -std=c++11 -o $outdir/binary -I$outdir -I$inclpath $impl $main"
    g++ -std=c++11 -o "$outdir"/binary -I"$outdir" -I"$inclpath" "$impl" "$main"
    "$outdir"/binary
}

function test_gen_code() {
    outdir=$1
    inhdr=$2

    expect_hdr="$(dirname ${inhdr})/"$(basename ${inhdr})".ref"
    expect_impl="$(dirname ${inhdr})"/$(basename -s .hpp $inhdr)".cpp.ref"
    out_hdr="$outdir/stub_"$(basename ${inhdr})
    out_impl="$outdir/stub_"$(basename -s .hpp ${inhdr})".cpp"

    echo -e "${C_YELLOW}=== $inhdr  ===${C_NONE}"
    echo -e "\t${expect_hdr} ${expect_impl}" "\t$PWD/${out_hdr}"
    ../build/gen-test-double stub --debug $inhdr $outdir

    diff -u "${expect_hdr}" "${out_hdr}"
    if [[ -e "${expect_impl}" ]]; then
        diff -u "${expect_impl}" "${out_impl}"
    fi
}

outdir="outdata"
if [[ ! -d "$outdir" ]]; then
    mkdir "$outdir"
fi

echo "Stage 1"
for sourcef in testdata/stage_1/*.hpp; do
    test_gen_code "$outdir" "$sourcef"

    out_impl="$outdir/stub_"$(basename -s .hpp ${sourcef})".cpp"
    case "$sourcef" in
        *class_funcs*) ;;
        *class_simple*) ;;
        *)
        test_compl_code "$outdir" "testdata/stage_1" "$out_impl" main1.cpp
        ;;
    esac

    rm "$outdir"/*
done

echo "Stage 2"
test_gen_code "$outdir" "testdata/stage_2/case1/ifs1.hpp"
test_compl_code "$outdir" "testdata/stage_2/case1" "$outdir/stub_ifs1.cpp" "testdata/stage_2/main.cpp"

echo "Stage 3"
test_gen_code "$outdir" "testdata/stage_3/ifs1.hpp"
test_compl_code "$outdir" "testdata/stage_3" "$outdir/stub_ifs1.cpp" "testdata/stage_3/main.cpp"

rm -r "$outdir"

exit 0
