## This Dockerfile is here to help you make Echidna work if you have issues with the installation of it or slither

## Built with docker build -t my/fuzzy:latest .
## Run with (if you have already ran tests and compilation)
## cd code && solc-select use 0.8.17 && cd packages/contracts/ && yarn echidna --test-mode assertion --test-limit 100000

## If you've never built the repo
## Run with
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
RUN wget https://github.com/crytic/echidna/releases/download/v2.2.0/echidna-2.2.0-Ubuntu-22.04.tar.gz -O echidna.tar.gz
RUN tar -xvkf echidna.tar.gz
RUN mv echidna /usr/bin/
RUN rm echidna.tar.gz


RUN echo "[$(date)] Install foundry"
RUN curl -L https://foundry.paradigm.xyz | bash

## TEMP: Reload env?
RUN export PATH="$PATH:$HOME/.foundry/bin"
ENV PATH="$PATH:$HOME/.foundry/bin" 

## Pretty weird but works to run foundry without resetting path
RUN PATH="$PATH:$HOME/.foundry/bin" foundryup 

RUN echo "[$(date)] Finish setup"