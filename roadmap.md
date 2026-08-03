# CovidAPI Roadmap

## 目前狀態

更新日期：2026-08-03

資料層重構、離線支援與基礎品質檢查已完成，紀錄於 commit `2dc3431`（`重構資料層並新增離線快取與測試`）。國家名稱正規化與座標快取亦已實作、尚未提交。目前本機 `main` 比 `origin/main` 領先一個 commit，尚未推送。

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

## 驗證結果

- iPhone 15、iOS 17.5 Simulator build 成功。
- 7 項單元測試全部通過，0 failures：
  - 疫情等級判定採用最高匹配等級。
  - API 成功後寫入快取。
  - 網路失敗時使用磁碟快取。
  - 網路失敗時將記憶體 fallback 標示為離線資料。
  - ViewModel 搜尋與等級篩選。
  - 國家名稱別名與警示文字正規化。
  - 座標快取跨 instance 持久化。
- Smoke test 確認 app 可安裝、啟動並載入 CDC 資料；列表、搜尋列、篩選器與 tab bar 顯示正常，未發生 crash。
- `project.pbxproj`、`Info.plist` 與 `git diff --check` 驗證通過。
- 本機簽章可從 ignored 的 `Signing.local.xcconfig` 解析，commit 中沒有個人 Team ID。

## 已知限制

- 自動化 smoke test 無法可靠操作 Simulator 內的 UIKit 控制項；搜尋輸入、篩選切換、詳細頁、地圖 marker 與 callout 仍需人工確認。
- Simulator 日誌出現 MapKit 定位與系統快取警告，但沒有 app crash 或程式層錯誤。
- 本機沒有 iPhone 16 Simulator，因此本次使用 iPhone 15／iOS 17.5；CI 仍使用 README 與 workflow 指定的 iPhone 16。

## 下一步

1. 人工完成搜尋、篩選、詳細頁、地圖 marker／callout 與離線模式操作檢查。
2. 推送 `main`，確認 GitHub Actions 通過。
3. 補充 UI tests 與 VoiceOver accessibility audit。
