# 階段一：構建與下載環境
FROM node:20-slim AS builder

WORKDIR /tmp-download

# 安裝下載所需的 wget
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# 下載正確的 Windsurf / Codeium Language Server 二進位檔，並直接賦予執行權限
RUN wget -q https://github.com/Exafunction/codeium/releases/latest/download/language_server_linux_x64 \
    && chmod +x language_server_linux_x64

# 階段二：最終運行環境
FROM node:20-slim

# 【關鍵修正】在最終運行環境安裝 ca-certificates 憑證包，否則無法建立外網 TLS 連線
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# 建立非 root 用戶
RUN groupadd -r app && useradd -r -g app app

WORKDIR /app

# 複製專案原始碼
COPY --chown=app:app package.json ./
COPY --chown=app:app src ./src
COPY --chown=app:app docs ./docs

# 建立 LS 存放目錄，並從 builder 階段將二進位檔複製過來
RUN mkdir -p /opt/windsurf
COPY --from=builder /tmp-download/language_server_linux_x64 /opt/windsurf/language_server_linux_x64

# 設定環境變數
ENV LS_BINARY_PATH=/opt/windsurf/language_server_linux_x64
ENV PORT=3003
ENV LS_PORT=42100
ENV LOG_LEVEL=info

# 建立可寫入的運行狀態目錄，並確保 app 用戶有完整權限
RUN mkdir -p /app/logs /tmp/windsurf-workspace \
    && chown -R app:app /app /tmp/windsurf-workspace /opt/windsurf

USER app

# 暴露內部的 3003 連接埠
EXPOSE 3003

# 使用 Node.js 內建指令來做健康檢查
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

CMD ["node", "src/index.js"]
