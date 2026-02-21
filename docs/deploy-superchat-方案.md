# Prompt Optimizer 部署方案（superchat.help）

**修订日期**：2025-02-21  
**免责说明**：本文档为部署评估与方案，具体环境需按实际情况调整。

---

## 一、项目与需求简要

| 项目 | 说明 |
|------|------|
| 仓库 | https://github.com/wushushuochanpin/prompt-optimizer.git |
| 落地路径 | `/root/coderepository/prompt-optimizer` |
| 域名 | `prompt-optimizer.superchat.help`，HTTPS，Nginx 反代 |
| 运行方式 | 全部 Docker，且**前后端均以开发服务器热加载模式**运行 |

---

## 二、项目结构评估

- **前端**：Vue3 + Vite，`packages/web` 开发端口 **18181**（`host: true`，可被外网访问）。
- **MCP 服务**：Node 独立进程，默认端口 **3000**，路径前缀 `/mcp`；需先 `mcp:build` 再 `mcp:dev`。
- **“后端”**：项目为**纯前端 + 静态资源 + MCP**，无独立后端 API 服务；`api/` 下仅有 `auth.js` 等辅助脚本，不单独起服务。
- **官方 Docker**：当前 `docker-compose.yml` / `Dockerfile` 为**生产模式**（构建静态 + Nginx + MCP），**无开发热加载**；要实现「全部开发服务器热加载」需**自建开发用 Compose 与启动方式**。

结论：  
- 服务只有两类：**Web 前端（Vite dev）**、**MCP 服务（Node dev）**。  
- 满足「全部 Docker + 开发热加载」需在容器内跑 `pnpm dev`（含 UI watch + web dev）和 `pnpm mcp:dev`，并由宿主机 Nginx 反代到容器端口。

---

## 三、部署方案概览

### 3.1 代码与版本

- 代码已克隆到：`/root/coderepository/prompt-optimizer`。
- 使用仓库**默认分支**（当前为 `develop`），即最新版本；如需固定版本可再 `git checkout vx.x.x`。

### 3.2 服务架构（开发热加载）

```
                    HTTPS (443)
                         │
                         ▼
              Nginx (宿主机或独立容器)
              prompt-optimizer.superchat.help
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
    /  →  Web (Vite dev)            /mcp → MCP (Node dev)
         容器端口 18181                   容器端口 3000
         (热加载)                         (开发模式)
```

- **一个应用容器**内同时跑：
  - `pnpm dev`：core/ui 构建 + UI watch + **Web Vite dev（18181）**，支持前端热加载。
  - `pnpm mcp:build && pnpm mcp:dev`：**MCP 开发模式（3000）**；MCP 代码变更需重启或后续可加 watch。
- 宿主机 Nginx 将：
  - `https://prompt-optimizer.superchat.help/` → `http://<容器>:18181`
  - `https://prompt-optimizer.superchat.help/mcp` → `http://<容器>:3000/mcp`

### 3.3 目录与文件规划

| 用途 | 路径/文件 |
|------|-----------|
| 代码库 | `/root/coderepository/prompt-optimizer` |
| 开发用 Compose | `/root/coderepository/prompt-optimizer/docker-compose.dev-hot.yml` |
| 环境变量示例 | 复制 `env.local.example` 为 `.env.local` 并按需填写 |
| Nginx 配置 | 见下节（宿主机或独立 Nginx 容器） |

### 3.4 Nginx 反代与 HTTPS

- 在**宿主机**或**独立 Nginx 容器**上配置：
  - `server_name prompt-optimizer.superchat.help`
  - SSL 证书（Let's Encrypt 或已有证书）配置 `ssl_certificate` / `ssl_certificate_key`
  - `location /` → `proxy_pass http://127.0.0.1:18181`（或应用容器映射出的宿主机端口）
  - `location /mcp` → `proxy_pass http://127.0.0.1:3000`
- 需设置 `proxy_http_version 1.1`、`proxy_set_header Host $host`、`X-Forwarded-Proto $scheme` 等，以便前端与 MCP 正确识别协议与域名。

### 3.5 运行步骤摘要

1. 在仓库根目录复制并编辑环境变量（若不存在 `.env.local` 会报错）：  
   `cp env.local.example .env.local`
2. 启动开发栈：  
   `cd /root/coderepository/prompt-optimizer && docker compose -f docker-compose.dev-hot.yml up -d`
3. 配置 Nginx：将 `docker/nginx-dev-reverse.conf` 拷贝到宿主机 Nginx 并修改证书路径，重载 Nginx；确保 DNS 将 `prompt-optimizer.superchat.help` 指向本机。
4. 浏览器访问：`https://prompt-optimizer.superchat.help`

---

## 四、补充与注意事项

### 4.1 必须项

- **HTTPS 证书**：需为 `prompt-optimizer.superchat.help` 准备证书（如 `certbot` / `acme.sh`），并在 Nginx 中配置。
- **DNS**：将 `prompt-optimizer.superchat.help` 解析到 Nginx 所在机器 IP。
- **环境变量**：至少配置一个 LLM API Key（如 `VITE_OPENAI_API_KEY` 或 `VITE_GEMINI_API_KEY`），否则优化与 MCP 功能不可用；可参考 `env.local.example`。

### 4.2 安全与访问控制

- 当前方案未启用 Basic 认证；若需与官方 Docker 一致的门户保护，可在 Nginx 的 `location /` 上增加 `auth_basic`，或后续在应用层加鉴权。
- 开发模式会暴露更多调试信息，建议仅在内网或受控环境使用；若对外公网，建议使用生产构建 + 现有 Dockerfile 部署。

### 4.3 热加载范围

- **Web 前端**：Vite 热更新生效。
- **MCP**：以 `mcp:dev` 运行，代码变更后需**重启 MCP 进程**（或后续在镜像/脚本中增加 watch 自动重启）。

### 4.4 与官方生产部署的差异

- 官方 `docker-compose.yml` 使用镜像 `linshen/prompt-optimizer:latest`，为**生产镜像**（Nginx + 静态 + MCP），无热加载。
- 本方案使用**自建的开发用 Compose**，挂载源码、在容器内跑 `pnpm dev` + `pnpm mcp:dev`，实现开发热加载；**不**使用官方生产镜像。

### 4.5 可选优化

- 若需 MCP 代码变更也自动生效，可在容器内用 `nodemon` 或 `tsup --watch` 监听 `packages/mcp-server` 并重启 `mcp:dev`。
- 若希望 Nginx 也容器化，可增加一个 `nginx` 服务，与 app 同网段，反代到 `app:18181` 与 `app:3000`。

---

## 五、结论

- **方案可行**：代码已落在 `/root/coderepository/prompt-optimizer`，通过新增 `docker-compose.dev-hot.yml` 在 Docker 内以开发模式运行 Web（18181）与 MCP（3000），宿主机 Nginx 反代并配置 HTTPS 即可实现「全部 Docker + 开发服务器热加载」。
- **补充**：需自行完成 DNS、HTTPS 证书、`.env.local` 配置；若需访问控制或对外生产环境，建议再叠加认证或改用生产镜像部署。
