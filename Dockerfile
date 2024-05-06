FROM alpine:3.19.1 AS base

RUN apk add --no-cache \
        ca-certificates \
        curl \
        wget \
        dumb-init \
        qt6-qtbase \
        qt6-qtsvg \
        qt6-qttools \
        qt6-qtbase-sqlite 

FROM base as builder

# Compiling qBitTorrent following instructions on
# https://github.com/qbittorrent/qBittorrent/wiki/Compilation:-Alpine-Linux

ARG BASE_DIR=/qbittorrent

RUN set -x \
    # Install build dependencies
 && apk add --no-cache \
        autoconf \
        automake \
        build-base \
        cmake \
        git \
        linux-headers \
        perl \
        pkgconf \
        python3-dev \
        re2c \
        tar \
        icu-dev \
        elfutils-dev \
        openssl-dev \
        zlib-dev \
        qt6-qtbase-dev \
        qt6-qttools-dev \
        qt6-qtsvg-dev 

RUN git clone --shallow-submodules --recurse-submodules https://github.com/ninja-build/ninja.git ${BASE_DIR}/ninja \
 && cd ${BASE_DIR}/ninja \
 && git checkout "$(git tag -l --sort=-v:refname "v*" | head -n 1)" \
 && cmake -Wno-dev -B build \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
 && cmake --build build \
 && cmake --install build

    # Boost build file.
RUN wget --no-check-certificate https://altushost-swe.dl.sourceforge.net/project/boost/boost/1.81.0/boost_1_81_0.tar.gz -O "${BASE_DIR}/boost-1.81.0.tar.gz" \
 && tar xf "${BASE_DIR}/boost-1.81.0.tar.gz" -C ${BASE_DIR}
 
    # Libtorrent
RUN git clone --shallow-submodules --recurse-submodules https://github.com/arvidn/libtorrent.git ${BASE_DIR}/libtorrent \
 && cd ${BASE_DIR}/libtorrent \
 && git checkout "$(git tag -l --sort=-v:refname "v2*" | head -n 1)" \
 && cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="Release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D BOOST_INCLUDEDIR="${BASE_DIR}/boost_1_81_0/" \
 && cmake --build build \
 && cmake --install build

RUN git clone --shallow-submodules --recurse-submodules https://github.com/qbittorrent/qBittorrent.git ${BASE_DIR}/source 

WORKDIR ${BASE_DIR}/build

RUN cmake ./../source \
      -Wno-dev -G Ninja -B . \
      -D CMAKE_BUILD_TYPE="Release" \
      -D GUI=off \
      -D CMAKE_CXX_STANDARD=17 \
      -D BOOST_INCLUDEDIR="${BASE_DIR}/boost_1_81_0/" \
      -D CMAKE_INSTALL_PREFIX="/usr/local" \
  && cmake --build .

FROM base AS runner

ARG BASE_DIR=/qbittorrent

COPY --from=builder ${BASE_DIR}/build/qbittorrent-nox /usr/local/bin
COPY --from=builder /usr/local/lib/libtorrent* /usr/local/lib/

RUN set -x \
    # Add non-root user
 && adduser -S -D -u 520 -g 520 -s /sbin/nologin qbittorrent \
    # Create symbolic links to simplify mounting
 && mkdir -p /home/qbittorrent/.config/qBittorrent \
 && mkdir -p /home/qbittorrent/.local/share/qBittorrent \
 && mkdir /downloads \
 && chmod go+rw -R /home/qbittorrent /downloads \
 && ln -s /home/qbittorrent/.config/qBittorrent /config \
 && ln -s /home/qbittorrent/.local/share/qBittorrent /torrents \
    # Check it works
 && su qbittorrent -s /bin/sh -c 'qbittorrent-nox -v'

# Default configuration file.
COPY qBittorrent.conf /default/qBittorrent.conf

COPY entrypoint.sh /

VOLUME ["/config", "/torrents", "/downloads"]

ENV HOME=/home/qbittorrent

USER qbittorrent

EXPOSE 8080 6881

ENTRYPOINT ["dumb-init", "/entrypoint.sh"]
CMD ["qbittorrent-nox"]

HEALTHCHECK --interval=5s --timeout=2s --retries=20 CMD curl --connect-timeout 15 --silent --show-error --fail http://localhost:8080/ >/dev/null || exit 1