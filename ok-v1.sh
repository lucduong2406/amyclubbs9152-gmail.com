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

# Hàm ghi log
log_message() {
    local message="$1"
    echo "$message" >> "$LOG_FILE"
    echo "$message"
}

# Kiểm tra và tạo thư mục log
LOG_DIR="$(dirname "$LOG_FILE")"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo -e "${RED}Không thể tạo thư mục log $LOG_DIR!${NC}"
    exit 1
fi

# Kiểm tra quyền ghi tệp log
if ! touch "$LOG_FILE" 2>/dev/null || ! [ -w "$LOG_FILE" ]; then
    echo -e "${RED}Không thể ghi vào tệp log $LOG_FILE! Vui lòng kiểm tra quyền.${NC}"
    exit 1
fi

# Ghi thông báo bắt đầu
log_message "[$(date)] Bắt đầu thực thi script..."

# Chuyển hướng output sau khi kiểm tra
exec 1>>"$LOG_FILE" 2>&1

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    log_message "${RED}Vui lòng chạy script này với quyền root (sudo)!${NC}"
    exit 1
fi

# Kiểm tra hệ điều hành
if ! command -v apt &> /dev/null; then
    log_message "${RED}Hệ thống không hỗ trợ apt. Vui lòng chạy trên Ubuntu/Debian.${NC}"
    exit 1
fi

# Kiểm tra dung lượng đĩa
MIN_DISK_SPACE=1024 # MB
AVAILABLE_SPACE=$(df -m / | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt "$MIN_DISK_SPACE" ]; then
    log_message "${RED}Dung lượng đĩa trống ($AVAILABLE_SPACE MB) không đủ. Cần ít nhất $MIN_DISK_SPACE MB.${NC}"
    exit 1
fi

# Xử lý lệnh stop/restart
SESSION_NAME="nexus_nodes"
case "$1" in
    stop)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux kill-session -t "$SESSION_NAME"
            log_message "${GREEN}Đã dừng phiên tmux $SESSION_NAME.${NC}"
        else
            log_message "${GREEN}Không tìm thấy phiên tmux $SESSION_NAME.${NC}"
        fi
        exit 0
        ;;
    restart)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            tmux kill-session -t "$SESSION_NAME"
            log_message "${GREEN}Đã xóa phiên tmux $SESSION_NAME để khởi động lại.${NC}"
        fi
        ;;
esac

# Cập nhật hệ thống
log_message "${GREEN}Đang cập nhật danh sách gói...${NC}"
apt update -y

# Cài đặt tmux và curl
log
