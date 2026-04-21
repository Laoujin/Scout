FROM node:22-bookworm-slim

ARG RUNNER_VERSION=2.321.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates openssh-client libicu72 util-linux gnupg \
      libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libxkbcommon0 \
      libxcomposite1 libxdamage1 libxrandr2 libxfixes3 \
      libgbm1 libasound2 libpango-1.0-0 libcairo2 libgtk-3-0 \
      fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI — used by scripts/issue-comment.sh, publish.sh and the workflow steps
# to comment/close issues and parse issue bodies. Auth comes from GH_TOKEN env at
# runtime (provided by the workflow's GITHUB_TOKEN); no `gh auth login` needed.
RUN install -dm 0755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Rename default node user (UID 1000) to runner
RUN usermod -l runner -d /home/runner -m node && \
    groupmod -n runner node

# Global npm installs as root
RUN npm install -g @anthropic-ai/claude-code playwright

# Switch to runner for per-user installs (playwright chromium + runner binary)
USER runner
WORKDIR /home/runner

RUN npx playwright install chromium

# Install GH Actions runner to a base path; entrypoint copies into the volume
RUN mkdir -p /home/runner/runner-base && cd /home/runner/runner-base && \
    curl -fsSL -o runner.tar.gz \
      https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf runner.tar.gz && rm runner.tar.gz

# Entrypoint runs as root to chown volume mounts, then drops to runner
USER root
COPY entrypoint.sh run-init.sh /home/runner/
RUN chmod +x /home/runner/entrypoint.sh /home/runner/run-init.sh && \
    chown runner:runner /home/runner/entrypoint.sh /home/runner/run-init.sh

ENTRYPOINT ["/home/runner/entrypoint.sh"]
