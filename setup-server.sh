#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Config paths
BASHRC="$HOME/.bashrc"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# ============================================
# Phase Detection
# ============================================
if [ "$(id -u)" -eq 0 ]; then
    # ==========================================
    # PHASE 1: ROOT SETUP (Security & User)
    # ==========================================
    log_info "Running Phase 1: System security and user setup..."
    echo ""

    # ============================================
    # System Updates
    # ============================================
    log_info "Updating package lists..."
    sudo apt update

    log_info "Upgrading packages..."
    sudo apt upgrade -y

    # ============================================
    # Configure UFW Firewall
    # ============================================
    if sudo ufw status | grep -q "Status: active"; then
        log_skip "UFW firewall is already active"
    else
        log_info "Installing and configuring UFW firewall..."
        sudo apt install -y ufw
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw allow 60000:61000/udp comment 'mosh'
        sudo ufw --force enable
    fi

    # ============================================
    # Install Fail2ban
    # ============================================
    if command -v fail2ban-server &> /dev/null; then
        log_skip "fail2ban is already installed"
    else
        log_info "Installing fail2ban..."
        sudo apt install -y fail2ban
        sudo systemctl enable fail2ban
        sudo systemctl start fail2ban
    fi

    # ============================================
    # Create non-root user
    # ============================================
    USERNAME="kuranai"

    if id "$USERNAME" &>/dev/null; then
        log_skip "User $USERNAME already exists"
    else
        log_info "Creating user $USERNAME..."
        sudo adduser --disabled-password --gecos "" "$USERNAME"
        sudo usermod -aG sudo "$USERNAME"

        # Enable passwordless sudo for convenience
        echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USERNAME > /dev/null

        # Copy SSH keys from root
        if [ -f "$HOME/.ssh/authorized_keys" ]; then
            sudo mkdir -p /home/$USERNAME/.ssh
            sudo cp "$HOME/.ssh/authorized_keys" /home/$USERNAME/.ssh/
            sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
            sudo chmod 700 /home/$USERNAME/.ssh
            sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
            log_info "SSH keys copied to $USERNAME"
        else
            log_info "Warning: No SSH keys found to copy. Add keys to /home/$USERNAME/.ssh/authorized_keys"
        fi
    fi

    # ============================================
    # Harden SSH Configuration
    # ============================================
    SSH_HARDENING="/etc/ssh/sshd_config.d/hardening.conf"

    if [ -f "$SSH_HARDENING" ]; then
        log_skip "SSH hardening already configured"
    else
        # Safety check: ensure SSH keys exist before disabling password auth
        if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
            log_info "Hardening SSH configuration..."
            sudo tee "$SSH_HARDENING" > /dev/null << 'EOF'
# Disable password authentication
PasswordAuthentication no
ChallengeResponseAuthentication no

# Disable root login entirely (use kuranai instead)
PermitRootLogin no

# Other hardening
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
            sudo systemctl reload ssh
            log_info "SSH hardened. Use 'ssh kuranai@<ip>' for future connections."
        else
            log_info "WARNING: No SSH keys found. Skipping SSH hardening to prevent lockout."
            log_info "Add your public key to ~/.ssh/authorized_keys and re-run this script."
        fi
    fi

    # ============================================
    # Configure Automatic Security Updates
    # ============================================
    if dpkg -l | grep -q unattended-upgrades; then
        log_skip "unattended-upgrades already installed"
    else
        log_info "Configuring automatic security updates..."
        sudo apt install -y unattended-upgrades
        sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    fi

    # ============================================
    # Install mosh
    # ============================================
    if command -v mosh &> /dev/null; then
        log_skip "mosh is already installed"
    else
        log_info "Installing mosh..."
        sudo apt install -y mosh
    fi

    # ============================================
    # Install tmux
    # ============================================
    if command -v tmux &> /dev/null; then
        log_skip "tmux is already installed"
    else
        log_info "Installing tmux..."
        sudo apt install -y tmux
    fi

    # ============================================
    # Copy setup script to kuranai's home
    # ============================================
    SCRIPT_PATH="$(readlink -f "$0")"
    DEST_PATH="/home/$USERNAME/setup-server.sh"

    if [ -f "$DEST_PATH" ]; then
        log_skip "Setup script already copied to $USERNAME's home"
    else
        log_info "Copying setup script to $USERNAME's home directory..."
        cp "$SCRIPT_PATH" "$DEST_PATH"
        chown $USERNAME:$USERNAME "$DEST_PATH"
        chmod +x "$DEST_PATH"
    fi

    # ============================================
    # Phase 1 Summary
    # ============================================
    echo ""
    log_info "============================================"
    log_info "Phase 1 complete (root setup)"
    log_info "============================================"
    echo ""
    echo "System security configured:"
    echo "  - UFW firewall (SSH + mosh allowed)"
    echo "  - fail2ban (brute-force protection)"
    echo "  - Automatic security updates"
    echo "  - User 'kuranai' created with sudo access"
    echo "  - SSH hardened (root login disabled)"
    echo "  - mosh and tmux installed"
    echo ""
    echo -e "${YELLOW}NEXT STEP:${NC}"
    echo "  1. Disconnect from this session"
    echo "  2. Reconnect as: ssh kuranai@<server-ip>"
    echo "  3. Run this script again: ~/setup-server.sh"
    echo ""
    exit 0

