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

- OpenMP 掃描作為最終宣稱
  - 實測僅 1.03x（邊界 scan/reduction）
  - 因為 route mutation loop 仍是主要時間
- Conflict-aware 批次處理
  - newblue2 從 65.6s 變成 80.3s（反而更慢）
  - Route order 改變增加迴圈數，效益不足
- CUDA 作為最終路徑
  - 子 kernel 33x ~ 38x，但整合後無法端到端加速
  - GPU 利用率 < 0.2% avg（CPU-GPU 通信限制）

---
transition: slide-up
---

# 曾嘗試但不採用的方法

- 嚴格合法 maze（overflow path 用 strict-capacity）
  - 可避免部分 overflow 但會 plateau，變慢 2.5x ~ 6x
- Bounded-length reroute 限制
  - adaptec2 慢 2.557x，adaptec4 慢 6.039x
  - WL 只有小幅改善，不符成本效益

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

為什麼 sequential commit 是必須的？

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

| 基準 | 執行緒 | Runtime (s) | 可平行比例 | 預期 S(12) |
| --- | --- | --- | --- | --- |
| newblue2 | 1 | 65.647 | ~99.4% 在 routing | 理論 S(12) ≤ 1.0003x |
| newblue2 | 12 | 63.587 | 啟動了 threads 但仍單核運作 | 實測 1.032x |
| adaptec3 | 1 | 491.501 | ~99.8% 在 routing | 理論 S(12) ≤ 0.0020x |
| adaptec3 | 12 | 485.315 | thread binding 不是瓶頸 | 實測 1.013x |

<style>
table {
  font-size: 20px;
}
</style>

---
layout: new-section
class: flex items-center justify-center h-full text-center
transition: slide-up
---

# 如果讓 GPU 上場呢？

---
transition: slide-up
---

## GPU 也無法有效加速

| 配置 | Runtime | GPU Util | 瓶頸分析 |
| --- | --- | --- | --- |
| 單 GPU CUDA scorer | ~195s | < 0.2% avg | Work unit 太小 |
| 雙 GPU visible | ~191s | < 0.2% avg | GPU1 基本未使用 |
| Standalone CUDA kernel | - | - | 33x ~ 38x（孤立時很快） |

- **Route mutation loop 是 strictly sequential**：修改 congestion map 時必須按順序提交
- **GPU work 被 CPU sequential flow 切碎**：小工作單位無法利用 GPU 的並行計算能力
- **CPU-GPU 通信瓶頸**：P2P 效能被 CPU 的循序程序餓住，無法達成非同步運作

<style>
table {
  font-size: 20px;
}
</style>

---
transition: slide-up
---

## GPU 單獨運作性能 vs 整合後

| 場景 | Runtime | GPU 利用率 | 子 kernel 時間 | 結論 |
| --- | --- | --- | --- | --- |
| adaptec3 單 GPU CUDA scorer | ~195s | 0.122% avg / 8% max | 1068ms | Integrated 無法達成 end-to-end 加速 |
| adaptec3 雙 GPU visible | ~191s | 0.158% avg / 8% max | 862ms | GPU1 幾乎未使用 |
| CUDA dogleg scoring (standalone) | - | - | 33x ~ 38x | 孤立 kernel 很快，但無法應用 |

- GPU 子 kernel 快（33x-38x），但整合 end-to-end 時受限於 CPU sequential flow

<style>
table {
  font-size: 20px;
}
</style>

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

## 1. Net-Guided Fast Layer Assignment

- **問題：** 原始 layer assignment 太慢；簡單的 fast greedy 會導致過多 layer change，WL 膨脹到 1.74x ~ 1.85x
- **解決：** 每個 net 估算 preferred layer，再讓 edge 盡量留在同一層或低層，只在無合法層時使用 congestion fallback
- **效果：** 保持快速同時控制 WL，適合原本合法的測資
- **加速幅度：** 1.05x ~ 1.24x（原合法測資）
- **WL 控制：** 平均 1.118x，最差 1.151x（原合法 7 測資）

```cpp
// environment variable
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
NTHU_NET_GUIDED_LAYER_PENALTY=0.02 // default
NTHU_NET_GUIDED_EDGE_CHANGE_PENALTY=0.35 // default
NTHU_NET_GUIDED_OVERFLOW_PENALTY=10000.0 // default
```

---
transition: slide-up
---

## 2. Adaptive Repair with Dynamic Budget

- **問題：** 固定的 P2/P3 預算對所有測資不適應；easy case 浪費時間，hard case 時間不足
- **解決：** 根據測量到的 overflow 狀態動態調整修復預算
  - 若 overflow = 0，停止修復
  - 若 overflow 小（< 50），只做短修復以節省時間
  - 若 overflow 大（> 200），升級到更高的 P2 疊代次數
- **加速幅度：** 1.29x ~ 1.69x（整體效果）

---
transition: slide-up
---

## 2. Adaptive Repair with Dynamic Budget

```cpp
// environment variable
// P2 repair
NTHU_ADAPTIVE_LEGAL_REPAIR=1               // adaptive toggle
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10        // short repair
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200 // high OF trigger
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24 // high OF max iter
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50   // small OF limit
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1   // small OF rounds
// P3 deep repair
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4  // init P3 iter
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66 // init box size
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122 // box increment
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24  // deep P3 iter
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80  // deep box size
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140  // deep box inc
```

