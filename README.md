# CovidAPI

iOS app 練習作品，串接行政院疾管署（CDC）旅遊疫情建議 Open Data JSON，將世界各地疫情警告條列展示，並以地圖視覺化標註各地危險等級。

## 功能

### 列表頁
- 從 CDC `TravelEpidemic/ExportJSON` 解析疫情資料，依時序條列展示
- 下拉重新整理（pull-to-refresh），即時更新資料
- 點擊條目進入詳細頁
- 採 Dynamic Type，字體會跟著系統設定縮放

<p align="center">
  <img src="screenshots/list.png" width="280" alt="列表頁">
</p>

### 詳細頁
- 顯示完整疫情描述，內容過長可捲動
- 標題置於 navigation bar，內文上方標註發布日
- 可收藏或取消收藏該疫情地區；收藏會套用到同地區後續的其他疫情
- 可透過 iOS 系統分享表單分享疫情等級、發布日、描述與 CDC 資料來源
- 可點選「在地圖查看」切換至地圖頁，自動定位並開啟該疫情 marker 的 callout

<p align="center">
  <img src="screenshots/detail.png" width="280" alt="詳細頁">
</p>

### 地圖頁
- 依等級（第一 / 二 / 三級）以不同顏色標註 marker
  - 🟡 第一級 注意
  - 🟠 第二級 警示
  - 🔴 第三級 警告
  - ⚪ 未分類
- 啟動時請求 When-In-Use 位置權限，自動將地圖聚焦使用者周遭區域
- 點擊 marker 顯示自訂 callout：等級（分色）、發布日期、描述前段
- callout 右側 ⓘ 可進入詳細頁
- 可依第一、二、三級與未分級篩選 markers，沒有資料的等級會自動停用
- 可只顯示收藏地區，或從地圖直接進入收藏管理頁

<p align="center">
  <img src="screenshots/map.png" width="280" alt="地圖頁">
  <img src="screenshots/callout.png" width="280" alt="地圖 callout">
</p>

## 技術

- **語言 / UI**：Swift 5、UIKit、Storyboard
- **資料**：`URLSession` + `Codable` 解析 JSON、Repository 共用資料來源
- **離線支援**：JSON 磁碟快取，網路失敗時顯示最後一次成功資料
- **狀態管理**：Loading / Loaded / Empty / Error + Retry
- **列表**：`UITableView` + automatic row height + Dynamic Type
- **地圖**：`MapKit`（`MKMapView` / `MKMarkerAnnotationView` / 自訂 `detailCalloutAccessoryView`）
- **定位 / 地理編碼**：`CoreLocation`（`CLLocationManager`）+ `CLGeocoder`
- **架構**：`SceneDelegate` 程式建構 `UITabBarController`，列表與地圖兩個 navigation stack
- **品質**：XCTest 單元測試、XCUITest 核心流程測試、GitHub Actions 持續整合

## 架構

```text
ViewController
      ↓
List ViewModel
      ↓
EpidemicRepository
   ├── CDC API Client
   └── Disk Cache
```

列表與地圖共用 `EpidemicRepository`。Repository 會合併同時發出的更新請求，成功後寫入快取；網路失敗時則回傳最後一次成功資料，避免在離線或面試展示環境中出現空白畫面。

## 搜尋與篩選

- 可搜尋國家、地區、疾病名稱與描述
- 可依疾管署提供的第一、二、三級旅遊疫情等級篩選，沒有等級的資料歸入「未分級」
- 沒有資料的等級選項會停用；「未分級」不代表疫情不嚴重，只代表來源未提供等級
- 顯示資料來源及最後更新時間
- 列表左上角星號選單可切換為只顯示收藏地區，或進入收藏管理頁
- 收藏管理頁會依地區整合最新疫情與資料筆數，可查看詳細內容或左滑移除；收藏會保存在裝置上

## 收藏地區通知

- 列表右上角鈴鐺可主動開啟或關閉通知，首次開啟才會請求系統權限
- 開啟時只建立目前資料基準，不會把既有疫情當成新通知
- 之後 app 重新整理並發現收藏地區的新疫情時，會傳送本機通知
- 點擊通知會直接開啟對應疫情詳細頁；app 在前景時也會顯示通知橫幅
- 此版本沒有後端推播；app 長時間未開啟時不保證即時收到新疫情通知

## 測試

在 Xcode 選擇 `CovidAPI` scheme 後按 `⌘U`，或執行：

```sh
xcodebuild test \
  -project CovidAPI/CovidAPI.xcodeproj \
  -scheme CovidAPI \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

目前有 13 項單元測試，涵蓋疫情等級判定、疾管署等級解碼、API 成功快取、離線 fallback、ViewModel 搜尋／篩選、收藏持久化、新疫情通知比對與 payload 路由、地名正規化與座標快取；另有 14 項 UI tests，涵蓋列表與地圖等級／收藏篩選、收藏管理、通知系統權限與 opt-in／點擊導覽、詳細頁導覽／分享／地圖定位、地圖 marker／callout 導覽及離線快取顯示。

## Roadmap

- [x] API / Repository / ViewModel 分層
- [x] Loading、Empty、Error 與 Retry
- [x] 離線快取與最後更新時間
- [x] 搜尋與警示等級篩選
- [x] 單元測試與 CI
- [x] 國家名稱正規化與座標快取
- [x] 地圖 marker clustering
- [x] 收藏地區
- [x] 收藏地區管理頁
- [x] 收藏地區的新疫情通知（app 更新資料時偵測）
- [x] UI tests 與 VoiceOver accessibility audit

## 資料來源

- 衛福部疾管署 旅遊疫情建議：<https://www.cdc.gov.tw/TravelEpidemic/ExportJSON>

## 開發環境

- Xcode 12.5+
- iOS 14.5+
- Swift 5

### 實機簽章

Simulator 與 CI 不需要設定 Apple Developer Team。若要在實機執行：

1. 複製 `CovidAPI/Config/Signing.local.xcconfig.example` 為 `Signing.local.xcconfig`
2. 將 `YOUR_TEAM_ID` 改成自己的 Apple Developer Team ID

本機簽章檔已加入 `.gitignore`，不會把個人 Team ID 提交到公開 repository。
