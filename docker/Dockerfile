FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Core system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    openssh-client \
    ca-certificates \
    build-essential \
    sudo \
    less \
    vim \
    jq \
    zsh \
    locales \
    gnupg \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8 || true

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Create dev user matching host UID/GID (parameterized at build time)
ARG DEV_USER=dev
ARG DEV_UID=501
ARG DEV_GID=20
RUN groupadd -g ${DEV_GID} devgroup 2>/dev/null || true \
    && useradd -m -u ${DEV_UID} -g ${DEV_GID} -s /bin/zsh ${DEV_USER} \
    && echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${DEV_USER}
WORKDIR /workspace

# Keep container alive; all work happens via docker exec
ENTRYPOINT ["sleep", "infinity"]