---
transition: slide-up
---

## 3. CUDA-Accelerated Overflow Scorer

- **問題：** overflow 評分在每次修復迴圈中重複執行，成為 CPU 密集操作
- **解決：** 使用 CUDA kernel 平行加速 overflow 評分，在 maze 搜尋前篩選候選路徑
- **運作邏輯：** 用 GPU 快速評估 candidate 會否超載，減少無效的 maze 搜尋
- **加速幅度：** 0.8x ~ 1.1x（有限，整合層面受 CPU-GPU 通信瓶頸）
- **獨立 kernel 性能：** standalone 33x ~ 38x，但整合後 end-to-end 無法達成
- **限制和觀察：**
  - GPU 利用率低（< 0.2% avg）
  - CPU sequential routing loop 無法與 GPU 非同步運作
  - 需要 read-only snapshot + deterministic commit 才能有效利用

```cpp
// environment variable
NTHU_CUDA_SCORER=1 // enable CUDA scorer
NTHU_CUDA_BATCH_SIZE=512
```

<style>
ul {
  font-size: 21px;
}
</style>

---
transition: slide-up
---

## 4. Edge-Count Priority Sorting

- **問題：** 後處理對所有候選對象一視同仁，浪費時間在低效的修復
- **解決：** 優先修復會接觸到最多 overflow edge 的線網
- **排序基準優先級：**
  1. 觸及的 overflow edges 數量
  2. 最大 overflow 值
  3. 總 overflow
- **加速幅度：** 1.02x ~ 1.23x（非原合法測資效益更大）
- **效益：** 將有限的修復資源集中在最高效的地方，快速聚焦優先級

```cpp
// environment variable
NTHU_POST_SORT_MODE=edge_count
```

---
transition: slide-up
---

# 最終結果比較

- **合法率：** 從 7/12 → 10/12
  - bigblue2 和 newblue1 雖有殘留超載，但已大幅改善
  - 原本合法的 7 個測資仍然 100% 保持合法
- **加速幅度：** 原合法 7 測資 1.69x，全 12 測資 1.29x
- **WL 控制：** 平均 1.158x，最差 1.284x（可接受）

| 範圍 | 原始 (s) | 最佳化後 (s) | 加速 | 合法率 | WL 比 |
| --- | --- | --- | --- | --- | --- |
| **全 12 測資** | 12295.6 | 9501.3 | **1.29x** | 10/12 | 1.158 avg |
| **原合法 7 個** | 6853.4 | 4061.9 | **1.69x** | 7/7 | 1.118 avg |

---
transition: slide-up
---

# 完整命令列參數

```bash
NTHU_FAST_GREEDY_LAYER=1 \
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1 \
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1 \
NTHU_ADAPTIVE_LEGAL_REPAIR=1 \
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10 \
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200 \
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24 \
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50 \
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1 \
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4 \
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66 \
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122 \
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24 \
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80 \
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140 \
NTHU_POST_SORT_MODE=edge_count \
./NthuRoute --p2-init-box-size=5 --p2-box-expand-size=5 \
  --p2-max-iteration=6 --overflow-threshold=1800 \
  --p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140
```

---
transition: slide-up
---

### 各測資詳細比較結果

| 測資 | 原本合法 | 原始 (s) | 最佳化後 (s) | 加速 | 原 overflow | 最終 overflow |
| --- | --- | --- | --- | --- | --- | --- |
| adaptec1 | ✓ | 441.96 | 356.41 | **1.24x** | 0/0 | 0/0 |
| adaptec2 | ✗ | 173.99 | 292.93 | 0.59x | ? | **0/0** ✓ |
| adaptec3 | ✓ | 479.19 | 456.88 | **1.05x** | 0/0 | 0/0 |
| adaptec4 | ✓ | 130.67 | 125.64 | **1.04x** | 0/0 | 0/0 |
| adaptec5 | ✓ | 1240.59 | 857.27 | **1.45x** | 0/0 | 0/0 |
| bigblue1 | ✓ | 1206.31 | 752.41 | **1.60x** | 0/0 | 0/0 |
| bigblue2 | ✗ | 1020.14 | 1084.25 | 0.94x | 314/4 | **68/2** ↓81% |
| bigblue3 | ✗ | 907.88 | 887.28 | **1.02x** | 42/4 | **0/0** ✓ |
| newblue1 | ✗ | 1043.27 | 1106.59 | 0.94x | 504/4 | **98/2** ↓81% |
| newblue2 | ✓ | 76.52 | 57.22 | **1.34x** | 0/0 | 0/0 |
| newblue5 | ✗ | 2296.88 | 1862.60 | **1.23x** | 94/4 | **0/0** ✓ |
| newblue6 | ✓ | 3278.21 | 1304.92 | **2.51x** | 0/0 | 0/0 |

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

# 未來展望：多核心與 GPU 優化方向

要達到 2x 以上的進一步加速，需要重新架構 routing pipeline

- **Read-only Congestion Snapshot**：避免 race condition
- **Batch Proposal Generation**：並行生成多個候選路徑
- **Deterministic Serial Commit**：生成時平行化，但要保證正確性
- **Async GPU Batching**：減少 CPU-GPU 通信開銷

**目前的侷限：** 改進空間有限，因為 sequential mutation loop 是硬性 constraint
