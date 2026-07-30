# Builds the sample game against Ubuntu 22.04 — the SAME OS as the Amazon
# GameLift Streams "Ubuntu 22.04 LTS" runtime environment. Building on a
# matching base guarantees the shared libraries we bundle are ABI-compatible
# with the streaming host.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libsdl2-dev \
        libsdl2-2.0-0 \
        patchelf \
        file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY breakout.c /build/breakout.c
COPY package_build.sh /build/package_build.sh
RUN chmod +x /build/package_build.sh && /build/package_build.sh

# The finished, ready-to-upload folder is left in /build/dist
CMD ["true"]
