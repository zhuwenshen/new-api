#!/bin/bash

# 开发环境管理脚本
# 用法: ./dev.sh [start|stop|restart|status]

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_DIR="$PROJECT_DIR/web"
LOG_DIR="$PROJECT_DIR/logs"
BACKEND_PID_FILE="$PROJECT_DIR/.backend.pid"
FRONTEND_PID_FILE="$PROJECT_DIR/.frontend.pid"
BACKEND_LOG="$LOG_DIR/new-api-backend.log"
FRONTEND_LOG="$LOG_DIR/new-api-frontend.log"

# 环境变量(是否调试模式)
export DEBUG=true

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 停止后端
stop_backend() {
    # 先通过 PID 文件停止
    if [ -f "$BACKEND_PID_FILE" ]; then
        PID=$(cat "$BACKEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            log_info "停止后端服务 (PID: $PID)..."
            kill "$PID" 2>/dev/null
            sleep 1
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$BACKEND_PID_FILE"
    fi
    # 通过端口清理残留进程（排除 claude 进程）
    for pid in $(lsof -ti:3000 2>/dev/null); do
        local cmd=$(ps -p "$pid" -o command= 2>/dev/null)
        if [[ ! "$cmd" =~ "claude" ]]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done
    log_info "后端服务已停止"
}

# 停止前端
stop_frontend() {
    if [ -f "$FRONTEND_PID_FILE" ]; then
        PID=$(cat "$FRONTEND_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            log_info "停止前端服务 (PID: $PID)..."
            kill "$PID" 2>/dev/null
            sleep 1
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$FRONTEND_PID_FILE"
    fi
    # 清理 vite 进程
    pkill -f "vite" 2>/dev/null
    log_info "前端服务已停止"
}

# 启动后端
start_backend() {
    cd "$PROJECT_DIR"
    mkdir -p "$LOG_DIR"
    log_info "编译后端..."
    if ! go build -o new-api .; then
        log_error "后端编译失败"
        return 1
    fi
    log_info "启动后端服务..."
    nohup ./new-api > "$BACKEND_LOG" 2>&1 &
    echo $! > "$BACKEND_PID_FILE"
    sleep 2
    if kill -0 "$(cat "$BACKEND_PID_FILE")" 2>/dev/null; then
        log_info "后端服务已启动 (PID: $(cat "$BACKEND_PID_FILE"))"
        log_info "后端地址: http://localhost:3000/"
        log_info "日志文件: $BACKEND_LOG"
    else
        log_error "后端服务启动失败，请查看日志: $BACKEND_LOG"
        return 1
    fi
}

# 启动前端
start_frontend() {
    cd "$WEB_DIR"
    mkdir -p "$LOG_DIR"
    log_info "启动前端开发服务器..."
    nohup bun run dev > "$FRONTEND_LOG" 2>&1 &
    echo $! > "$FRONTEND_PID_FILE"
    sleep 3
    if kill -0 "$(cat "$FRONTEND_PID_FILE")" 2>/dev/null; then
        log_info "前端服务已启动 (PID: $(cat "$FRONTEND_PID_FILE"))"
        log_info "前端地址: http://localhost:5173/"
        log_info "日志文件: $FRONTEND_LOG"
    else
        log_error "前端服务启动失败，请查看日志: $FRONTEND_LOG"
        return 1
    fi
}

# 查看状态
show_status() {
    echo ""
    echo "========== 服务状态 =========="

    # 后端状态
    if [ -f "$BACKEND_PID_FILE" ] && kill -0 "$(cat "$BACKEND_PID_FILE")" 2>/dev/null; then
        echo -e "后端: ${GREEN}运行中${NC} (PID: $(cat "$BACKEND_PID_FILE")) - http://localhost:3000/"
    else
        echo -e "后端: ${RED}已停止${NC}"
    fi

    # 前端状态
    if [ -f "$FRONTEND_PID_FILE" ] && kill -0 "$(cat "$FRONTEND_PID_FILE")" 2>/dev/null; then
        echo -e "前端: ${GREEN}运行中${NC} (PID: $(cat "$FRONTEND_PID_FILE")) - http://localhost:5173/"
    else
        echo -e "前端: ${RED}已停止${NC}"
    fi
    echo "==============================="
    echo ""
}

# 查看日志
show_logs() {
    case "$1" in
        backend|b)
            tail -f "$BACKEND_LOG"
            ;;
        frontend|f)
            tail -f "$FRONTEND_LOG"
            ;;
        *)
            log_info "后端日志:"
            tail -20 "$BACKEND_LOG" 2>/dev/null || echo "无日志"
            echo ""
            log_info "前端日志:"
            tail -20 "$FRONTEND_LOG" 2>/dev/null || echo "无日志"
            ;;
    esac
}

# 显示帮助
show_help() {
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  start           启动所有服务（后端+前端）"
    echo "  start backend   仅启动后端"
    echo "  start frontend  仅启动前端"
    echo "  stop            停止所有服务"
    echo "  stop backend    仅停止后端"
    echo "  stop frontend   仅停止前端"
    echo "  restart         重启所有服务"
    echo "  restart backend 仅重启后端"
    echo "  status          查看服务状态"
    echo "  logs            查看最近日志"
    echo "  logs backend    实时查看后端日志"
    echo "  logs frontend   实时查看前端日志"
    echo "  help            显示帮助信息"
    echo ""
}

# 主逻辑
case "$1" in
    start)
        case "$2" in
            backend|b)
                stop_backend
                start_backend
                ;;
            frontend|f)
                stop_frontend
                start_frontend
                ;;
            *)
                stop_backend
                stop_frontend
                start_backend
                start_frontend
                show_status
                ;;
        esac
        ;;
    stop)
        case "$2" in
            backend|b)
                stop_backend
                ;;
            frontend|f)
                stop_frontend
                ;;
            *)
                stop_backend
                stop_frontend
                log_info "所有服务已停止"
                ;;
        esac
        ;;
    restart)
        case "$2" in
            backend|b)
                stop_backend
                start_backend
                ;;
            frontend|f)
                stop_frontend
                start_frontend
                ;;
            *)
                stop_backend
                stop_frontend
                sleep 1
                start_backend
                start_frontend
                show_status
                ;;
        esac
        ;;
    status|s)
        show_status
        ;;
    logs|log|l)
        show_logs "$2"
        ;;
    help|h|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
