# NTHU-Route 優化方法、結果與檢討報告

Date: 2026-06-06
Branch: `vm-fastest-benchmark-guard`

## 摘要

本專案以 `external/nthu-route-original` 作為不可修改 baseline，主要修改
`external/nthu-route`。所有正式 benchmark 都在 VM
`ubuntu@202.5.251.114` 上執行，環境為 16 vCPU、2x Tesla V100-SXM2-32GB、
Apptainer `router.sif`、Lab2 verifier。測資主軸為 requested 12:
`adaptec1-5`, `bigblue1-3`, `newblue1`, `newblue2`, `newblue5`, `newblue6`。

目前最可辯護的單一策略不是最快 frontier，而是:

- net-guided low-layer fast layer assignment,
- adaptive legal repair,
- high-overflow P2 budget,
- edge-count post candidate ordering,
- bounded-length reroute 實驗保留為 opt-in 但 final 關閉。

最新完整 recheck 結果:

| Scope | Original s | Current s | Speedup | WL ratio | Legality |
| --- | ---: | ---: | ---: | --- | --- |
| requested12 latest recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, total overflow 166 |
| original-legal 7 latest recheck | 6853.445 | 4061.935 | 1.687x | avg 1.118, worst 1.151 | 7/7 legal |
| earlier clean selected run | 12295.597 | 9144.395 | 1.345x | avg 1.158, worst 1.284 | 10/12 legal, total overflow 166 |

這代表目前策略能保證 original 原本合法的 7 筆仍合法，並大幅降低 original
overflow cases 的 overflow，但 `bigblue2` 與 `newblue1` 仍有小 residual
overflow。

## 1. 原本程式的效能 Pitfalls

### 1.1 Rip-up and Reroute 是 sequential mutation loop

原始 NTHU-Route 的主要時間不是單純 grid scan，而是在 two-pin rip-up and
reroute。`RangeRouter::range_router()` 會對 shared congestion map 做:

1. 檢查舊 path 是否 overflow。
2. 從 congestion map 移除舊 two-pin path。
3. 用目前 congestion 找 replacement path。
4. 把新 path 插回 congestion map。

這個流程有順序相依與 shared mutable state。直接加 OpenMP 會造成 route order
改變、data race 或更多 fallback。VM profiling 也驗證這點:

| Benchmark | Threads | Seconds | Avg CPU | Key profile |
| --- | ---: | ---: | ---: | --- |
| newblue2 | 1 | 65.647 | 99.4% | `route_all` 99.2%, `specify_all_range` 99.0% of route_all |
| newblue2 | 12 | 63.587 | 103.1% | threads 有啟動，但仍近似單核心 |
| adaptec3 | 1 | 491.501 | 99.8% | `specify_all_range` dominates |
| adaptec3 | 12 | 485.315 | 101.8% | thread binding 不是瓶頸 |

結論: 原本程式最大的 pitfall 是 routing mutation loop 難以安全平行化，不是
OpenMP 沒開、thread 沒建立或 cache binding 設錯。

### 1.2 Fixed P2/P3 budget 不會依 congestion 狀態調整

原始 flow 使用固定 P2/P3 iteration 和 box size。某些測資會花很多時間修不太動
的 overflow，或太早進 layer assignment 導致 3D overflow 爆炸。

`main` under same CLI 的 `newblue5` 是最明顯例子:

| Case | Main s | Current s | Main OF/Max | Current OF/Max |
| --- | ---: | ---: | ---: | ---: |
| newblue5 | 4971.193 | 1845.377 | 6267278/4 | 0/0 |

Main 花了更久但仍非法，代表固定 post-processing budget 對 hard cases 不夠穩。

### 1.3 Layer assignment 是速度與 WL 的 trade-off

原本較完整的 layer assignment 品質較穩，但時間成本高。早期 fast greedy layer
assignment 大幅加速，但因每條 edge 獨立選 layer，容易產生過多 layer change 和 via，
使 WL ratio 上升到約 1.7x 到 1.9x。

