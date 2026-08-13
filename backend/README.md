# Notification backend

零第三方 runtime dependency 的最小通知服務，使用 Python 3.11+、SQLite、CDC JSON 與 APNs HTTP/2。

```sh
python3 -m unittest discover -s backend/tests -v
python3 -m backend.notification_backend --database /tmp/covidapi.sqlite3 sync --dry-run

BACKEND_ACCESS_TOKEN='replace-me' \
python3 -m backend.notification_backend --database /tmp/covidapi.sqlite3 serve
```

排程器依序執行 `sync` 與 `dispatch`。正式 dispatch 需由 secret manager 注入：

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`（`.p8` 完整內容）
- `APNS_TOPIC`（app bundle identifier）
- `APNS_ENVIRONMENT=sandbox|production`

另可設定 `DATABASE_PATH`、`CDC_URL`、`PORT`。`BACKEND_ACCESS_TOKEN` 是目前的單一 staging access token；正式多使用者環境應在 API gateway 驗證短效 token。APNs client 需要系統提供 `openssl` 與支援 HTTP/2 的 `curl`。

SQLite 檔包含 APNs device token，部署時必須放在具備靜態加密與最小權限的 managed volume／database，且不得收進備份以外的 log 或 metrics。需要共享資料庫或多 instance worker 時，應將 repository 層換成受管資料庫後再擴展。

首次同步 production 前先執行 `sync --dry-run`。這會驗證並保存 CDC 快照，但不建立 delivery；避免把既有疫情推送成新通知。

## Provider-neutral staging

容器設定刻意不綁定雲端供應商。安裝 Docker 的環境可先建立 `backend/.env.staging`（參考 `.env.staging.example`），再啟動不發送推播的 API 與 CDC worker：

```sh
docker compose --env-file backend/.env.staging -f compose.staging.yaml up --build -d
curl http://127.0.0.1:8080/healthz
```

worker 預設每 15 分鐘同步並建立 CDC baseline，但 `PUSH_DISPATCH_ENABLED=false`，因此不會建立或送出 delivery。準備好 sandbox APNs `.p8` 後，明確加入 APNs override 才會啟用推播：

```sh
docker compose --env-file backend/.env.staging \
  -f compose.staging.yaml -f compose.apns.yaml up --build -d
```

hosting 必須提供 TLS termination，且 `/v1/*` 不應直接暴露於沒有 rate limit 的公網。SQLite volume 只適合單一 API container＋單一 worker 的 staging；production 或水平擴展前需改用 managed database。