else
    # ==========================================
    # PHASE 2: DEV ENVIRONMENT (as kuranai)
    # ==========================================
    log_info "Running Phase 2: Developer environment setup..."
    echo ""

    # Git configuration
    GIT_USERNAME="kuranai"
    GIT_EMAIL="mail@kuranai.de"

    # ============================================
    # Install Claude CLI
    # ============================================
    if command -v claude &> /dev/null; then
        log_skip "Claude CLI is already installed"
    else
        log_info "Installing Claude CLI..."
        curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
        bash /tmp/claude-install.sh
        rm -f /tmp/claude-install.sh
    fi

    # ============================================
    # Install mise (for managing programming languages)
    # ============================================
    if command -v mise &> /dev/null; then
        log_skip "mise is already installed"
    else
        log_info "Installing mise..."
        curl -fsSL https://mise.run -o /tmp/mise-install.sh
        bash /tmp/mise-install.sh
        rm -f /tmp/mise-install.sh
    fi

    # ============================================
    # Install PHP build dependencies
    # ============================================
    log_info "Installing PHP build dependencies..."
    sudo apt install -y autoconf bison build-essential curl gettext git \
        libgd-dev libcurl4-openssl-dev libedit-dev libicu-dev libjpeg-dev \
        libmysqlclient-dev libonig-dev libpng-dev libpq-dev libreadline-dev \
        libsqlite3-dev libssl-dev libxml2-dev libxslt-dev libzip-dev openssl \
        pkg-config re2c zlib1g-dev

    # ============================================
    # Install Ruby build dependencies
    # ============================================
    log_info "Installing Ruby build dependencies..."
    sudo apt install -y rustc libyaml-dev libgmp-dev

    # ============================================
    # Install Programming Languages via mise
    # ============================================
    export PATH="$HOME/.local/bin:$PATH"

    if command -v mise &> /dev/null; then
        log_info "Installing Node.js via mise..."
        mise use --global node@lts

        log_info "Installing PHP via mise..."
        mise use --global php@latest

        log_info "Installing Ruby via mise..."
        mise use --global ruby@latest
    else
        log_info "WARNING: mise not found, skipping language installations"
    fi

    # ============================================
    # Configure Git
    # ============================================
    if git config --global user.name &>/dev/null; then
        log_skip "Git user.name already configured"
    else
        log_info "Configuring git user.name..."
        git config --global user.name "$GIT_USERNAME"
    fi

    if git config --global user.email &>/dev/null; then
        log_skip "Git user.email already configured"
    else
        log_info "Configuring git user.email..."
        git config --global user.email "$GIT_EMAIL"
    fi

    # ============================================
    # Create code directory
    # ============================================
    CODE_DIR="$HOME/code"

    if [ -d "$CODE_DIR" ]; then
        log_skip "Code directory already exists"
    else
        log_info "Creating code directory..."
        mkdir -p "$CODE_DIR"
    fi

    # ============================================
    # Configure weekly mise upgrades via cron
    # ============================================
    MISE_CRON="/etc/cron.weekly/mise-upgrade"

    if [ -f "$MISE_CRON" ]; then
        log_skip "mise weekly upgrade cron job already configured"
    else
        log_info "Configuring weekly mise upgrades..."
        sudo tee "$MISE_CRON" > /dev/null << 'EOF'
#!/bin/bash
# Weekly mise upgrade for all users with mise installed