### 1.4 Post-processing candidate 處理過多或過少都會失衡

原始 post-processing 會花大量時間在候選 reroute 上。若 aggressively prune，
runtime 會很好，但容易留下 overflow。這就是 edge-count frontier 可達 5x 以上，
但 legal coverage 很差的原因。

### 1.5 CUDA work granularity 太小

CUDA scorer 在 standalone kernel 可達 33x 到 38x，但整合進 router 後，GPU
utilization 幾乎為零。`adaptec3` 單 GPU costed path:

| Scenario | Seconds | GPU0 avg/max util | `cuda_maze_ms` | Interpretation |
| --- | ---: | ---: | ---: | --- |
| single_costed | 194.907 | 0.122% / 8% | 1068.330 ms | CUDA 子工作約 1 秒，總 runtime 約 195 秒 |
| dual_visible_costed | 191.291 | 0.158% / 8% | 861.536 ms | GPU1 幾乎沒用到 |

結論: 目前 CUDA 問題不是 GPU 不夠，而是 CPU sequential routing 之間夾著太小、
太分散的 GPU calls。

## 2. 優化手段與結果總表

| 方法 | 核心想法 | 代表 commit/report | 速度 | WL | 結果 |
| --- | --- | --- | ---: | --- | --- |
| OpenMP analysis kernels | 平行化 congestion scan、overflow/WL reduction。 | `../docs/21-vm-multicore-utilization-log.md` | 12-case 約 1.03x | 約 1.000x | 正確但太小。 |
| Conflict-aware multicore prototype | 嘗試把不衝突 two-pin reroute batch parallel。 | `db540bb`, `a5465c9`, `e648e19` | newblue2 default 65.739s, prototype best 80.255s | 類似 | CPU 提高但更慢。 |
| Fast greedy layer assignment | 取代 expensive layer assignment。 | early docs | 12-case 1.59x | legal avg 1.743, worst 1.851 | 快但 WL 太高。 |
| Net-guided low-layer assignment | 每個 net 有 preferred layer，優先低合法 layer。 | `7300fb7`, `53b1965` | legal7 WL<=1.2: 1.961x | avg 1.125, worst 1.163 | WL 控制有效。 |
| P2/P3 budget tuning | 減少 routing effort。 | early docs | fastest guarded 12-case 3.17x | legal avg 1.767, worst 1.862 | 速度強但 WL 高。 |
| Edge-count post-processing | overflow edge count 優先，限制 reroute。 | `NTHU_POST_SORT_MODE=edge_count` | 12-case 5.38x frontier | 約 1.8x+ | 多數 illegal，只能當 frontier。 |
| CUDA scoring | GPU costed maze / dogleg candidate scoring。 | CUDA logs | standalone 33x-38x, integrated A3 2.780x | A3 約 1.706x | 子核心快，end-to-end 不穩。 |
| Overall adaptive repair | 不依測資名，根據 overflow 決定是否 repair。 | `db48d4a` 到 `b982db4` | legal7 1.771x | avg 1.116, worst 1.151 | 正確但 speed 不夠。 |
| High-overflow P2 budget | overflow 高時 P2 max 提升到 24，small overflow 則 cap。 | `67c56da`, `d1b7584` | requested12 1.345x | avg 1.158, worst 1.284 | 目前 final family。 |
| Strict legal maze | overflow path 嘗試 strict-capacity maze。 | `643aff2`, `9c10d52` | 無採用速度勝利 | 目標是低 WL | plateau 或 crash，拒用。 |
| Layer penalty probe | 調 layer penalty 降 WL。 | `7499b1f` | 4-case 3104.704s vs 3106.744s | 無變化 | 負結果。 |
| Bounded-length guard | 限制 maze detour 長度。 | `de271c9`, `5b0fea5` | A2 慢 2.557x, A4 慢 6.039x | WL 小幅下降 | 正確但太慢，final 關閉。 |

