FROM alpine:3.19.1

# Install required packages
RUN apk add --no-cache \
        boost \
        ca-certificates \
        curl \
        wget \
        dumb-init \
        icu \
        elfutils-dev \
        elfutils \
        libtool \
        openssl \
        python3 \
        qt6-qtbase \
        qt6-qtsvg \
        qt6-qttools \
        re2c \
        zlib

# Compiling qBitTorrent following instructions on
# https://github.com/qbittorrent/qBittorrent/wiki/Compilation:-Alpine-Linux

RUN set -x \
    # Install build dependencies
 && apk add --no-cache -t .build-deps \
        autoconf \
        automake \
        boost-dev \
        build-base \
        cmake \
        git \
        libtool \
        linux-headers \
        perl \
        pkgconf \
        python3 \
        python3-dev \
        re2c \
        tar \
        icu-dev \
        elfutils-dev \
        elfutils \
        openssl-dev \
        qt6-qtbase-dev \
        qt6-qttools-dev \
        zlib-dev \
        qt6-qtsvg-dev \
  && ln -s /usr/lib/libexecinfo.so.1 /usr/lib/libexecinfo.so

RUN git clone --shallow-submodules --recurse-submodules https://github.com/ninja-build/ninja.git /tmp/ninja \
 && cd /tmp/ninja \
 && git checkout "$(git tag -l --sort=-v:refname "v*" | head -n 1)" \
 && cmake -Wno-dev -B build \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
 && cmake --build build \
 && cmake --install build
    # Boost build file.
RUN wget --no-check-certificate https://altushost-swe.dl.sourceforge.net/project/boost/boost/1.81.0/boost_1_81_0.tar.gz -O "/tmp/boost-1.81.0.tar.gz" \
 && tar xf "/tmp/boost-1.81.0.tar.gz" -C /tmp
    # Libtorrent
RUN git clone --shallow-submodules --recurse-submodules https://github.com/arvidn/libtorrent.git /tmp/libtorrent \
 && cd /tmp/libtorrent \
 && git checkout "$(git tag -l --sort=-v:refname "v2*" | head -n 1)" \
 && cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="Release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D BOOST_INCLUDEDIR="$HOME/boost_1_81_0/" \
        -D CMAKE_INSTALL_LIBDIR="lib" \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
 && cmake --build build \
 && cmake --install build
    # Build qBittorrent
RUN git clone --shallow-submodules --recurse-submodules https://github.com/qbittorrent/qBittorrent.git /tmp/qbittorrent \
 && cd /tmp/qbittorrent \
 && git checkout "$(git tag -l --sort=-v:refname | head -n 1)" \
 && cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="release" \
        -D GUI=off \
        -D CMAKE_CXX_STANDARD=17 \
        -D BOOST_INCLUDEDIR="$HOME/boost_1_81_0/" \
        -D CMAKE_CXX_STANDARD_LIBRARIES="/usr/lib/libexecinfo.so" \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
 && cmake --build build \
 && cmake --install build \
    # Clean-up
 && cd / \
 && apk del --purge .build-deps \
 && rm -rf /tmp/*

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