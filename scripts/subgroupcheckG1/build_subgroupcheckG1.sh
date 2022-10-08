#!/bin/bash

PHASE1=../../circuits/pot20_final.ptau
CIRCUIT_NAME=subgroupcheckG1
BUILD_DIR=../../build/"$CIRCUIT_NAME"

if [ -f "$PHASE1" ]; then
    echo "Found Phase 1 ptau file"
else
    echo "No Phase 1 ptau file found. Exiting..."
    exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir "$BUILD_DIR"
fi

echo $PWD

echo "****COMPILING CIRCUIT****"
start=`date +%s`
#circom "$CIRCUIT_NAME".circom --O1 --r1cs --wasm --sym --c --wat --output "$BUILD_DIR"
circom "$CIRCUIT_NAME".circom --O1 --r1cs --wasm --sym --output "$BUILD_DIR"
end=`date +%s`
echo "DONE ($((end-start))s)"

echo "****GENERATING WITNESS FOR SAMPLE INPUT****"
start=`date +%s`
node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm input_"$CIRCUIT_NAME".json "$BUILD_DIR"/witness.wtns
end=`date +%s`
echo "DONE ($((end-start))s)"
snarkjs wej "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/witness.json

echo "****GENERATING ZKEY 0****"
start=`date +%s`
~/node/out/Release/node --trace-gc --trace-gc-ignore-scavenger --max-old-space-size=2048000 --initial-old-space-size=2048000 --no-global-gc-scheduling --no-incremental-marking --max-semi-space-size=1024 --initial-heap-size=2048000 --expose-gc ~/snarkjs/cli.js zkey new subgroupcheckG1.r1cs ../../circuits/pot25_final.ptau subgroupcheckG1_0.zkey -v > zkey0.out
end=`date +%s`
echo "DONE ($((end-start))s)"

echo "****CONTRIBUTE TO PHASE 2 CEREMONY****"
start=`date +%s`
~/node/out/Release/node ~/snarkjs/cli.js zkey contribute -verbose subgroupcheckG1_0.zkey subgroupcheckG1.zkey -n="First phase2 contribution" -e="some random text 5555" > contribute.out
end=`date +%s`
echo "DONE ($((end-start))s)"

echo "****EXPORTING VKEY****"
start=`date +%s`
~/node/out/Release/node ~/snarkjs/cli.js zkey export verificationkey subgroupcheckG1.zkey vkey.json -v
end=`date +%s`
echo "DONE ($((end-start))s)"

echo "****GENERATING PROOF FOR SAMPLE INPUT****"
start=`date +%s`
~/rapidsnark/build/prover subgroupcheckG1.zkey witness.wtns proof.json public.json > proof.out
#~/node/out/Release/node ~/snarkjs/cli.js subgroupcheckG1.zkey witness.wtns proof.json public.json > proof.out
end=`date +%s`
echo "DONE ($((end-start))s)"