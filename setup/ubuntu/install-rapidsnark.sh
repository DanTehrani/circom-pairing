git clone https://github.com/iden3/rapidsnark.git
cd rapidsnark

npm install
git submodule init
git submodule update
npx task createFieldSources
npx task buildProver

export PATH=/home/ubuntu/rapidsnark/build:$PATH
alias rapidsnark=prover