## 2.1 OpenMP Analysis Kernels

### 方法

把本來可資料平行的區塊加上 OpenMP，例如 congestion cost update、
max overflow、wirelength reduction、post-processing candidate counter。

### 實作重點

代表邏輯位於 `Congestion.cpp` 與 post-processing counters。這類 loop 是
edge-level scan，可平行但不是主 runtime。

### 結果

- `nthu_openmp_t4` requested12: `11917.582s` vs original `12295.597s`，
  speedup `1.03x`。
- adaptec1-3: `1.009x`。
- WL 約 `1.000x`，沒有品質 regression。

### 判斷

這是正確但低影響的優化。profiling 顯示 route mutation 仍是 dominant path，
因此繼續調 `OMP_NUM_THREADS` 或 binding 意義不大。

## 2.2 Conflict-Aware Multicore Reroute Prototype

### 方法

嘗試把 two-pin reroute 分批，讓 conflict box 不重疊的 candidate 在平行區產生
proposal，再用 serial maze fallback 保 correctness。

### 結果

| Version | newblue2 seconds | Avg CPU | Legal | Comment |
| --- | ---: | ---: | --- | --- |
| default | 65.739 | 104% | yes | baseline |
| direct parallel maze `db540bb` | 2609.637 | higher | no | first iteration 後 abort |
| serial maze fallback `a5465c9` | 136.985 | 270% | yes | 慢很多 |
| capped candidates `e648e19` | 80.255 | 162% | yes | 仍慢於 default |

### 判斷

利用率可以拉高，但 route order 改變會增加 iteration，且 maze fallback 仍吃時間。
此方向要成功，需要 read-only congestion snapshot + deterministic commit，而不是
直接平行改 congestion map。

## 2.3 Fast Greedy Layer Assignment

### 方法

原本 layer assignment 較完整但慢。fast greedy 直接對 edge 選 projected demand
較低的 layer，以降低 layer assignment runtime。

### 實作概念

入口 dispatch:

```cpp
if (std::getenv("NTHU_FAST_GREEDY_LAYER") != nullptr) {
    if (std::getenv("NTHU_FAST_GREEDY_LAYER_NET_GUIDED") != nullptr) {
        fast_net_guided_layer_assignment();
    } else {
        fast_greedy_layer_assignment();
    }
}
```

位置: `external/nthu-route/src/router/Layerassignment.cpp:891`

### 結果

- requested12 early `nthu_fast_layer`: `7729.719s`, speedup `1.59x`。
- legal coverage `8/12`。
- original-legal avg WL ratio `1.743`，worst `1.851`。

### 判斷

這是第一個有效的粗粒度 speedup，但 WL 太高，不能作為 final quality-sensitive
策略。

## 2.4 Net-Guided Low-Layer Fast Assignment

### 方法

針對 fast layer 的 WL 問題，改成每個 net 先估 preferred layer，再讓 edge
盡量留在同一層或低層。若低層不合法，才用 congestion fallback。

### 實作重點

```cpp
const double net_layer_penalty = env_double("NTHU_NET_GUIDED_LAYER_PENALTY", 0.02);
const double edge_layer_change_penalty =
        env_double("NTHU_NET_GUIDED_EDGE_CHANGE_PENALTY", 0.35);
const double overflow_penalty = env_double("NTHU_NET_GUIDED_OVERFLOW_PENALTY", 10000.0);
const bool low_layer_first = std::getenv("NTHU_NET_GUIDED_LOW_LAYER_FIRST") != nullptr;
```

位置: `external/nthu-route/src/router/Layerassignment.cpp:527`

### 結果

