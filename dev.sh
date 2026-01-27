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
BACKEND_PORT=3000
FRONTEND_PORT=5173

# 环境变量(是否调试模式)
export DEBUG=true
export BROWSER=none
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"

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

ensure_log_dir() {
    mkdir -p "$LOG_DIR"
}

read_pid() {
    local pid_file="$1"
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -z "$pid" ]; then
        return 1
    fi
    echo "$pid"
}

pid_is_running() {
    local pid_file="$1"
    local expected_cmd="$2"
    local pid
    pid=$(read_pid "$pid_file") || return 1
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    if [ -n "$expected_cmd" ]; then
        local cmd
        cmd=$(ps -p "$pid" -o command= 2>/dev/null)
        [[ "$cmd" == *"$expected_cmd"* ]] || return 1
    fi
    return 0
}

port_is_listening() {
    local port="$1"
    lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

port_listener_pid() {
    local port="$1"
    lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n1
}

sync_pid_file_with_port() {
    local pid_file="$1"
    local port="$2"
    local pid
    pid=$(port_listener_pid "$port")
    if [ -n "$pid" ]; then
        echo "$pid" > "$pid_file"
        return 0
    fi
    return 1
}

tail_recent_log() {
    local log_file="$1"
    if [ -f "$log_file" ]; then
        tail -20 "$log_file"
    else
        echo "无日志"
    fi
}

wait_for_service() {
    local service_name="$1"
    local pid_file="$2"
    local expected_cmd="$3"
    local port="$4"
    local log_file="$5"
    local max_wait="${6:-30}"

    for ((i=1; i<=max_wait; i++)); do
        if port_is_listening "$port"; then
            sync_pid_file_with_port "$pid_file" "$port"
            return 0
        fi
        if [ "$i" -gt 1 ] && ! pid_is_running "$pid_file" "$expected_cmd"; then
            log_error "$service_name 进程已退出，请查看日志: $log_file"
            tail_recent_log "$log_file"
            rm -f "$pid_file"
            return 1
        fi
        sleep 1
    done

    log_error "$service_name 启动超时，端口 $port 未就绪，请查看日志: $log_file"
    tail_recent_log "$log_file"
    return 1
}

start_detached() {
    local pid_file="$1"
    local log_file="$2"
    shift 2

    setsid "$@" >>"$log_file" 2>&1 < /dev/null &
    echo $! > "$pid_file"
}

ensure_frontend_deps() {
    if [ ! -x "$WEB_DIR/node_modules/.bin/vite" ]; then
        log_info "安装前端依赖..."
        (
            cd "$WEB_DIR" &&
            bun install
        ) || return 1
    fi
}

ensure_frontend_dist() {
    if [ -f "$WEB_DIR/dist/index.html" ]; then
        return 0
    fi

    ensure_frontend_deps || return 1
    log_info "构建前端静态资源..."
    (
        cd "$WEB_DIR" &&
        bun run build
    ) || return 1
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
    for pid in $(lsof -ti:"$BACKEND_PORT" 2>/dev/null); do
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
    for pid in $(lsof -ti:"$FRONTEND_PORT" 2>/dev/null); do
        kill -9 "$pid" 2>/dev/null
    done
    log_info "前端服务已停止"
}

# 启动后端
start_backend() {
    cd "$PROJECT_DIR"
    ensure_log_dir
    ensure_frontend_dist || {
        log_error "前端静态资源构建失败"
        return 1
    }
    log_info "编译后端..."
    if ! go build -o new-api .; then
        log_error "后端编译失败"
        return 1
    fi
    log_info "启动后端服务..."
    : > "$BACKEND_LOG"
    start_detached "$BACKEND_PID_FILE" "$BACKEND_LOG" ./new-api
    if wait_for_service "后端服务" "$BACKEND_PID_FILE" "./new-api" "$BACKEND_PORT" "$BACKEND_LOG"; then
        log_info "后端服务已启动 (PID: $(cat "$BACKEND_PID_FILE"))"
        log_info "后端地址: http://localhost:$BACKEND_PORT/"
        log_info "日志文件: $BACKEND_LOG"
    else
        return 1
    fi
}

# 启动前端
start_frontend() {
    cd "$WEB_DIR"
    ensure_log_dir
    ensure_frontend_deps || {
        log_error "前端依赖安装失败"
        return 1
    }
    log_info "启动前端开发服务器..."
    : > "$FRONTEND_LOG"
    start_detached "$FRONTEND_PID_FILE" "$FRONTEND_LOG" bun run dev --host 0.0.0.0
    if wait_for_service "前端服务" "$FRONTEND_PID_FILE" "" "$FRONTEND_PORT" "$FRONTEND_LOG"; then
        log_info "前端服务已启动 (PID: $(cat "$FRONTEND_PID_FILE"))"
        log_info "前端地址: http://localhost:$FRONTEND_PORT/"
        log_info "日志文件: $FRONTEND_LOG"
    else
        return 1
    fi
}

# 查看状态
show_status() {
    echo ""
    echo "========== 服务状态 =========="

    # 后端状态
    if port_is_listening "$BACKEND_PORT"; then
        sync_pid_file_with_port "$BACKEND_PID_FILE" "$BACKEND_PORT"
        echo -e "后端: ${GREEN}运行中${NC} (PID: $(cat "$BACKEND_PID_FILE")) - http://localhost:$BACKEND_PORT/"
    else
        echo -e "后端: ${RED}已停止${NC}"
    fi

    # 前端状态
    if port_is_listening "$FRONTEND_PORT"; then
        sync_pid_file_with_port "$FRONTEND_PID_FILE" "$FRONTEND_PORT"
        echo -e "前端: ${GREEN}运行中${NC} (PID: $(cat "$FRONTEND_PID_FILE")) - http://localhost:$FRONTEND_PORT/"
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
        start_ok=0
        case "$2" in
            backend|b)
                stop_backend
                start_backend || start_ok=1
                ;;
            frontend|f)
                stop_frontend
                start_frontend || start_ok=1
                ;;
            *)
                stop_backend
                stop_frontend
                start_backend || start_ok=1
                start_frontend || start_ok=1
                show_status
                ;;
        esac
        exit "$start_ok"
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
        restart_ok=0
        case "$2" in
            backend|b)
                stop_backend
                start_backend || restart_ok=1
                ;;
            frontend|f)
                stop_frontend
                start_frontend || restart_ok=1
                ;;
            *)
                stop_backend
                stop_frontend
                sleep 1
                start_backend || restart_ok=1
                start_frontend || restart_ok=1
                show_status
                ;;
        esac
        exit "$restart_ok"
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
