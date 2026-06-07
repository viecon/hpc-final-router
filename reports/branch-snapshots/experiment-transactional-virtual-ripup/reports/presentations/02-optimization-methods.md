# 優化方法簡報

日期：2026-06-06

## 投影片 1 - 原始 router 的效能問題

原始 NTHU-Route 的效能問題不是單一函式慢，而是 routing flow 裡有幾個互相影響
的 bottleneck：

- `rip-up/reroute` 會 sequentially 修改 shared `congestion map`；
- 固定 `P2/P3` budget 不會根據實際 `overflow` 狀態調整；
- 原始 layer assignment 較慢，但 naive fast layer 會讓 `wirelength` 變大；
- `post-processing` 可以很快，但太早停會留下 `overflow`；
- `CUDA` work units 太小，放進整體 CPU routing loop 後利用率很低。

## 投影片 2 - Routing pipeline 與平行化判斷

這張用來回答「為什麼不能直接平行化」。

| 階段 | 做什麼 | 平行化判斷 |
| --- | --- | --- |
| 1. Input / tree construction | 讀 `.gr`、建 FLUTE/two-pin tree。 | 可以做一些平行，但不是 runtime 主因。 |
| 2. Congestion analysis | 掃 edge demand、算 `overflow`、算 `wirelength`。 | 最容易平行；我們做過 `OpenMP`，但 end-to-end 只有約 `1.03x`。 |
| 3. `P2 rip-up/reroute` | 移除舊 path、找新 path、更新 shared `congestion map`。 | 最難平行；route order 會改變後續 cost，lock 又會接近 serial。 |
| 4. `P3 post-processing` | 挑 overflow candidates 再修。 | scoring 可平行，commit 仍受 shared state 和 conflict 影響。 |
| 5. Layer assignment | 把 2D route 映射到 metal layers。 | 改演算法比加 thread 有效；我們用 net-guided fast layer。 |
| 6. Output / verify | 輸出 route，跑 checker。 | 可平行但占比小，不是主要加速點。 |

結論：真正要多核化，不能只是 `#pragma omp parallel for`。比較合理的未來方向是
batch independent route proposals，先平行算 candidate，再用 deterministic order
commit。

## 投影片 3 - 為什麼目前只能安全地 sequential commit

這裡不是說 `rip-up/reroute` 理論上永遠不能平行化，而是目前 NTHU-Route 的
implementation 把「找路」和「commit」綁在同一個 in-place 流程，所以直接多
thread 會改變結果。

| 程式位置 | 實際相依性 | 為什麼會卡平行化 |
| --- | --- | --- |
| `Route_2pinnets::route_all_2pin_net()` | 主要時間進入 `RangeRouter::specify_all_range()`。 | hot path 不是單純 scan，而是進到 route mutation。 |
| `RangeRouter::range_router()` | 先讀 old path overflow，再 `remove` old path，找新 path，最後 `insert` new path。 | 每條 net 的新 cost 依賴前面 nets 已經 commit 後的 `congestion map`。 |
| `Congestion::update_congestion_map_remove_two_pin_net()` / `insert_two_pin_net()` | 直接修改 `edge.used_net`、`edge.cur_cap`，並重新計算 edge cost。 | 兩個 thread 若碰到同一條 edge，會 data race；即使用 lock，route order 仍會改變結果。 |
| `MM_mazeroute::adjust_twopin_element()` | maze 成功後會改 `two_pin.path`、pin endpoints、net tree neighbor 關係。 | 不只是 edge demand，net tree 結構本身也會 mutation。 |
| `Post_processing::initial_for_post_processing()` | 依排序後的 overflow candidates 逐一呼叫 `rangeRouter.range_router()`。 | 前一個 candidate 修完後，後面 candidate 的 overflow 狀態可能已經變了。 |

所以「直接平行化」會遇到三個問題：

1. shared `congestion map` 的 demand/cost race；
2. route order 改變，導致 `wirelength` / `overflow` 結果不 deterministic；
3. maze route 和 net tree update 不是純函式，不能安全地同時 commit。

我們其實有做過 parallel prototype：先用 conflict box 找不重疊的 candidates，
再平行處理。結果 CPU utilization 有上升，但因為 route order 變動、serial
fallback、stale candidates，`newblue2` 反而從 default `65.739s` 變成 best
`80.255s`，第一版 direct parallel maze commit 還跑到 `2609.637s` 並 abort。

## 投影片 4 - 如果要平行化，必須改成兩階段架構

可以改，但不是小改。需要把目前 in-place reroute 拆成 proposal 和 commit：