| Scope | Speedup | Avg WL | Worst WL | Overflow |
| --- | ---: | ---: | ---: | --- |
| legal7 WL<=1.5 portfolio | 2.05x | 1.368 | 1.425 | 0/0 all |
| legal7 WL<=1.2 portfolio | 1.961x | 1.125 | 1.163 | 0/0 all |
| WL<=1.2 speed frontier | 3.585x | 1.138 | within 1.2 | total overflow 13642 |

### 判斷

這證明 WL 問題主要來自 layer continuity 和低層偏好，而不只是 routing budget。
但若要達到 2.8x 到 3.2x 且合法，仍需要更好的 overflow repair。

## 2.5 P2/P3 Budget Tuning 與 Edge-Count Post

### 方法

P2/P3 budget tuning 透過 CLI 控制 routing effort:

```text
--p2-init-box-size=5 --p2-box-expand-size=5
--p2-max-iteration=6 --overflow-threshold=1800
--p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140
```

Edge-count post 則優先處理穿過最多 overflow edges 的 candidate:

```cpp
} else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "edge_count") == 0) {
    std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
        if (a.overflow_edge_count != b.overflow_edge_count) {
            return a.overflow_edge_count > b.overflow_edge_count;
        }
        ...
    });
}
```

位置: `external/nthu-route/src/router/Post_processing.cpp:225`

### 結果

- P2/P3 budget best legal adaptec1: `2.118x`。
- fastest guarded requested12 portfolio: `3.17x`，但 original-legal avg/worst
  WL `1.767/1.862`。
- edge-count post requested12: `5.38x`，但 legal coverage 只有 `2/12`。

### 判斷

這兩個方向都證明 runtime 可以大幅下降，但如果 repair 過弱就會留下 overflow。
因此 final 只採用 edge-count 作為 candidate ordering 的一部分，不採用 aggressive
pruning frontier。

## 2.6 Adaptive Legal Repair 與 High-Overflow P2 Budget

### 方法

不根據 benchmark 名稱切策略，而是在 routing 後讀取 overflow 狀態:

- overflow 為 0 則停止。
- overflow 小則只補少量 P2，避免 over-repair。
- overflow 高於 trigger 則提高 P2 max iteration 到 24。
- 初始 P3 短，repair P3 深。

### 實作重點

```cpp
if (cur_overflow > trigger) {
    int adaptive_max_iter = std::max(routingparam.get_iteration_p2(),
            env_int("NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER", routingparam.get_iteration_p2()));
    const int high_overflow_trigger = env_int("NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER", 0);
    const int high_overflow_max_iter =
            env_int("NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER", adaptive_max_iter);
    if (high_overflow_trigger > 0 && cur_overflow >= high_overflow_trigger &&
            high_overflow_max_iter > adaptive_max_iter) {
        adaptive_max_iter = high_overflow_max_iter;
    }
    ...
}
```

位置: `external/nthu-route/src/router/Construct_2d_tree.cpp:841`

### 結果

| Scope | Original s | Current s | Speedup | WL | Legality |
| --- | ---: | ---: | ---: | --- | --- |
| legal7 clean report | 6853.445 | 3910.736 | 1.752x | avg 1.118, worst 1.151 | 7/7 legal |
| requested12 clean report | 12295.597 | 9144.395 | 1.345x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |
| latest requested12 recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |

### 判斷

這是目前最好的單一策略，沒有 hardcode 測資名稱。它保住 original legal cases，
也把 hard cases overflow 大幅壓低，但速度仍未達 2.8x。

## 2.7 CUDA Scoring

### 方法

把 costed maze / dogleg candidate scoring 交給 CUDA，測試 single GPU、
dual-visible GPU、dual-GPU preselect。

### 結果

| Scenario | Case | Seconds | GPU0 avg/max | GPU1 avg/max | Legal |
| --- | --- | ---: | ---: | ---: | --- |
| single_costed | adaptec3 | 194.907 | 0.122% / 8% | 0 / 0 | yes |
| dual_visible_costed | adaptec3 | 191.291 | 0.158% / 8% | 0 / 0 | yes |
| dual_multigpu_preselect | adaptec3 | 199.862 | 0.171% / 9% | 0 / 0 | yes |

