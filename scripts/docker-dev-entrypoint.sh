#!/bin/sh
# 开发模式入口：安装依赖、构建 core/ui/mcp，并并行启动 Web 与 MCP 开发服务

set -e
cd /app

echo "Installing dependencies..."
pnpm install --frozen-lockfile

echo "Building core & ui & mcp (one-time)..."
pnpm build:core
pnpm build:ui
pnpm mcp:build

echo "Starting Web (Vite) + MCP dev servers..."
exec pnpm exec concurrently -k -n "WEB,MCP" \
  "pnpm run dev:parallel" \
  "pnpm mcp:dev"