| 階段 | 目前作法 | 可平行版本需要改成 |
| --- | --- | --- |
| 讀 congestion | route 時直接讀目前 mutable `congestion map`。 | 建立 read-only congestion snapshot。 |
| 找 candidate path | 找到 path 後直接寫回 `two_pin.path`。 | 每個 thread 只產生 route proposal，不改 global state。 |
| 檢查 conflict | 目前靠 route order 自然吸收衝突。 | 先算 touched-edge set / bounding box，做 conflict coloring 或 batching。 |
| commit | 每條 net 找完路立即 remove/insert。 | 用 deterministic serial commit，commit 前再次檢查 overflow 是否真的改善。 |
| fallback | 目前失敗就走原本 maze / post-processing path。 | batch 失效時回到 sequential reroute，避免破壞 legality。 |

這也是為什麼文獻裡的 parallel global router 通常不是把原本 loop 直接加
`OpenMP`，而是設計 collision-aware / negotiation-based parallel routing。

## 投影片 5 - Amdahl's law：可平行化比例有多小

Amdahl's law：

```text
S(N) = 1 / ((1 - P) + P / N)
```

其中 `P` 是可平行化計算量比例，`N` 是核心數。這裡的 `P` 不用猜，而是從兩種
實測資料來：

- profiling 直接量到的可平行 scan/reduction 占比；
- thread sweep 的實測 speedup 反推 effective `P`。

### 直接 profiling 的 code-region 占比

來源：`../../docs/32-gpu-feasibility-notes.md`,
`../../docs/21-vm-multicore-utilization-log.md`

| 來源 | 可安全直接平行化的範圍 | `P` | `S(12)` | `S(infinite)` |
| --- | --- | ---: | ---: | ---: |
| adaptec1 detailed profile | `pre_evaluate_congestion_cost` + `overflow` / `wirelength` reduction | 0.0285% | 1.000261x | 1.000285x |
| newblue2 VM profile | 假設 `route_all` 以外全都可平行，這已經是很寬鬆上限 | <= 0.7574% | <= 1.006991x | <= 1.007632x |
| adaptec3 VM profile | 假設 `route_all` 以外全都可平行，這已經是很寬鬆上限 | <= 0.1979% | <= 1.001817x | <= 1.001983x |

這張表的意思是：如果只平行化目前容易平行的 analysis kernels，就算 12 cores 也
幾乎不可能帶來可見的 end-to-end speedup。

### 從實測 speedup 反推 effective `P`

反推公式：

```text
P = (1 - 1 / S(N)) / (1 - 1 / N)
```

| 實測 row | 實測 speedup `S(N)` | 反推 effective `P` | `S(infinite)` |
| --- | ---: | ---: | ---: |
| newblue2, 1 -> 12 threads: 65.646939s -> 63.587045s | 1.032395x | 3.4231% | 1.035444x |
| adaptec3, 1 -> 12 threads: 491.501180s -> 485.314663s | 1.012747x | 1.3731% | 1.013922x |
| requested12 `OpenMP t4`: 12295.597s -> 11917.582s | 1.031719x | 4.0992% | 1.042744x |

這裡的 effective `P` 是從整體 runtime 反推，會包含 measurement noise、cache
effect、iteration variation，以及所有目前 OpenMP 造成的實際效果；它不是 source
code line-by-line 的精準比例。即使如此，上限仍只有約 `1.014x` 到 `1.043x`。

結論：

> 直接可平行化的 scan/reduction 計算量太小；實測反推也顯示 current OpenMP
> path 的 effective parallel fraction 只有幾個百分點。所以真正要接近多核加速，
> 需要改成 batch route proposals，而不是只平行化現有 analysis kernels。

## 投影片 6 - 方法地圖

| 方法 | 目標 | 結果 |
| --- | --- | --- |
| `OpenMP` analysis kernels | 加速 CPU scan/reduction | 正確，但大約只有 `1.03x`。 |
| Conflict-aware reroute batches | 嘗試真正多核 reroute | CPU 利用率變高，但更慢。 |
| Fast greedy layer | 降低 layer assignment time | 很快，但 `WL` 太高。 |
| Net-guided low-layer | 控制 `WL` | 被保留為 final 方向。 |
| Adaptive legal repair | 保住原本合法 cases | 被保留。 |
| High-overflow `P2` budget | 修 hard-case `overflow` | 被保留。 |
| Edge-count post | runtime frontier | 有診斷價值，但多數 illegal。 |
| `CUDA` scoring | candidate / maze scoring | sub-kernel 正確且快，end-to-end 弱。 |
| Strict / bounded maze | 控制 `overflow` / `WL` | rejected 或 opt-in only。 |

## 投影片 7 - Fast layer 實作

Layer assignment dispatcher 只有在環境變數打開時才走 fast path：