Standalone scorer 可以 33x 到 38x，但 integrated end-to-end A3 最好 legal
約 `2.780x`，且不是 requested12 final。

### 判斷

目前 CUDA 是有用的子核心，但不是有效的 end-to-end optimization。未來要 batching
大量 candidate，否則 GPU 會被 CPU sequential flow 餓住。

## 2.8 Strict Legal Maze 與 Bounded-Length Reroute

### Strict Legal Maze

嘗試在 overflow path 使用 strict-capacity maze。結果可以避免部分 overflow，但
plateau 且慢；post-accept improvement 版本在 tree rebuild crash，因此 final 關閉。

### Bounded-Length Reroute

文獻上 bounded-length maze routing 很適合控制 WL，因此我們實作 opt-in guard。
第一版在 `Range_router` 外部 rollback，造成 tree state inconsistent，full12
`12/12 fail`。

修正後把長度上限傳入 `MM_mazeroute`，在 `adjust_twopin_element()` 前拒絕:

```cpp
trace_back_to_find_path_2d(sink_pos);
if (max_path_edges >= 0 && !element->path.empty() &&
        static_cast<int>(element->path.size()) - 1 > max_path_edges) {
    element->path.clear();
    find_path_flag = false;
    break;
}
adjust_twopin_element();
```

位置: `external/nthu-route/src/router/MM_mazeroute.cpp:373`

結果:

| Case | Final s | Safe bounded s | Time ratio | Final WL | Safe bounded WL | OF/Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| adaptec2 | 289.548 | 740.369 | 2.557x slower | 5759135 | 5750722 | 0/0 |
| adaptec4 | 129.473 | 781.975 | 6.039x slower | 13544728 | 13525365 | 0/0 |

安全版正確且 WL 小幅下降，但太慢，所以 final 關閉。這也說明真正要做的不是
「找到第一條 path 後超長就拒絕」，而是 maze search 本身要能繼續找 bounded
候選。

## 3. 未來方向與檢討

### 3.1 True Bounded-Length Maze Search

目前 safe guard 只是 reject 第一條過長 path，導致 repair 變慢。下一步應該在
maze search 內加入 length state 或 detour budget，讓搜尋偏向:

- `length <= manhattan * ratio + extra`
- overflow 降低優先
- 找不到 bounded legal path 時才逐步 relax

這比外部 rollback 安全，也更符合 NCTU-GR 的 bounded-length maze routing。

### 3.2 Connected Overflow Region Repair

剩餘問題集中在 `bigblue2` 和 `newblue1` 的小 residual overflow。固定 P3 對它們
效率低。應改為:

1. 從 overflow edges 建 connected components。
2. 找出碰到該 component 的 nets。
3. rip up 小批 nets。
4. 用 bounded proposals reroute。
5. 只接受 total overflow 下降且 WL 增幅受控的 batch。

### 3.3 Read-Only Snapshot + Deterministic Commit Parallelism

現有 parallel reroute 慢，是因為直接改 shared state 或產生太多無效 proposal。
未來多核方向應該:

- parallel 只做 proposal generation。
- proposal 使用 read-only congestion snapshot。
- commit 階段 deterministic serial，或只 commit non-overlap conflict sets。
- batch size 依 overflow region 動態調整。

### 3.4 Batched GPU Candidate Evaluation

CUDA 未來不應單次送小 box，而要收集大量 route boxes / dogleg candidates:

- contiguous cost arrays,
- one launch handles many boxes,
- CPU 只負責 commit 和 conflict resolution。

這樣才有機會把 GPU utilization 從接近 0 拉起來。

### 3.5 3D WL / Via-Aware Refinement

