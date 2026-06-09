# Welcome to [Slidev](https://github.com/slidevjs/slidev)!

To start the slide show:

- `pnpm install`
- `pnpm run dev`
- visit <http://localhost:3030>

Edit the [slides.md](./slides.md) to see the changes.

Learn more about Slidev at the [documentation](https://sli.dev/).

# Unused/Unknown Slides

```md
---
transition: slide-up
---

# 與 Main Branch 同 CLI 比較

在相同的參數設定下，最佳化版本勝過原始版本

## 比較設定

* 相同的 CLI 參數：`--p2-init-box-size=5 --p2-box-expand-size=5`
* 原始版本 (`main`) 未設定環境變數
* 最佳化版本啟用全部策略

## 比較結果

| 指標 | Main | Current | 改善 |
| --- | --- | --- | --- |
| 總秒數 | 16441.3 | 9804.4 | ⬇️ 40% |
| 加速倍數 | 1.0x | 1.68x | - |
| **合法率** | 4/12 | **10/12** | ⬆️ 6 個 case |
| 總 overflow | 20851542 | 166 | ⬇️ 99.99% |

## 關鍵數字

即使在同樣繁重的參數下：

* Main 仍有 8 個測資超載
* Current 透過自適應策略，將合法率從 4/12 提升到 10/12
* 同時總時間還縮短了 40%

---
transition: slide-up
---

# 不能當作 Final 的快速結果

一些實驗雖然很快，但不能作為最終成果宣稱

## 三類快速但不可用的結果

| 類型 | 例子 | 為什麼不行 |
| --- | --- | --- |
| **品質敏感組合** | WL≤1.2 合法 7 portfolio: 1.96x | 多版本挑選每個 case 最好的結果，並非單一 router 的表現 |
| **Runtime frontier** | 全 12 測資 edge-count: 5.38x | 很快但合法覆蓋率僅 2/12 |
| **最快保護組合** | 全 12 測資 3.17x | 保護了原合法的 case，但 WL 偏大，且 hard case 仍有超載 |

## 診斷價值

這些實驗雖然不能當作 final claim，但告訴我們：

* **速度上限**：最多可以快到 5.38x（僅依靠 edge-count priority）
* **品質界限**：在保持原合法的 7 個 case 的前提下，約可達 1.75x
* **研究方向**：哪個最佳化方向最有潛力

## 結論

最終報告使用**同一套全局策略**的結果，不混合多個版本的最佳 pick。

---
transition: slide-up
---

# 診斷實驗

* **Bounded-length reroute** - 保留為 opt-in 但未啟用
* **CUDA scoring** - 保留程式碼，可選用但並非 final claim
```

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