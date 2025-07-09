#!/bin/bash

# Script tự động cài đặt tmux, Nexus CLI và chạy nexus-network trong các cửa sổ tmux riêng biệt trên Ubuntu
# Yêu cầu: Ubuntu, quyền root, kết nối mạng
# Sử dụng: sudo ./ok.sh [stop|restart]
# Log: /var/log/nexus_setup.log

# Màu sắc cho thông báo
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Tệp log
LOG_FILE="/var/log/nexus_setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec 1>>"$LOG_FILE" 2>&1
echo "[$(date)] Bắt đầu thực thi script..." | tee /dev/tty

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Vui lòng chạy script này với quyền root (sudo)!${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Kiểm tra hệ điều hành
if ! command -v apt &> /dev/null; then
    echo -e "${RED}Hệ thống không hỗ trợ apt. Vui lòng chạy trên Ubuntu/Debian.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Kiểm tra dung lượng đĩa
MIN_DISK_SPACE=1024 # MB
AVAILABLE_SPACE=$(df -m / | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt "$MIN_DISK_SPACE" ]; then
    echo -e "${RED}Dung lượng đĩa trống ($AVAILABLE_SPACE MB) không đủ. Cần ít nhất $MIN_DISK_SPACE MB.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Xử lý lệnh stop/restart
SESSION_NAME="nexus_nodes"
case "$1" in
    stop)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux kill-session -t "$SESSION_NAME"
            echo -e "${GREEN}Đã dừng phiên tmux $SESSION_NAME.${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}Không tìm thấy phiên tmux $SESSION_NAME.${NC}" | tee -a "$LOG_FILE"
        fi
        exit 0
        ;;
    restart)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux kill-session -t "$SESSION_NAME"
            echo -e "${GREEN}Đã xóa phiên tmux $SESSION_NAME để khởi động lại.${NC}" | tee -a "$LOG_FILE"
        fi
        ;;
esac

# Cập nhật hệ thống
echo -e "${GREEN}Đang cập nhật danh sách gói...${NC}" | tee -a "$LOG_FILE"
apt update -y

# Cài đặt tmux và curl
echo -e "${GREEN}Đang cài đặt tmux và curl...${NC}" | tee -a "$LOG_FILE"
apt install -y tmux curl

# Kiểm tra cài đặt tmux và curl
for cmd in tmux curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Cài đặt $cmd thất bại! Vui lòng kiểm tra lại.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Hiển thị phiên bản tmux
echo -e "${GREEN}tmux đã được cài đặt thành công! Phiên bản:${NC}" | tee -a "$LOG_FILE"
tmux -V | tee -a "$LOG_FILE"

# Tạo tệp cấu hình .tmux.conf
TMUX_CONF="/home/$SUDO_USER/.tmux.conf"
[ -z "$SUDO_USER" ] && TMUX_CONF="/root/.tmux.conf"
echo -e "${GREEN}Đang tạo tệp cấu hình .tmux.conf tại $TMUX_CONF...${NC}" | tee -a "$LOG_FILE"

cat > "$TMUX_CONF" << EOF
# Thay đổi prefix từ Ctrl+b sang Ctrl+a
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Bật hỗ trợ chuột
set -g mouse on

# Thay đổi chỉ mục cửa sổ và pane bắt đầu từ 1
set -g base-index 1
setw -g pane-base-index 1

# Cải thiện màu sắc
set -g default-terminal "screen-256color"

# Tùy chỉnh thanh trạng thái
set -g status-bg colour234
set -g status-fg colour12
set -g status-left "[#S] "
set -g status-right "%Y-%m-%d %H:%M"

# Chia pane nhanh bằng | và -
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Di chuyển giữa các pane giống Vim
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
EOF

# Phân quyền cho tệp cấu hình
chown "${SUDO_USER:-root}:${SUDO_USER:-root}" "$TMUX_CONF"
chmod 644 "$TMUX_CONF"
echo -e "${GREEN}Tệp cấu hình .tmux.conf đã được tạo thành công.${NC}" | tee -a "$LOG_FILE"

# Cài đặt Nexus CLI
echo -e "${GREEN}Đang cài đặt Nexus CLI...${NC}" | tee -a "$LOG_FILE"
if ! curl -s --fail --connect-timeout 10 https://cli.nexus.xyz/ | sh; then
    echo -e "${RED}Cài đặt Nexus CLI thất bại! Vui lòng kiểm tra kết nối mạng hoặc URL.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Kiểm tra lệnh nexus-network
