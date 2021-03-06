package: o2checkcode
requires:
  - O2
  - o2codechecker
build_requires:
  - CMake
force_rebuild: 1
version: "1.0"
---
#!/bin/bash -e

# Run the code checker with ALICE-specific rules and no others. Assumes the
# compile_commands.json file is available under $O2_ROOT
cp "${O2_ROOT}"/compile_commands.json .

# TODO: preprocessing on compile_commands.json, such as:
# * Filtering out ROOT dict results,
# * Filtering files relevant for the pull request to run checks on them only

# List of enabled checks (make sure they are all green)
CHECKS="${O2_CHECKER_CHECKS:--*,modernize-*,-modernize-use-default,-modernize-pass-by-value,-modernize-use-auto,-modernize-use-bool-literals,-modernize-use-using,-modernize-loop-convert,-modernize-use-bool-literals,-modernize-make-unique,aliceO2-member-name}"

# Run checks
run_O2CodeChecker.py -clang-tidy-binary $(which O2codecheck) -header-filter=.*SOURCES.* ${O2_CHECKER_FIX:+-fix} -checks=${CHECKS} 2>&1 | tee error-log.txt

# Turn warnings into errors
sed -e 's/ warning:/ error:/g' error-log.txt > error-log.txt.0 && mv error-log.txt.0 error-log.txt

# Get full list of .cxx/.h files
O2_SRC=$(python -c 'import json,sys,os; sys.stdout.write( os.path.commonprefix([ x["file"] for x in json.loads(open("compile_commands.json").read()) if not "G__" in x["file"] and x["file"].endswith(".cxx") ]) )')
[[ -e $O2_SRC/CMakeLists.txt ]]

# Run copyright notice check
COPYRIGHT="$(cat <<'EOF'
// Copyright CERN and copyright holders of ALICE O2. This software is
// distributed under the terms of the GNU General Public License v3 (GPL
// Version 3), copied verbatim in the file "COPYING".
//
// See https://alice-o2.web.cern.ch/ for full licensing information.
//
// In applying this license CERN does not waive the privileges and immunities
// granted to it by virtue of its status as an Intergovernmental Organization
// or submit itself to any jurisdiction.
EOF
)"
COPYRIGHT_LINES=$(echo "$COPYRIGHT" | wc -l)
set +x
while read FILE; do
  [[ "$(head -n$COPYRIGHT_LINES "$FILE")" == "$COPYRIGHT" ]] || { printf "$FILE:1:1: error: missing or malformed copyright notice\n" >> error-log.txt; }
done < <(find "$O2_SRC" -name '*.cxx' -o -name '*.h')

# Tell user what to do in case of copyright notice error
if grep -q "malformed copyright notice" error-log.txt; then
  printf "\nerror: Some files are missing the correct copyright notice on top.\n"
  printf "error: Make sure all your source files begin with the following exact lines:\nerror:\n"
  while read LINE; do printf "error: $LINE\n"; done < <(echo "$COPYRIGHT")
  printf "error:\nerror: List of non-compliant files will follow.\n\n"
fi

# Filter the actual errors from the log (ignore autogenerated stuff from
# protocol buffers for the moment). Break with nonzero if errors are found
! ( grep -v "/G__" error-log.txt | grep -v ".pb.cc" | grep " error:" )
