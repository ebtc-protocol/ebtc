## This Dockerfile is here to help you make Echidna work if you have issues with the installation of it or slither

## Built with
## docker build -t my/fuzzy:latest .

## Run image with
## docker run -it --rm -v $PWD:/code my/fuzzy

## Run ECHIDNA with (if you have already ran tests and compilation)
## cd code && solc-select use 0.8.17 && cd packages/contracts/ && yarn echidna --test-mode assertion --test-limit 100000

## Run MEDUSA with (if you have already ran tests and compilation)
## cd code && solc-select use 0.8.17 && cd packages/contracts/ && medusa fuzz

## If you've never built the repo
## Run ECHIDNA with
## yarn && git submodule init && git submodule update && solc-select use 0.8.17 && cd packages/contracts/ && yarn echidna --test-mode assertion --test-limit 100000

FROM ubuntu:20.04

RUN set -eux

RUN echo "[$(date)] Start setup"

## NEEDED else it get's stuck at some timezone question screen
ENV DEBIAN_FRONTEND=noninteractive 

RUN export WORKDIR=/home/ubuntu

RUN echo "[$(date)] Go to working directory"
RUN cd $WORKDIR

RUN echo "[$(date)] Install OS libraries"
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y curl git gcc make python3-pip unzip jq wget tar

## Install Node via nvm to avoid bs
ENV NODE_VERSION=16.13.0
RUN apt install -y curl
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
ENV NVM_DIR=/root/.nvm
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
RUN node --version
RUN npm --version

## Install yarn
RUN echo "[$(date)] Install yarn"
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt update && apt install -y yarn

RUN echo "[$(date)] Install solc-select"
RUN pip3 install solc-select

RUN echo "[$(date)] Install latest solidity versions"
RUN solc-select install 0.8.17
## NOTE: You could use something else here, just don't want to install a ton of compilers for no reason

RUN echo "[$(date)] Install slither"
RUN pip3 install slither-analyzer


RUN echo "[$(date)] Install echidna"
RUN wget https://github.com/crytic/echidna/releases/download/v2.2.1/echidna-2.2.1-Linux.zip -O echidna.zip
RUN unzip echidna.zip
RUN tar -xvkf echidna.tar.gz
RUN mv echidna /usr/bin/
RUN rm echidna.zip echidna.tar.gz


RUN echo "[$(date)] Install foundry"
RUN curl -L https://foundry.paradigm.xyz | bash

## TEMP: Reload env?
RUN export PATH="$PATH:$HOME/.foundry/bin"
ENV PATH="$PATH:$HOME/.foundry/bin" 

## Pretty weird but works to run foundry without resetting path
RUN PATH="$PATH:$HOME/.foundry/bin" foundryup 

RUN echo "[$(date)] Finish setup"

## GO
## NOTE: For some reason we need to re-get else sometimes glibc throws error
RUN apt-get update
RUN apt install -y glibc-source
RUN wget https://go.dev/dl/go1.21.1.linux-arm64.tar.gz && tar -C /usr/local -xzf go1.21.1.linux-arm64.tar.gz
RUN export PATH="$PATH:/usr/local/go/bin"
ENV PATH="$PATH:/usr/local/go/bin"

RUN git config --global user.email "you@example.com"
RUN git config --global user.name "Your Name"

RUN echo "Downloading and building Medusa..."
RUN git clone https://github.com/crytic/medusa
RUN cd medusa && git checkout ac99e78ee38df86a8afefb21f105be9e4eae46ee && git pull origin dev/merge-assertion-and-property-mode && git pull origin dev/no-multi-abi

## WARNING!!!!
## Comment this line on Silicon, the line below is for Intel!
RUN cd medusa && GOOS=linux GOARCH=amd64 go build

RUN cd medusa && mv medusa /usr/local/bin/ 

RUN chmod +x /usr/local/bin/medusa

RUN export PATH="$PATH:/usr/local/bin/medusa"