for user_home in /root /home/*; do
    if [ -x "$user_home/.local/bin/mise" ]; then
        user=$(basename "$user_home")
        [ "$user_home" = "/root" ] && user="root"

        su - "$user" -c 'export PATH="$HOME/.local/bin:$PATH" && mise upgrade --yes' \
            >> /var/log/mise-upgrade.log 2>&1
    fi
done
EOF
        sudo chmod +x "$MISE_CRON"
    fi

    # ============================================
    # Install Neovim dependencies (for LazyVim)
    # ============================================
    log_info "Installing Neovim/LazyVim dependencies..."
    sudo apt install -y git build-essential ripgrep fd-find unzip

    # ============================================
    # Install latest Neovim from GitHub releases
    # ============================================
    NVIM_INSTALL_DIR="/opt/nvim-linux-x86_64"

    if [ -d "$NVIM_INSTALL_DIR" ]; then
        log_skip "Neovim is already installed in /opt"
    else
        log_info "Installing latest Neovim from GitHub releases..."
        curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
        sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
        rm nvim-linux-x86_64.tar.gz
        log_info "Neovim installed successfully"
    fi

    # Add Neovim to PATH in .bashrc
    if grep -q '/opt/nvim-linux-x86_64/bin' "$BASHRC" 2>/dev/null; then
        log_skip "Neovim PATH already configured in .bashrc"
    else
        log_info "Adding Neovim to PATH in .bashrc..."
        echo 'export PATH="/opt/nvim-linux-x86_64/bin:$PATH"' >> "$BASHRC"
    fi

    # ============================================
    # Install LazyVim
    # ============================================
    NVIM_CONFIG="$HOME/.config/nvim"

    if [ -d "$NVIM_CONFIG" ] && [ -f "$NVIM_CONFIG/lua/config/lazy.lua" ]; then
        log_skip "LazyVim is already installed"
    else
        log_info "Installing LazyVim..."

        # Backup existing Neovim config if it exists
        if [ -d "$NVIM_CONFIG" ]; then
            log_info "Backing up existing Neovim config..."
            mv "$NVIM_CONFIG" "$NVIM_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
        fi

        # Backup existing Neovim data/state/cache
        [ -d "$HOME/.local/share/nvim" ] && mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.backup.$(date +%Y%m%d%H%M%S)"
        [ -d "$HOME/.local/state/nvim" ] && mv "$HOME/.local/state/nvim" "$HOME/.local/state/nvim.backup.$(date +%Y%m%d%H%M%S)"
        [ -d "$HOME/.cache/nvim" ] && mv "$HOME/.cache/nvim" "$HOME/.cache/nvim.backup.$(date +%Y%m%d%H%M%S)"

        # Clone LazyVim starter
        git clone https://github.com/LazyVim/starter "$NVIM_CONFIG"

        # Remove .git so user can add their own version control
        rm -rf "$NVIM_CONFIG/.git"

        log_info "LazyVim installed. Run 'nvim' to complete plugin installation."
    fi

    # ============================================
    # Configure PATH in .bashrc
    # ============================================

    # Add ~/.local/bin to PATH (for Claude CLI and other local binaries)
    if grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" 2>/dev/null; then
        log_skip "~/.local/bin PATH already configured in .bashrc"
    else
        log_info "Adding ~/.local/bin to PATH in .bashrc..."
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
    fi

    # Add mise activation to .bashrc
    if grep -q 'mise activate bash' "$BASHRC" 2>/dev/null; then
        log_skip "mise activation already configured in .bashrc"
    else
        log_info "Adding mise activation to .bashrc..."
        echo 'eval "$(~/.local/bin/mise activate bash)"' >> "$BASHRC"
    fi

    # ============================================
    # Set default directory to ~/code
    # ============================================
    if grep -q 'cd ~/code' "$BASHRC" 2>/dev/null; then
        log_skip "Default code directory already configured in .bashrc"
    else
        log_info "Setting ~/code as default directory..."
        echo '# Change to code directory on new terminal' >> "$BASHRC"
        echo 'cd ~/code 2>/dev/null || true' >> "$BASHRC"
    fi

    # ============================================
    # Configure automatic tmux session on login
    # ============================================
    TMUX_AUTO_ATTACH='
# Auto-attach to tmux session on login
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ]; then
    tmux attach-session -t main 2>/dev/null || tmux new-session -s main
fi'

    if grep -q 'tmux attach-session -t main' "$BASHRC" 2>/dev/null; then
        log_skip "tmux auto-attach already configured in .bashrc"
    else
        log_info "Configuring tmux auto-attach on login..."
        echo "$TMUX_AUTO_ATTACH" >> "$BASHRC"
    fi

    # ============================================
    # Create basic tmux configuration (optional but nice)
    # ============================================
    TMUX_CONF="$HOME/.tmux.conf"
    if [ -f "$TMUX_CONF" ]; then
        log_skip "tmux configuration already exists"
    else
        log_info "Creating basic tmux configuration..."
        cat > "$TMUX_CONF" << 'EOF'
# Enable mouse support
set -g mouse on

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Increase history limit
set -g history-limit 50000

# Renumber windows when one is closed
set -g renumber-windows on

# Reduce escape time for better vim experience
set -sg escape-time 10

# Enable 256 colors
set -g default-terminal "screen-256color"

# Enable extended keys (for Shift+Enter, etc.)
set -s extended-keys on
set -as terminal-features 'xterm*:extkeys'
EOF
    fi

    # ============================================
    # Phase 2 Summary
    # ============================================
    echo ""
    log_info "============================================"
    log_info "Phase 2 complete (dev environment)"
    log_info "============================================"
    echo ""
    echo "Developer environment configured:"
    echo "  - Claude CLI"
    echo "  - mise (for managing programming languages)"
    echo "  - Node.js, PHP, Ruby (via mise, auto-updated weekly)"
    echo "  - Git configured ($GIT_USERNAME / $GIT_EMAIL)"
    echo "  - ~/code directory created (default on new terminal)"
    echo "  - Neovim (latest from GitHub releases)"
    echo "  - LazyVim (Neovim distribution)"
    echo "  - tmux (with auto-attach to 'main' session)"
    echo ""
    echo "To apply changes to current shell, run:"
    echo "  source ~/.bashrc"
    echo ""
    echo "Next SSH/mosh connection will auto-attach to tmux."
    echo ""
    echo "Run 'nvim' to complete LazyVim plugin installation."
    echo ""
    echo "Mise upgrade logs: /var/log/mise-upgrade.log"
    echo ""
fi
