---
theme: penguin
css: ./style.css
title: HPC final report
layout: intro
transition: slide-up
---

<div class="flex items-end gap-0">
  <p class="text-base text-gray-500">跑的飛快</p>
  <img src="./pics/tiger.gif" class="w-80 top-0 right-0" />
</div>

## HPC 期末報告

# 全局繞線最佳化問題

Group 11

---
transition: slide-up
---

# 題目介紹：VLSI 全局繞線問題

- **Global Routing** 是晶片實體設計中的關鍵最佳化問題
- 在容量有限的網格上繞線，須同時滿足：
  1. 連接所有線網端點
  2. 最小化繞線長度（Wirelength）
  3. 避免繞線壅塞（Overflow = 0）
- 研究能帶來的幫助
  - EDA（電子設計自動化工具）實體設計流程中會反覆執行
  - Runtime 直接影響設計疊代速度
  - 微小加速也能產生顯著的整體效果

---
transition: slide-up
---

# 研究目標

- 比較方式
  - 使用 NTHU-Route 2.0 作為原始碼基準
- 測試集：12 個指定的 ISPD08 基準設計
  - adaptec 1-5
  - bigblue 1-3
  - newblue 1,2,5,6

---
transition: slide-up
---

# 評估指標

| 指標 | 說明 |
|------|------|
| **Runtime** | 執行時間（秒）|
| **Correctness** | 是否所有 edge 都滿足容量限制 |
| **Wirelength** | 總繞線長度 |
| **Overflow** | 超出容量的 edge 總數 |

---
transition: slide-up
---

# 原始 NTHU-Route 基準

**測試條件：**
- 16 vCPU、2x Tesla V100-SXM2-32GB
- Apptainer 容器、Lab2 驗證器
- 環境變數未設定

---
transition: slide-up
---

# 基準效能

| 範圍 | 測資數 | Runtime | 合法率 |
|------|--------|---------|--------|
| **全 12 測資** | 12 | **12295.6s** | 7/12 |
| **原合法** | 7 | **6853.4s** | 7/7 |
| **原超載** | 5 | **5442.2s** | 0/5 |

---
transition: slide-up
---

# 基準效能

- 合法的 7 個測資：  
  - adaptec 1,3,4,5
  - bigblue 1,2,6
- 檢查工具鏈
  - **Lab2 Python Checker**：主要指標計算
  - **eval2008.pl**：備用驗證
  - **Metrics**：wirelength, overflow, max-OF

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 為什麼不能直接加 OpenMP？

---
transition: slide-up
---

# 曾嘗試但不採用的方法

- 將 OpenMP 掃描作為最終宣稱
  - 實測僅 1.03x
- Conflict-aware 批次處理
  - CPU 使用率高
  - 因 route order 變動反而更慢
- 將 CUDA 作為最終路徑
  - 子 kernel 很快，但 P2P 效能被 CPU 循序流程切碎，GPU 使用率 < 0.2%
- 嚴格合法 maze
  - 可保證不超載，但會變慢 2.5-6x

---
transition: slide-up
---

## Routing Pipeline 與平行化分析

| 階段 | 運作 | 平行性 |
|------|------|--------|
| **1. 輸入/樹狀結構建立** | 讀取 .gr、FLUTE | 可部分 |
| **2. 壅塞分析** | 掃描 edges、計算 overflow | YES |
| **3. P2 修復** | Rip-up/reroute | NO |
| **4. P3 後處理** | 候選修復 | 有限 |
| **5. 層級分配** | 2D → 金屬層 | YES |
| **6. 輸出/驗證** | 檢查結果 | YES |

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 主要時間花費在 P2 的 sequential mutation loop，
# 直接加鎖會導致序列化。

---
transition: slide-up
---

# P2 修復的順序相依性

為什麼循序提交 (sequential commit) 是必須的？

```cpp
// pseudo code
for each two_pin_net in nets {
  // get current congestion status
  int old_cost = congestion_map[net.path];

  // remove old path
  congestion_map.remove(net.path);
  
  // find new path based on current status
  new_path = find_path(congestion_map);

  // config new path
  congestion_map.insert(new_path);
}

```
---
transition: slide-up
---

# 目前平行化的困難

1. **Shared state race**：多個執行緒修改同一個 congestion map
2. **Route order sensitive**：下一個 net 的成本相依於前面 net 的提交
3. **Net tree mutation**：不僅是 edge demand，樹狀結構本身也會改變

---
transition: slide-up
---

# Amdahl 定律分析

- 即使平行化了，效益也很有限（上限 < 1.04x）

<br>

$$S(N) = \frac{1}{(1 - P) + P / N}$$

- P：可平行化比例
- N：核心數

---
transition: slide-up
---

# 實測數據

| 基準 | 可平行範圍 | P | S(12) | S(∞) |
| --- | --- | --- | --- | --- |
| adaptec1 | scan/reduction | 0.0285% | 1.00026x | 1.00029x |
| newblue2 | 寬鬆上限 | ≤0.7574% | ≤1.0070x | ≤1.0076x |
| adaptec3 | 寬鬆上限 | ≤0.1979% | ≤1.0018x | ≤1.0020x |

---
transition: slide-up
---

# 從實測加速反推

- **newblue2**: 65.6s → 63.6s = 1.032x
  - P ≈ 3.42%
- **adaptec3**: 491.5s → 485.3s = 1.013x
  - P ≈ 1.37%

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 直接平行化當前的 scan/reduction
# 不足以獲得明顯的端到端加速。

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 最佳化方向
<h1 style="font-size: 56px">不靠平行化</h1>

---
transition: slide-up
---

## 1. Net-Guided Fast Layer