目前仍是 2D routing 後 layer assignment。FastRoute 4.0 與 CUGR 都顯示 via、
3D pattern、layer ordering 對 WL 和 routability 很重要。未來應加入:

- local layer move refinement,
- via-aware score,
- net continuity constraint,
- overflow-safe local layer repair。

## 4. 可能會有的問題

### Q1: 為什麼不直接用最快的 edge-count 結果？

因為它多數 illegal。requested12 可以到 `5.38x`，但 legal coverage 只有 `2/12`。
這只能當 runtime frontier，不能當合法 router 結果。

### Q2: 為什麼目前 speedup 沒有 2.8x 到 3.2x？

在 WL<=1.2 且 original-legal 全合法的條件下，legal7 最好是 `1.961x`。如果放寬
legality，WL<=1.2 frontier 可到 `3.585x`，但 overflow `13642`。瓶頸是 overflow
repair，而不是找不到快路徑。

### Q3: 為什麼不用多核心或雙 GPU？

OpenMP threads 有建立，但 routing mutation loop 是 sequential。CUDA kernel 本身快，
但 integrated GPU work 只佔總時間很小比例，GPU utilization 近零。雙 GPU 不改善
單 testcase latency。

### Q4: 為什麼 current 仍有 2 筆 illegal？

`bigblue2` 和 `newblue1` 是 original-overflow / hard cases，current 已把 overflow
降到 `68/2` 與 `98/2`，但尚未完全清掉。original-legal 7 筆已保證 `7/7` legal。

### Q5: 報告中的 portfolio 和 final one-strategy 有什麼差別？

早期 best-per-benchmark portfolio 用於診斷上限，例如 3.17x fastest guarded 或
2.05x WL<=1.5 legal7。final one-strategy 不能依測資名切換，只能根據 routing state
自適應。最終採用的是後者。

### Q6: Bounded-length guard 既然正確，為什麼不開？

安全版只是在第一條 path 太長時拒絕，沒有繼續找較短候選，因此會讓 repair
迭代變慢。A2/A4 雖 WL 小幅下降，但時間慢 2.557x 與 6.039x，所以 final 關閉。

### Q7: 實驗可重現性問題？

VM load、evaluator 時間與 output 大小會造成秒數小幅變動。因此報告同時保留 clean
selected run 與 latest recheck。所有正式數據都有 result root 記錄，且
`external/nthu-route-original` 保持 untouched。

## 5. 文獻探討

### 5.1 NTHU-Route 2.0

NTHU-Route 2.0 的重點是 history-based cost、congested-region ordering、
rip-up and reroute ordering 以及 implementation techniques。這直接支持我們的
adaptive repair 方向: 問題不只是單次最短路，而是何時、以什麼順序、對哪些 congested
regions 花 repair effort。

對照本專案:

- high-overflow P2 budget 對應「根據 congestion 狀態分配 effort」。
- edge-count candidate ordering 對應「congested region / candidate priority」。
- 剩餘 B2/N1 問題顯示還需要更細的 region-level repair。

來源:

- NTHU-Route 2.0 ICCAD paper:
  <https://www.cecs.uci.edu/~papers/iccad08/PDFs/Papers/05A.1.pdf>
- NTHU-Route 2.0 TCAD robust router:
  <https://www.researchgate.net/publication/224189190_NTHU-Route_20_A_robust_global_router_for_modern_designs>

### 5.2 NCTU-GR 2.0

NCTU-GR 2.0 提出 bounded-length maze routing、RSMT-aware routing 與
task-based collision-aware multithreading。文獻摘要指出其 parallel router 在 4-core
系統上對 overflow-free / hard-to-route cases 有平均 2.71x / 3.12x speedup，且 routing
quality 幾乎不變。

對照本專案:

- 我們的 naive / conflict-box parallel reroute 證明「只把 route loop 平行化」不夠。
- 我們的 bounded-length guard 證明限制 detour 的位置必須在 maze search 內部，而不是
  外部 rollback。
