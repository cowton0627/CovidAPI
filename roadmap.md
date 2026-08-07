# CovidAPI Roadmap

## 目前狀態

更新日期：2026-08-07

資料層重構、離線支援、地圖效能、UI tests、無障礙、未分級說明、地區收藏與 app 內新疫情通知均已完成。CI Simulator 建立流程也已修正；本機 `main` 與 `origin/main` 同步。

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
- 修正 GitHub Actions 在 runner 沒有預建 Simulator 時找不到 `iPhone 16` 的問題：workflow 會選擇最新可用的 iOS runtime、建立並啟動專用 Simulator，再以 UUID 執行測試。
- 新增地圖 marker／callout／詳細頁導覽與離線快取顯示 UI tests，並以固定座標 fixture 避免 CI 依賴 geocoding 網路。
- 將首頁疫情等級篩選器移到列表的固定 section header，避免 navigation bar 空間不足導致「未分級」截斷。
- 新增通知系統權限 UI test，驗證首次授權後 app 會切換為通知已啟用狀態。
- 新增收藏地區管理頁：依地區整合最新疫情與筆數，支援進入詳細頁與左滑移除。
- 首頁星號改為收藏選單，集中提供「只顯示收藏地區」與「管理收藏地區」。
- 詳細頁新增系統分享表單，可分享疫情等級、發布日、描述與 CDC 資料來源。
- 地圖頁新增疫情等級篩選，與列表共用同一套等級判定及無資料停用規則。
- 詳細頁新增「在地圖查看」，會切換地圖 tab、恢復全部篩選並定位開啟對應 marker。
- 本機通知加入疫情識別資訊，點擊後可直接開啟對應詳細頁，前景使用期間也會顯示橫幅。
- 地圖加入收藏選單，可只顯示收藏地區或直接進入收藏管理頁；收藏異動會即時同步 markers。
- 地圖加入「顯示全部疫情標記」，可在單點定位或手動移動後重新框選目前篩選結果。
- GitHub Actions checkout 升級至 Node.js 24 的 v6，並將 workflow token 權限限制為唯讀 repository content。
- 地圖底部新增資料來源與更新時間，使用快取時會明確標示「離線資料」。
- 通知權限遭拒時，提示可直接前往 App 系統設定重新開啟。

## 驗證結果

- iPhone 15、iOS 17.5 Simulator build 成功。
- 13 項單元測試全部通過，0 failures：
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
  - 通知 payload 可正確保留並還原疫情識別碼。
- 17 項 UI tests 全部通過，0 failures：
  - 搜尋與警示等級篩選。
  - 列表進入詳細頁。
  - 切換至地圖頁。
  - 從詳細頁收藏地區並於列表篩選。
  - 通知 opt-in 控制顯示正常。
  - 通知系統授權提示可允許，授權後 app 狀態正確更新。
  - 地圖 marker 可開啟 callout，callout 內容與詳細頁導覽正常。
  - 網路失敗時仍會顯示快取資料與「離線資料」來源標示。
  - 可進入收藏管理頁、左滑移除地區並顯示空狀態。
  - 詳細頁可開啟 iOS 系統分享表單。
  - 地圖可依警示等級篩選 markers。
  - 可從列表詳細頁切換至地圖，定位並開啟對應 marker callout。
  - 通知路由可清除既有篩選並直接開啟對應疫情詳細頁。
  - 地圖可只顯示收藏地區，並即時移除非收藏 markers。
  - 從詳細頁定位單一疫情後，可重新框選並看到全部 markers。
  - 離線時列表與地圖皆會顯示快取資料來源及更新時間。
  - 通知權限遭拒時會顯示取消與前往設定選項。
- Smoke test 確認 app 可安裝、啟動並載入 CDC 資料；列表、搜尋列、篩選器與 tab bar 顯示正常，未發生 crash。
- `project.pbxproj`、`Info.plist` 與 `git diff --check` 驗證通過。
- GitHub Actions 不再出現 `actions/checkout@v4` 的 Node.js 20 淘汰警告。
- 本機簽章可從 ignored 的 `Signing.local.xcconfig` 解析，commit 中沒有個人 Team ID。
- CI 修正 commit `08b1623` 已推送；GitHub Actions run `30894732585` 的 Simulator 建立、build 與 test 均成功。

## 已知限制

- UI tests 已覆蓋搜尋、篩選、收藏、通知系統授權、詳細頁、地圖 marker／callout 與離線快取。
- Simulator 日誌出現 MapKit 定位與系統快取警告，但沒有 app crash 或程式層錯誤。
- 本機沒有 iPhone 16 Simulator，因此本機驗證使用 iPhone 15／iOS 17.5；CI 會自行建立 iPhone 16 Simulator，不再依賴 runner 預建裝置。

## 下一步

1. 若需要完全即時通知，設計後端定期抓取 CDC 資料與 APNs 推播服務。