if ! command -v nexus-network &> /dev/null; then
    echo -e "${RED}Lệnh nexus-network không tồn tại! Cài đặt Nexus CLI thất bại.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi
echo -e "${GREEN}Nexus CLI đã được cài đặt thành công!${NC}" | tee -a "$LOG_FILE"

# Yêu cầu URL danh sách node ID
DEFAULT_NODE_URL="${NEXUS_NODE_URL:-https://raw.githubusercontent.com/lucduong2406/NEXUS-CLI/main/12}"
echo -e "${GREEN}Vui lòng nhập URL chứa danh sách node ID (Enter để sử dụng $DEFAULT_NODE_URL):${NC}" | tee -a "$LOG_FILE"
read -r NODE_URL
NODE_URL="${NODE_URL:-$DEFAULT_NODE_URL}"

# Tải danh sách node ID
echo -e "${GREEN}Đang tải danh sách node ID từ $NODE_URL...${NC}" | tee -a "$LOG_FILE"
NODE_IDS=$(curl -s --fail --connect-timeout 10 "$NODE_URL" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$NODE_IDS" ]; then
    echo -e "${RED}Không thể tải danh sách node ID từ $NODE_URL! Vui lòng kiểm tra URL hoặc kết nối mạng.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Lọc node ID hợp lệ
NODE_IDS=$(echo "$NODE_IDS" | grep -E '^[0-9]+$' | grep -v '^$')
NODE_COUNT=$(echo "$NODE_IDS" | wc -l)
if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${RED}Không tìm thấy node ID hợp lệ trong danh sách!${NC}" | tee -a "$LOG_FILE"
    exit 1
fi
echo -e "${GREEN}Tìm thấy $NODE_COUNT node ID hợp lệ.${NC}" | tee -a "$LOG_FILE"

# Kiểm tra phiên tmux cũ
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo -e "${RED}Phiên tmux $SESSION_NAME đã tồn tại.${NC}" | tee -a "$LOG_FILE"
    read -p "Bạn có muốn xóa phiên này để tiếp tục? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo -e "${RED}Vui lòng xóa phiên tmux hiện tại hoặc chọn tên phiên khác.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
    tmux kill-session -t "$SESSION_NAME"
    echo -e "${GREEN}Đã xóa phiên tmux $SESSION_NAME.${NC}" | tee -a "$LOG_FILE"
fi

# Tạo phiên tmux mới
echo -e "${GREEN}Đang tạo phiên tmux mới: $SESSION_NAME...${NC}" | tee -a "$LOG_FILE"
tmux new-session -d -s "$SESSION_NAME"

# Tạo cửa sổ cho mỗi node ID
WINDOW_INDEX=1
while IFS= read -r node_id; do
    if [ -n "$node_id" ]; then
        if [ $WINDOW_INDEX -gt 1 ]; then
            tmux new-window -t "$SESSION_NAME:$WINDOW_INDEX" -n "node-$node_id"
        else
            tmux rename-window -t "$SESSION_NAME:$WINDOW_INDEX" "node-$node_id"
        fi
        tmux send-keys -t "$SESSION_NAME:$WINDOW_INDEX" "nexus-network start --node-id $node_id" C-m
        echo -e "${GREEN}Đã tạo cửa sổ $WINDOW_INDEX cho node ID $node_id.${NC}" | tee -a "$LOG_FILE"
        ((WINDOW_INDEX++))
    fi
done <<< "$NODE_IDS"

# Chọn cửa sổ đầu tiên
tmux select-window -t "$SESSION_NAME:1"

# Gắn vào phiên tmux
echo -e "${GREEN}Đang gắn vào phiên tmux $SESSION_NAME với $NODE_COUNT cửa sổ...${NC}" | tee -a "$LOG_FILE"
echo -e "${GREEN}Hướng dẫn: Ctrl+a n (chuyển cửa sổ tiếp), Ctrl+a p (cửa sổ trước), Ctrl+a d (thoát tmux).${NC}" | tee -a "$LOG_FILE"
echo -e "${GREEN}Dừng phiên: 'sudo ./ok.sh stop'. Xem log: 'cat $LOG_FILE'.${NC}" | tee -a "$LOG_FILE"
tmux attach-session -t "$SESSION_NAME"

# Thông báo hoàn tất
echo -e "${GREEN}Cài đặt và chạy nexus-network hoàn tất!${NC}" | tee -a "$LOG_FILE"