- **問題：** 原始快速層級分配過於貪婪，導致 WL ↑↑
- **解決：** 讓同一個線網優先選擇一致、較低且合法的金屬層
- **效果：** 維持加速，同時控制 WL 的增長
- **環境變數：**
  - NTHU_FAST_GREEDY_LAYER=1
  - NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
  - NTHU_NET_GUIDED_LOW_LAYER_FIRST=1

```cpp
if (std::getenv("NTHU_FAST_GREEDY_LAYER_NET_GUIDED") != nullptr) {
    fast_net_guided_layer_assignment();  // fast + net continuity
} else {
    fast_greedy_layer_assignment(); // too greedy
}

```

---
transition: slide-up
---

## 2. Adaptive Legal Repair

- **問題：** 固定預算對所有測資來說可能過重或過輕
- **解決：** 先執行短修復，再根據 overflow 狀態動態調整
- **效果：** 避免在簡單測資上浪費時間，同時也不放棄困難測資
- **邏輯：**
  1. 先執行 NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10 次
  2. 檢查 overflow 狀態
  3. 若仍超載 > 200，提升至 NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
  4. 若很小 < 50，則限制額外的修復
- **效果：** 讓 hard case 多修復，easy case 少修復

---
transition: slide-up
---

## 3. High-Overflow P2 Budget

- **問題：** overflow 很高時，固定的疊代次數不足
- **解決：** 偵測到高 overflow 後，將 P2 最大疊代次數提升至 24
- **效果：** 針對性加強修復能力
- **環境變數：**
  - NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
  - NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
- **邏輯：** 若當前的 overflow > 200，則允許 P2 繼續執行最多 24 次疊代

---
transition: slide-up
---

## 4. Edge-Count Priority

- **問題：** 後處理對所有候選對象一視同仁
- **解決：** 優先修復會接觸到最多 overflow edge 的線網
- **效果：** 將有限的修復資源集中在最高效的地方
- **方法：** 後處理候選排序基於：
  1. 觸及的 overflow edges 數量
  2. 最大 overflow 值
  3. 總 overflow
- **環境變數：**
  - NTHU_POST_SORT_MODE=edge_count
- **效益：** 快速聚焦優先級，避免在不重要的候選對象上浪費時間

---
transition: slide-up
---

# 不靠多核心的理由

- 多核心與 GPU 難以被有效利用

| 方向 | 實測結果 | 結論 |
| --- | --- | --- |
| OpenMP scan/reduction | 1.03x | 正確但不是瓶頸 |
| 12-thread 繞線 | 65.6s → 63.6s | 執行緒已啟動，但主迴圈仍近似單核心運作 |
| Conflict-aware 批次處理 | 比預設更慢 | 繞線順序 (Route order) 變動的成本大於效益 |

<style>
table {
  font-size: 20px;
}
</style>

---
transition: slide-up
---

# GPU 嘗試結果

| 配置 | Runtime | GPU Util | 結論 |
| --- | --- | --- | --- |
| 單 GPU scorer | ~195s | <0.2% avg | Work unit 太小 |
| 雙 GPU | 191-200s | <0.2% avg | GPU1 基本上未使用 |

---
transition: slide-up
---

# 推測原因

- GPU 和多核心的工作被 CPU sequential routing 流程切碎
  - 不僅僅是問題可平行化比例太小
  - 是 GPU 無法與 CPU 進行非同步運作

---
transition: slide-up
---

# 最終結果比較

- **合法率：** 從 7/12 → 10/12
  - bigblue2 和 newblue1 雖有少量的殘留超載，但已大幅改善
- **加速倍數：** 1.29x ~ 1.69x
- **WL 控制：** 平均 1.158x，最差 1.284x

| 範圍 | 原始 (s) | 最佳化後 (s) | 加速 | 合法率 | WL 比 |
| --- | --- | --- | --- | --- | --- |
| **全 12 測資** | 12295.6 | 9501.3 | **1.29x** | 10/12 | 1.158 avg |
| **原合法 7 個** | 6853.4 | 4061.9 | **1.69x** | 7/7 | 1.118 avg |

---
transition: slide-up
---

### 各測資比較結果

| 測資 | 原本合法 | 原始 (s) | 最佳化後 (s) | 加速 | 超載 |
| --- | --- | --- | --- | --- | --- |
| adaptec1 | Y | 441.96 | 356.41 | **1.24x** | 0/0 |
| adaptec2 | N | 173.99 | 292.93 | 0.59x | 0/0 |
| adaptec3 | Y | 479.19 | 456.88 | **1.05x** | 0/0 |
| adaptec4 | Y | 130.67 | 125.64 | **1.04x** | 0/0 |
| adaptec5 | Y | 1240.59 | 857.27 | **1.45x** | 0/0 |
| bigblue1 | Y | 1206.31 | 752.41 | **1.60x** | 0/0 |
| bigblue2 | N | 1020.14 | 1084.25 | 0.94x | 68/2 |
| bigblue3 | N | 907.88 | 887.28 | **1.02x** | 0/0 |
| newblue1 | N | 1043.27 | 1106.59 | 0.94x | 98/2 |
| newblue2 | Y | 76.52 | 57.22 | **1.34x** | 0/0 |
| newblue5 | N | 2296.88 | 1862.60 | **1.23x** | 0/0 |
| newblue6 | Y | 3278.21 | 1304.92 | **2.51x** | 0/0 |

<style>
table th, table td {
  font-size: 18px;
  padding-top: 0.2rem;
  padding-bottom: 0.2rem;
}
</style>

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 策略與演算法的選擇比執行緒數量更重要

---
transition: slide-up
---

# 未來展望：多核心優化方向

- Read-only snapshot
- Batch proposal generation
- Deterministic serial commit
