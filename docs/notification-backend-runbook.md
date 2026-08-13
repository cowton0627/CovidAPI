# 通知後端實作檢查清單

這份清單適用於選定任一 hosting、資料庫與 runtime 後的 staging／production 上線流程。

## 建立環境

- [ ] 建立獨立的 staging 與 production project、database、queue worker。
- [ ] 在 secret manager 建立 CDC source、APNs key id、team id、private key、database URL 與 bearer signing key。
- [ ] 限制 production secret 的讀取角色；CI 只取得部署所需的短效憑證。
- [ ] 設定 `/healthz`、抓取成功率、queue backlog、APNs error rate 與失效 token metrics。

供應商未選定前，可使用 repository 根目錄的 `compose.staging.yaml` 建立不發送推播的 provider-neutral staging。APNs sandbox 憑證備妥後，再疊加 `compose.apns.yaml`；後者是唯一會將 `PUSH_DISPATCH_ENABLED` 切為 `true` 的設定。

## 部署順序

1. 執行 database migration，確認唯一鍵 `(epidemicIdentifier, token)` 已建立。
2. 部署 API 與 worker，但先停用 production push dispatch。
3. 執行 CDC dry-run，只寫入抓取結果與 metrics，不建立發送工作。
4. 以測試裝置 token 驗證註冊、偏好同步、撤銷與 `/healthz`。
5. 啟用 staging APNs topic，確認 payload 通過 [`notification-payload.schema.json`](notification-payload.schema.json)。
6. 以小比例 production devices canary，確認去重與退避重試後再全面啟用。

## 事故處理

- CDC schema 變更：停用 dispatch，保留最後成功快照，修正 parser 後重新執行 dry-run。
- APNs 大量 `5xx` 或 `429`：停止新增 dispatch，保留 queue，依 `Retry-After` 退避。
- 重複通知：立即停用 worker，檢查唯一鍵與 delivery transaction，再從未發送狀態恢復。
- token 外洩疑慮：撤銷相關 bearer key、輪換 APNs key，刪除受影響 token 並要求 app 重新註冊。

## 回滾

- API 與 worker 使用可回滾版本標籤，migration 必須提供向後相容的 down plan。
- 回滾只停止推播，不刪除 `epidemic_items` 與 delivery audit，避免恢復後重複發送。
- 回滾完成後確認 `/healthz`、queue backlog 與 app 的 API fallback 都正常。
