# 階段一：構建與下載環境
FROM node:20-slim AS builder

WORKDIR /tmp-download

# 安裝下載所需的工具與憑證
RUN apt-get update && apt-get install -y ca-certificates wget && rm -rf /var/lib/apt/lists/*

# 【修正】使用官方明確釋出的 v2.12.5 穩定版網址，確保 100% 下載到正確的二進位檔
RUN wget -q https://github.com/Exafunction/codeium/releases/latest/download/language_server_linux_x64 \
    && chmod +x language_server_linux_x64

# 階段二：最終運行環境
FROM node:20-slim

# 【關鍵修正】在最終環境同時安裝憑證與 wget、curl
# 這樣才能支援：外部網路連線 + 你指定的 wget 健康檢查 + 背景定時重新整理
RUN apt-get update && apt-get install -y ca-certificates wget curl && rm -rf /var/lib/apt/lists/*

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
RUN mkdir -p /home/user/projects \
    && ln -s /tmp/windsurf-workspace /home/user/projects/workspace-devinxse \
    && chown -R app:app /home/user /opt/windsurf

# 設定環境變數
ENV LS_BINARY_PATH=/opt/windsurf/language_server_linux_x64
ENV PORT=3003
ENV LS_PORT=42100
ENV LOG_LEVEL=info

# 建立可寫入的運行狀態目錄，並確保 app 用戶有完整權限
RUN mkdir -p /app/logs /tmp/windsurf-workspace \
    && chown -R app:app /app /tmp/windsurf-workspace /opt/windsurf

USER app

EXPOSE 3003

# 運作正常的標準 wget 健康檢查（因為階段二已安裝 wget）
# HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
#  CMD wget -qO- http://127.0.0.1:3003/health || exit 1

# 【終極優化命令】同時啟動背景重新整理迴圈（每 120 秒）與 Node.js 主服務
CMD ["sh", "-c", "while true; do sleep 120; curl -s -X POST http://127.0.0.1:3003/dashboard/api/accounts/refresh-credits -H \"X-Dashboard-Password: ${DASHBOARD_PASSWORD}\"; done & node src/index.js"]
