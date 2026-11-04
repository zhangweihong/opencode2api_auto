#!/bin/sh
# 本地 Docker 部署脚本。
# 用法：
#   ./deploy.sh start     启动容器；本地镜像不存在时先构建
#   ./deploy.sh restart   重新构建镜像，并重建容器
#   ./deploy.sh stop      停止容器，保留数据卷和镜像
set -eu

# 固定到脚本所在的仓库根目录，避免从其他目录执行时找不到 Compose 文件。
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$root"

local_image=opencode2api:local

usage() {
    cat <<'EOF'
用法:
  ./deploy.sh start     启动容器。本地镜像不存在时会先构建。
  ./deploy.sh restart   重新构建镜像，并重建容器。
  ./deploy.sh stop      停止容器。保留数据卷和镜像。
EOF
}

# 打印命令后再执行。set -e 会在 Docker 返回非零状态时停止脚本。
run_docker() {
    printf '>> docker'
    printf ' %s' "$@"
    printf '\n'
    docker "$@"
}

assert_docker() {
    # 使用 Compose V2 的 docker compose 子命令，而不是旧的 docker-compose 可执行文件。
    if ! docker compose version >/dev/null 2>&1; then
        echo "未找到可用的 Docker Compose。请先安装并启动 Docker。" >&2
        exit 1
    fi
}

ensure_config() {
    if [ -f "$root/config.json" ]; then
        return
    fi
    if [ ! -f "$root/config.example.json" ]; then
        echo "缺少 config.json，并且找不到 config.example.json。" >&2
        exit 1
    fi
    # Compose 把宿主机 config.json 作为首次启动的配置种子，文件不存在时无法启动。
    cp "$root/config.example.json" "$root/config.json"
    echo "警告: 已根据 config.example.json 生成 config.json。启动前请填写 Key，并修改 WebUI 密码。" >&2
}

local_image_exists() {
    docker image inspect "$local_image" --format '{{.Id}}' >/dev/null 2>&1
}

build_image() {
    run_docker compose -f compose.yaml -f compose.local.yaml build
}

show_endpoints() {
    api_port=${OPENCODE2API_PORT:-9090}
    web_port=${OPENCODE2API_WEBUI_PORT:-9091}
    echo "API:   http://127.0.0.1:${api_port}"
    echo "WebUI: http://127.0.0.1:${web_port}"
}

action=${1:-}

case "$action" in
    start)
        assert_docker
        ensure_config
        if ! local_image_exists; then
            echo "本地镜像 ${local_image} 不存在，开始构建。"
            build_image
        fi
        run_docker compose -f compose.yaml -f compose.local.yaml up -d
        show_endpoints
        ;;
    restart)
        assert_docker
        ensure_config
        echo "重新构建镜像并重建容器。已有数据卷会保留。"
        build_image
        # --force-recreate 确保容器换上刚构建的镜像，而不是只重启旧容器。
        run_docker compose -f compose.yaml -f compose.local.yaml up -d --force-recreate
        show_endpoints
        ;;
    stop)
        assert_docker
        run_docker compose -f compose.yaml -f compose.local.yaml stop
        echo "容器已停止。数据卷和本地镜像已保留。"
        ;;
    *)
        usage
        exit 1
        ;;
esac
