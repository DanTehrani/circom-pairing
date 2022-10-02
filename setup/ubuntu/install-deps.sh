sudo apt update -y
sudo apt install build-essential -y

curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh -y
source $HOME/.cargo/env
git clone https://github.com/iden3/circom.git
cd circom
cargo build --release
cargo install --path circom

sudo apt install build-essential libgmp-dev libsodium-dev nasm nlohmann-json3-dev -y

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

nvm install --lts
npm install --global yarn