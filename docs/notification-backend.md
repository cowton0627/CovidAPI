# 即時疫情通知後端設計

本文件描述未來將 CDC 旅遊疫情資料轉成 APNs 推播的最小後端契約。iOS app 目前已能接收通知、解析疫情識別資訊並導覽至詳細頁；後端只需要穩定產生相同格式的 payload。

## 流程

1. 排程工作定期抓取 CDC Open Data JSON。
2. 驗證 HTTP 狀態、JSON schema 與必要欄位；失敗時保留上一次成功快照。
3. 以 `notificationIdentifier`（地區、疫情標題與發布時間的穩定組合）去重，只處理新項目或內容版本變更。
4. 將新疫情寫入短期資料庫，建立待發送工作。
5. 依裝置 token 與使用者收藏地區篩選收件者，透過 APNs 發送。
6. 成功送達後記錄 `apns-id`；永久失效 token 移除，暫時錯誤採指數退避重試。

## APNs payload

```json
{
  "aps": {
    "alert": {
      "title": "新的旅遊疫情資訊",
      "body": "日本-腸病毒"
    },
    "sound": "default"
  },
  "epidemicIdentifier": "日本-腸病毒|1700000000.0"
}
```

`epidemicIdentifier` 必須與 app 的 `EpidemicNotificationRoute` 格式相容；不要把完整疫情描述放進 payload，避免超過 APNs 大小限制，詳細內容由 app 更新資料後顯示。

## 必要資料表

- `epidemic_items`: identifier、來源發布時間、內容 hash、首次與最後觀察時間。
- `device_tokens`: token、平台、收藏地區集合、授權狀態、最後成功時間。
- `notification_deliveries`: item identifier、token、狀態、重試次數、APNs request id。

## 安全與可靠性

- APNs key、CDC API 憑證與資料庫連線資訊只放在 secret manager，不進 repository。
- 裝置 token 以雜湊或加密形式保存，並提供撤銷與保存期限。
- 每次抓取與推播都記錄 metrics：抓取成功率、新項目數、發送成功率、失效 token 數與延遲。
- 使用唯一鍵 `(epidemicIdentifier, token)` 保證重試不造成重複通知。
- 先以 staging topic 與測試 token 驗證，再逐步提高 production 發送比例。

## 與目前 iOS app 的銜接

- app 仍負責本地收藏、通知 opt-in 與詳細頁導覽。
- 後端收到裝置 token 與收藏同步資料後，只推送使用者已收藏地區的新項目。
- 若 app 長時間離線，重新啟動時仍以 API 快照補齊資料，不依賴推播完整性。

## HTTP API 契約

所有 endpoint 使用 HTTPS、JSON，並以短效 access token 驗證。伺服器不得把 APNs secret 或完整 token 回傳給 app。

### `PUT /v1/devices/{deviceId}`

註冊或更新裝置 token。`deviceId` 應由 app 產生並持久化，不使用 Apple ID 或其他個人識別資訊。

```json
{
  "platform": "ios",
  "pushToken": "<hex token>",
  "notificationsEnabled": true,
  "favoriteLocations": ["日本", "美國"]
}
```

回應 `204 No Content`。重複提交必須冪等，token 變更時覆蓋舊值。

### `PATCH /v1/devices/{deviceId}/preferences`

同步通知 opt-in 與收藏地區。只接受必要欄位，回應 `204 No Content`；收藏集合應限制筆數與字串長度。

### `DELETE /v1/devices/{deviceId}`

撤銷裝置 token 與所有收藏同步資料，回應 `204 No Content`。登出、使用者關閉通知或刪除 app 資料時呼叫。

### `GET /healthz`

供排程器與 hosting health check 使用，只回傳服務狀態，不包含資料庫、APNs 或 CDC secret 詳細資訊。正常回應 `200 {"status":"ok"}`。

### 錯誤格式

```json
{
  "error": {
    "code": "invalid_request",
    "message": "favoriteLocations contains an invalid value"
  }
}
```

`4xx` 不重試；`429` 與 `5xx` 使用 `Retry-After` 或指數退避。所有錯誤回應不得回傳 push token。
