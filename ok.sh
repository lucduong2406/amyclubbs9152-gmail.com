#!/bin/bash

# Script tự động cài đặt tmux, Nexus CLI, và chạy nexus-network trong các cửa sổ tmux riêng biệt trên Ubuntu

# Màu sắc cho thông báo
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Vui lòng chạy script này với quyền root (sudo)!${NC}"
  exit 1
fi

# Cập nhật hệ thống
echo -e "${GREEN}Đang cập nhật danh sách gói...${NC}"
apt update -y

# Cài đặt tmux
echo -e "${GREEN}Đang cài đặt tmux...${NC}"
apt install -y tmux

# Kiểm tra xem tmux đã được cài đặt thành công chưa
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}Cài đặt tmux thất bại! Vui lòng kiểm tra lại.${NC}"
    exit 1
fi

# Hiển thị phiên bản tmux
echo -e "${GREEN}tmux đã được cài đặt thành công! Phiên bản:${NC}"
tmux -V

# Tạo tệp cấu hình .tmux.conf cho user hiện tại
TMUX_CONF="/home/$SUDO_USER/.tmux.conf"
echo -e "${GREEN}Đang tạo tệp cấu hình .tmux.conf...${NC}"

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
chown "$SUDO_USER:$SUDO_USER" "$TMUX_CONF"
echo -e "${GREEN}Tệp cấu hình .tmux.conf đã được tạo tại $TMUX_CONF${NC}"

# Cài đặt curl (nếu chưa có)
echo -e "${GREEN}Đang cài đặt curl...${NC}"
apt install -y curl

# Kiểm tra xem curl đã được cài đặt chưa
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Cài đặt curl thất bại! Vui lòng kiểm tra lại.${NC}"
    exit 1
fi

# Cài đặt Nexus CLI
echo -e "${GREEN}Đang cài đặt Nexus CLI...${NC}"
if curl -s https://cli.nexus.xyz/ | sh; then
    echo -e "${GREEN}Nexus CLI đã được cài đặt thành công!${NC}"
else
    echo -e "${RED}Cài đặt Nexus CLI thất bại! Vui lòng kiểm tra kết nối mạng hoặc URL.${NC}"
    exit 1
fi

# Yêu cầu người dùng nhập URL chứa danh sách node ID
echo -e "${GREEN}Vui lòng nhập URL chứa danh sách node ID (nhấn Enter để sử dụng URL mặc định: https://raw.githubusercontent.com/lucduong2406/NEXUS-CLI/refs/heads/main/12):${NC}"
read -r NODE_URL
if [ -z "$NODE_URL" ]; then
    NODE_URL="https://raw.githubusercontent.com/lucduong2406/NEXUS-CLI/main/12"
fi

# Tải danh sách node ID
echo -e "${GREEN}Đang tải danh sách node ID từ $NODE_URL...${NC}"
NODE_IDS=$(curl -s -f "$NODE_URL" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$NODE_IDS" ]; then
    echo -e "${RED}Không thể tải danh sách node ID từ $NODE_URL! Vui lòng kiểm tra URL hoặc kết nối mạng.${NC}"
    exit 1
fi

# Lọc node ID hợp lệ (chỉ giữ các dòng chứa số)
NODE_IDS=$(echo "$NODE_IDS" | grep -E '^[0-9]+$' | grep -v '^$')
NODE_COUNT=$(echo "$NODE_IDS" | wc -l)
if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${RED}Không tìm thấy node ID hợp lệ nào trong danh sách!${NC}"
    exit 1
fi

# Thông báo số cửa sổ sẽ tạo
echo -e "${GREEN}Sẽ tạo $NODE_COUNT cửa sổ tmux cho $NODE_COUNT node ID (mỗi node ID trong một cửa sổ).${NC}"

# Kiểm tra và xóa phiên tmux cũ nếu tồn tại
SESSION_NAME="nexus_nodes"
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo -e "${GREEN}Phiên tmux $SESSION_NAME đã tồn tại, đang xóa...${NC}"
    tmux kill-session -t "$SESSION_NAME"
fi

# Tạo phiên tmux mới
echo -e "${GREEN}Đang tạo phiên tmux mới: $SESSION_NAME...${NC}"
tmux new-session -d -s "$SESSION_NAME"

# Tạo cửa sổ cho mỗi node ID
WINDOW_INDEX=1
while IFS= read -r node_id; do
    if [ -n "$node_id" ]; then
        # Tạo cửa sổ mới (cửa sổ đầu tiên đã được tạo bởi new-session)
        if [ $WINDOW_INDEX -gt 1 ]; then
            tmux new-window -t "$SESSION_NAME:$WINDOW_INDEX" -n "node-$node_id"
        else
            tmux rename-window -t "$SESSION_NAME:$WINDOW_INDEX" "node-$node_id"
        fi

        # Gửi lệnh nexus-network start
        tmux send-keys -t "$SESSION_NAME:$WINDOW_INDEX" "nexus-network start --node-id $node_id" C-m

        ((WINDOW_INDEX++))
    fi
done <<< "$NODE_IDS"

# Chọn cửa sổ đầu tiên
tmux select-window -t "$SESSION_NAME:1"

# Gắn vào phiên tmux
echo -e "${GREEN}Đang gắn vào phiên tmux $SESSION_NAME với $NODE_COUNT node ID trên $NODE_COUNT cửa sổ...${NC}"
echo -e "${GREEN}Chuyển cửa sổ: Ctrl+a n (tiếp) hoặc Ctrl+a p (trước). Thoát: Ctrl+a d. Xóa phiên: 'tmux kill-session -t $SESSION_NAME'.${NC}"
tmux attach-session -t "$SESSION_NAME"

# Hiển thị thông báo hoàn tất
echo -e "${GREEN}Cài đặt và cấu hình tmux, Nexus CLI, và chạy nexus-network hoàn tất!${NC}"
