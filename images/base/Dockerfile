FROM debian:bookworm

ARG TZ
ENV TZ="$TZ"

# Install basic development tools
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  less \
  git \
  file \
  procps \
  gosu \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  strace \
  lsof \
  ripgrep \
  iputils-ping \
  iputils-tracepath \
  gzip \
  cmake \
  pkg-config \
  gdb \
  valgrind \
  shellcheck \
  iproute2 \
  dnsutils \
  jq \
  python3 \
  neovim \
  curl \
  wget \
  tmux \
  ca-certificates \
  build-essential \
  locales \
  && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
  && locale-gen \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Set up non-root user
ARG USERNAME=dev
RUN groupadd --system --gid 500 ${USERNAME} && useradd --system --create-home --uid 500 --gid 500 ${USERNAME}

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R ${USERNAME} /commandhistory

# Set environment variables
ENV DEVCONTAINER=true

# Create workspace and config directories
RUN mkdir -p /workspace && chown -R ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

# Install git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER ${USERNAME}

# Set default shell and editor
ENV SHELL=/bin/zsh
ENV EDITOR=nvim
ENV VISUAL=nvim

# mise specific https://mise.jdx.dev/directories.html#config-mise
ENV MISE_CONFIG_DIR=/home/dev/.mise/config
ENV MISE_CACHE_DIR=/home/dev/.mise/cache
ENV MISE_STATE_DIR=/home/dev/.mise/state
ENV MISE_DATA_DIR=/home/dev/.mise/data

# Install zsh with powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -p https://github.com/zsh-users/zsh-autosuggestions \
  -p https://github.com/zsh-users/zsh-syntax-highlighting \
  -p https://github.com/zsh-users/zsh-completions \
  -p history-substring-search \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "bindkey '^[[A' history-substring-search-up" \
  -a "bindkey '^[[B' history-substring-search-down" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# gitstatus and oh-my-zsh need a writable cache dir
RUN mkdir -p /home/dev/.cache && chown dev:dev /home/dev/.cache

USER root

# Copy and set up entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy and set up dev-shell handle, i.e. `docker compose exec agent-sandbox dev-shell`
RUN ln -s /usr/local/bin/entrypoint.sh /usr/local/bin/dev-shell

# Entrypoint runs as root to adjust uid/gid, then drops to dev user
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh"]