```cpp
if (std::getenv("NTHU_FAST_GREEDY_LAYER") != nullptr) {
    if (std::getenv("NTHU_FAST_GREEDY_LAYER_NET_GUIDED") != nullptr) {
        fast_net_guided_layer_assignment();
    } else {
        fast_greedy_layer_assignment();
    }
}
```

效果：

- plain fast layer：requested12 約 `1.59x`，但 original-legal `WL` avg/worst
  `1.743/1.851`，品質太差；
- net-guided low-layer `WL<=1.2` legal7 diagnostic portfolio：`1.961x`，
  avg/worst `WL` `1.125/1.163`，只用來看方法上限，不當正式 score。

## 投影片 8 - Net-guided low-layer assignment

核心想法：

- 建立每個 net 的 edge list；
- 用 continuity 和 `overflow` penalty 評分 candidate layers；
- `NTHU_NET_GUIDED_LOW_LAYER_FIRST=1` 時，優先選低且合法的 layer；
- 只有必要時才用 congested fallback。

關鍵設定：

```text
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
```

為什麼有效：

- plain fast greedy 是 edge-by-edge 選 layer，容易讓同一個 net 分散到太多 layer；
- net-guided assignment 讓同一個 net 比較連續，減少 via 和 `WL` 成長；
- 這是把早期 fast layer 從「很快但品質差」修成「仍快且品質可控」的關鍵。

## 投影片 9 - Adaptive repair 實作

核心想法：

- 先跑短的 initial repair；
- 量測目前 `overflow`；
- 如果仍有 `overflow`，從已完成的 iteration 繼續 `P2`；
- 如果 `overflow` 很高，才提高 `P2 max iteration`；
- 如果 `overflow` 很小，限制額外 repair，避免 over-repair。

關鍵設定：

```text
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
```

效果：

- legal7 same-config clean run：`1.752x`，`WL` avg/worst `1.118/1.151`，`7/7` legal；
- requested12 same-config clean run：`1.345x`，`WL` avg/worst `1.158/1.284`，
  `10/12` legal，total `overflow=166`。

## 投影片 10 - Edge-count post-processing

核心想法：

- 統計每個 candidate 會碰到多少 overflow edges；
- 依 overflow edge count、max overflow、total overflow 排序；
- 把有限 reroute effort 先花在比較密集的 overflow 區域。

效果：

- requested12 runtime frontier：`5.38x`；
- 16-case matrix median speedup：`4.331x`；
- 但 legal coverage 很差，所以不能當 final legal strategy。

這個實驗的價值是：

> 如果少做 repair，router 可以很快；真正困難的是在不留下 `overflow` 的情況下
> 少做 repair。

## 投影片 11 - 多核與 CUDA 的實驗教訓

`OpenMP`：

- scan/reduction kernels 可以正確平行；
- 但主要 runtime 在 `P2/P3 rip-up/reroute` 的 shared-state mutation；
- conflict-aware prototype 有提高 CPU 使用率，但 route order、conflict check、
  serial fallback 讓它更慢。

`CUDA`：

- standalone scorer 很快；
- 但整合進 router 後，GPU work 被很多小 kernel 和 CPU sequential commit 切碎；
- dual GPU 對 single-case latency 幾乎沒有幫助。

結論：

> 未來要平行化，方向應該是 batch route proposals + deterministic commit。
> 目前這種直接 shared-state parallel reroute 或小 kernel offload，無法有效改善
> end-to-end runtime。

## 投影片 12 - Bounded-length 診斷

目標：

- 避免 maze route 產生太長 detour，降低 `WL`。

失敗點：

- 第一版在 `mm_maze_route_p()` 已經 mutate tree 後才 rollback `two_pin.path`；
- full12 bounded probe 變成 `12/12` fail。

安全修法：

- 把 `max_path_edges` 傳進 `MM_mazeroute`；
- 在 `adjust_twopin_element()` 前就 reject。

結果：

- A2/A4 smoke legal，`WL` 略降；
- 但 A2 慢 `2.557x`，A4 慢 `6.039x`；
- 因此 final disabled，只保留 opt-in。

## 投影片 13 - 保留與拒絕的方向

Final 保留：

- net-guided low-layer fast layer；
- adaptive legal repair；
- high-overflow `P2` budget；
- edge-count ordering 作為受控 candidate priority。

拒絕或 opt-in 的方向：

- 把 `OpenMP` scan 當 final speed claim；
- conflict-aware reroute prototype；
- `CUDA` single/dual GPU 作為 final path；
- strict legal maze；
- bounded-length reject-only guard；
- layer penalty tuning。

詳細來源：

- `../02-methods-by-commit-and-result.md`
- `../01-final-router-optimization-zh.md`
