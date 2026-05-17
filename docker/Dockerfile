FROM --platform=linux/amd64 cachyos/cachyos

# System update + base tools (no zig needed — binary is pre-built on host)
RUN pacman -Syu --noconfirm \
 && pacman -S --noconfirm sudo git curl base-devel \
 && pacman -Scc --noconfirm

# Non-root user with passwordless sudo (mirrors a real install)
RUN useradd -m -s /bin/bash jllopis \
 && echo "jllopis:jllopis" | chpasswd \
 && echo "jllopis ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jllopis \
 && chmod 0440 /etc/sudoers.d/jllopis

# Install yay as the non-root user
RUN su - jllopis -c "\
  git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin \
  && cd /tmp/yay-bin \
  && makepkg -si --noconfirm \
  && rm -rf /tmp/yay-bin"

# Copy pre-built static desperta binary
# Build on host first: zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
# Build context must be repo root: docker build -f docker/Dockerfile .
COPY --chown=jllopis:jllopis zig-out/bin/desperta /home/jllopis/.local/bin/desperta
RUN chmod +x /home/jllopis/.local/bin/desperta

USER jllopis
WORKDIR /home/jllopis

ENV PATH="/home/jllopis/.local/bin:$PATH"

CMD ["/bin/bash"]