- 未來最合理方向是 NCTU-GR-style bounded search + collision-aware proposal commit。

來源:

- NCTU-GR 2.0 publication page:
  <https://scholar.nycu.edu.tw/zh/publications/nctu-gr-20-multithreaded-collision-aware-global-routing-with-boun/>
- NCTU-GR 2.0 PDF mirror used in prior review:
  <https://ir.lib.nycu.edu.tw/bitstream/11536/21646/1/000318163800005.pdf>

### 5.3 SPRoute

SPRoute 的觀點是 parallel global routing 需要 adaptive parallelism 與 negotiation，
不是固定把所有 nets 平行 reroute。這與本專案 profiling 一致: route order、conflict、
shared congestion state 會支配正確性和收斂速度。

對照本專案:

- OpenMP scan 不是主瓶頸。
- parallel proposal 要搭配 conflict control 和 deterministic commit。
- 當 livelock 或 overflow plateau 出現時，需要動態降低或改變 parallel granularity。

來源:

- SPRoute paper:
  <https://csl.yale.edu/~rajit/ps/sproute.pdf>

### 5.4 FastRoute 4.0

FastRoute 4.0 強調 via-aware Steiner tree generation、3-bend routing、
layer assignment ordering 與 via minimization。它的核心啟示是: via/WL 不應只在最後
layer assignment 才補救，而應該貫穿 tree generation、pattern routing 和 layer assignment。

對照本專案:

- plain fast greedy layer 的 WL 失控，正是缺少 net continuity / via-aware control。
- net-guided low-layer assignment 是第一步，但仍缺少 via-aware tree / 3-bend routing。

來源:

- FastRoute 4.0 PDF:
  <https://home.engineering.iastate.edu/~cnchu/pubs/c52.pdf>
- FastRoute 4.0 summary page:
  <https://www.researchgate.net/publication/221154485_FastRoute_40_Global_router_with_efficient_via_minimization>

### 5.5 CUGR

CUGR 的方向是 detailed-routability-driven 3D global routing，使用 3D pattern routing、
multi-level 3D maze routing 和 resource model。它不只把 3D 問題壓成 2D 後再 layer
assignment，而是更直接考慮 3D routing quality。

對照本專案:

- 我們目前仍是 2D route + layer assignment，因此 hard cases 可能在 3D layer assignment
  後放大 overflow。
- 未來若要同時改善 WL 和 routability，需要把 3D resource / via / layer move 納入 repair。

來源:

- CUGR paper/code:
  <https://github.com/cuhk-eda/cu-gr>
- CUGR PDF:
  <https://cwpui.com/doc/c10.pdf>

## 6. 結論

本專案的核心結論是: NTHU-Route 的可用加速不來自單純「開多核心」或「丟到 GPU」，
而是來自 routing effort 和 layer assignment policy 的改變。

目前有效且可辯護的方向:

1. fast layer 提供主要速度來源。
2. net-guided low-layer 修正 fast layer 的 WL 問題。
3. adaptive repair 與 high-overflow P2 budget 保證 original-legal cases 不退化。
4. edge-count 與 weakened repair 可作為 speed frontier，但不能當 final。
5. OpenMP/CUDA 需要更大的 algorithm restructuring 才可能有效。

目前最終策略仍未達到 2.8x 到 3.2x 的合法單一策略 speedup，但它已經做到:

- requested12 約 `1.29x-1.35x` speedup,
- original-legal subset 約 `1.69x-1.75x` speedup,
- original-legal `7/7` 保持合法,
- requested12 `10/12` legal,
- requested12 WL avg/worst 約 `1.158/1.284`,
- total overflow 壓到 `166`。

下一步若要突破，應該集中在 true bounded-length maze search、connected overflow
region repair、read-only parallel proposal、batched GPU candidate evaluation，以及 3D
via/WL-aware refinement。
