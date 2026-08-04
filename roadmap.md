# CovidAPI Roadmap

## 目前狀態

更新日期：2026-08-04

資料層重構、離線支援、地圖效能、UI tests、無障礙、未分級說明、地區收藏與 app 內新疫情通知均已完成。目前本機 `main` 比 `origin/main` 領先兩個 commits，尚未推送。

## 本次完成

- 將疫情資料模型、API client、磁碟快取、Repository 與列表 ViewModel 分層。
- 列表與地圖共用 `EpidemicRepository`，並合併同時發出的更新請求。
- 加入 Loading、Loaded、Empty、Error、Retry 等畫面狀態。
- 加入關鍵字搜尋與第一至第三級旅遊疫情篩選。
- 網路失敗時回傳最後一次成功資料，並正確標示為離線資料。
- 加入 XCTest 與 GitHub Actions CI。
- 將 Apple Developer Team ID 移至 ignored 的本機 xcconfig；tracked files 不含個人 Team ID。
- 更新 README 的架構、測試、簽章設定與功能說明。
- 地圖 geocoding 改用正規化地名，並以 UserDefaults 持久化座標，重新載入時可直接建立 marker。
- 地圖資料刷新會取消舊 geocoding 批次，避免過期或重複 marker 混入。
- 鄰近地圖 marker 會自動聚合，群組 marker 顯示包含的疫情筆數。
- 加入 3 項使用固定 fixture 的 UI tests，覆蓋搜尋／篩選、詳細頁導覽與地圖 tab 切換。
- 為列表、搜尋、篩選、狀態畫面、詳細內容、地圖 marker／群組與操作按鈕補齊 accessibility identifier、label 與 hint。
- 解析疾管署 `severity_level`，新增「未分級」篩選並停用沒有資料的等級，避免將空白誤解為疫情不嚴重。
- 加入地區收藏：詳細頁可切換收藏，列表可只顯示收藏地區，並以 UserDefaults 持久化。
- 加入通知 opt-in；app 更新資料時比對已看過項目，僅通知收藏地區的新疫情，首次啟用只建立基準。

## 驗證結果

- iPhone 15、iOS 17.5 Simulator build 成功。
- 12 項單元測試全部通過，0 failures：
  - 疫情等級判定採用最高匹配等級。
  - API 成功後寫入快取。
  - 網路失敗時使用磁碟快取。
  - 網路失敗時將記憶體 fallback 標示為離線資料。
  - ViewModel 搜尋與等級篩選。
  - 國家名稱別名與警示文字正規化。
  - 座標快取跨 instance 持久化。
  - 優先採用疾管署 `severity_level`。
  - 解碼明確與未提供的疫情等級。
  - 收藏地區跨不同疫情持久化。
  - ViewModel 收藏地區篩選。
  - 通知追蹤只回傳收藏地區且尚未看過的新疫情。
- 5 項 UI tests 全部通過，0 failures：
  - 搜尋與警示等級篩選。
  - 列表進入詳細頁。
  - 切換至地圖頁。
  - 從詳細頁收藏地區並於列表篩選。
  - 通知 opt-in 控制顯示正常。
- Smoke test 確認 app 可安裝、啟動並載入 CDC 資料；列表、搜尋列、篩選器與 tab bar 顯示正常，未發生 crash。
- `project.pbxproj`、`Info.plist` 與 `git diff --check` 驗證通過。
- 本機簽章可從 ignored 的 `Signing.local.xcconfig` 解析，commit 中沒有個人 Team ID。

## 已知限制

- UI tests 已覆蓋搜尋、篩選、收藏、詳細頁與地圖 tab；地圖 marker／callout、通知權限提示與離線操作仍需人工確認。
- Simulator 日誌出現 MapKit 定位與系統快取警告，但沒有 app crash 或程式層錯誤。
- 本機沒有 iPhone 16 Simulator，因此本次使用 iPhone 15／iOS 17.5；CI 仍使用 README 與 workflow 指定的 iPhone 16。

## 下一步

1. 推送 `main`，確認 GitHub Actions 通過。
2. 人工確認地圖 marker／callout、通知權限提示與離線模式。
3. 若需要完全即時通知，設計後端定期抓取 CDC 資料與 APNs 推播服務。
