# NTHU-Route Global Routing 加速與實驗方法報告

Last updated: 2026-05-27

## 摘要

本專題研究 VLSI global routing 在 ISPD08 benchmark 上的加速方法。研究主軸不是單純更換 router，而是以 NTHU-Route 作為可修改的 source-code baseline，分析其原始 code flow，找出可以介入的計算瓶頸，並透過多輪實驗比較不同加速策略的效果。NCTU-GR 則作為 cross-router baseline，用來理解同一組 testcase 在另一個 global router 架構下可達到的速度與合法性。

實驗流程採用「假設、設計、實作、測試、驗證、再提出新假設」的迭代方式。前期先建立 NTHU-Route 與 NCTU-GR 的 reproducible baseline，接著針對 NTHU-Route 嘗試 OpenMP analysis kernels、fast greedy layer assignment、P2/P3 routing budget tuning、CUDA-assisted costed maze scoring，以及 edge-count post-processing 等策略。最後選出有實際改動演算法或執行流程的 NTHU 策略，在 ISPD08 16 組 testcase 上重測。

最終最穩定、可宣稱的 NTHU source-code legal 加速成果，是在 `adaptec1-3` 上使用 best-per-benchmark legal strategy：

| Benchmark set | NTHU original | Best legal NTHU | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| `adaptec1-3` | 981.939003s | 422.179091s | 2.325883x | 0 |

16 組 ISPD08 重測則作為 cross-validation。由於 Taiwania Slurm QoS 實際可 dispatch 的 wall time 只有 `30:00`，部分大 testcase timeout。最終 96 個 strategy/testcase 組合中，74 筆產生有效 checker summary，22 筆 timeout/header-only，0 筆 missing。16 組重測顯示：fast layer 是最穩定的 legal 加速方向；P2/P3 budget tuning 對部分 testcase 有效；CUDA 子核心能加速局部 bounded maze/candidate scoring，但 end-to-end 受 sequential reroute flow 限制；edge-count post-processing 能做出很大的 runtime frontier，但多數結果不 legal。

## 1. 研究背景與目標

Global routing 是 VLSI physical design 中的重要階段。它需要在 routing grid 上連接所有 nets，同時盡量降低 wirelength、避免 overflow，並在合理時間內完成。Global router 的效能通常不是單純由某個小 kernel 決定，而是由 routing order、rip-up/reroute policy、overflow repair、layer assignment 與 post-processing 共同影響。

本專題的課程要求包含：

1. 設計或建立 baseline，並進行交叉測試。
2. 測試多次，善用統計方法與 benchmark 呈現結果。
3. 著重在改進策略與實驗方法。

因此本研究的目標不是只找一個最快的黑箱 binary，而是建立一套可重現的實驗流程，說明每個加速策略「改了哪裡、為什麼這樣改、結果是否有效」。實驗中原先希望達成 NTHU 自身 5x-10x speedup，但經過多輪測試後，合理結論是：legal NTHU source-code speedup 目前穩定達到約 2.33x；5x 以上可以在 NCTU-GR black-box 或 NTHU illegal runtime frontier 中看到，但還不能作為完成版 legal NTHU 結果。

## 2. 實驗環境與資料來源

### 2.1 Benchmark

主要 benchmark 為 ISPD08 global routing testcase，共 16 組：

```text
adaptec1, adaptec2, adaptec3, adaptec4, adaptec5,
bigblue1, bigblue2, bigblue3, bigblue4,
newblue1, newblue2, newblue3, newblue4, newblue5, newblue6, newblue7
```

在 16 組重測中，每個 testcase 理論上會跑 6 種 NTHU strategy，因此共有 96 個 strategy/testcase 組合。

### 2.2 Router

本專題使用兩個 router：

| Router | 角色 | 說明 |
| --- | --- | --- |
| NTHU-Route | 主要研究對象 | 有 source code，可進行 OpenMP、CUDA、routing policy、layer assignment、post-processing 修改。 |
| NCTU-GR | cross-router baseline | binary-only black-box，用來比較不同 router 架構下的速度與合法性，但不能算作 NTHU source-code 加速。 |

### 2.3 評估指標

每次 routing 完成後，以 Lab2 checker 評估：

- Runtime seconds
- Total wirelength
- Total overflow
- Max overflow
- Overflowed nets
- Overflowed edges
- Legal status：本報告以 checker `status=ok` 且 `total_overflow=0` 視為 legal。

### 2.4 執行環境

實驗在 Taiwania Slurm + Apptainer 環境中執行。16 組重測 `r2` 當時可穩定 dispatch 的 wall time 為 `30:00`，因此部分大 testcase timeout。後續課程公告將臨時限制調整為每組最多 1 個 running job、上限 2 nodes / 64 cores / 16 GPUs、最長 1 小時；2026-05-27 的輕量提交測試顯示 1 小時 job 會進入 `PENDING` 並卡在 `QOSGrpJobsLimit`，不是 walltime 錯誤。換言之，現行政策可能允許未來用 1 小時重跑 timeout cases，但本報告的 16 組 `r2` 數據仍應依當時 `30:00` 條件解讀。

## 3. 實驗流程

本專題採用迭代式實驗流程：

1. 建立 baseline。
   先讓 NTHU-Route 與 NCTU-GR 能在相同 container、相同 Slurm script、相同 checker 下執行，避免不同環境造成不可比較的結果。

2. 找瓶頸。
   透過 profiling 與 code inspection，確認 NTHU-Route 主要時間花在 Part 2 rip-up/reroute，而不是簡單 grid reduction。

3. 提出策略假設。
   每個策略都對應一個明確假設，例如 OpenMP 能否加速 analysis kernel、fast layer 能否取代 expensive layer assignment、P2/P3 budget 是否能避免過度 reroute、GPU 是否適合 bounded maze scoring。

4. 實作或設定策略。
   透過 compile option、environment variable、command-line routing parameters 或 source-code modification 隔離每個策略。

5. 跑 benchmark 並驗證。
   每個結果都產生 router output 與 checker summary。Speedup 一律相對同 testcase 的 `nthu_original` 計算。

6. 決定保留或淘汰。
   若策略只有 runtime 快但 overflow 很高，則標記為 runtime frontier，不列為 final legal result。

主要結果檔如下：

| Artifact | 用途 |
| --- | --- |
| `results/bench16_strategy_catalog.csv` | 定義所有 strategy 與是否納入 16 組重測。 |
| `results/bench16_strategy_matrix_r2_summary.csv` | 16 組重測的有效 checker summary rows。 |
| `results/bench16_strategy_matrix_r2_speedups.csv` | 16 組重測相對 NTHU original 的 speedup。 |
| `results/method_speedups_summary.csv` | 早期方法彙整，包含 adaptec1-3 best legal result。 |
| `results/cross_validation_checks.csv` | 重要結果的 cross-validation checks。 |

## 4. 原始 NTHU-Route Code Flow

理解原始 code flow 是本專題的核心，因為每個策略都必須說明自己是插在原本流程的哪個位置。

### 4.1 Main flow

NTHU-Route 的入口在 `Main.cpp`。高階流程是：

1. `ParameterAnalyzer` 解析輸入 testcase、輸出路徑與 routing parameters。
2. `RoutingRegion` 讀入 routing grid、capacity、nets。
3. `Congestion` 建立 2D congestion map。
4. `Construct_2d_tree` 執行主要 global routing。
5. `Layer_assignment` 將 2D routing result 指派到 3D metal layers。
6. `OutputGeneration` 輸出 route result。

程式位置：[external/nthu-route/src/router/Main.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Main.cpp:54)

```cpp
NTHUR::ParameterAnalyzer ap(argc, argv);
NTHUR::RoutingRegion routingData(ap.dataPreparation());
NTHUR::Congestion congestion(routingData.get_gridx(), routingData.get_gridy());
NTHUR::Construct_2d_tree tree(ap.routing_param(), routingData, congestion);
NTHUR::OutputGeneration output(routingData);
NTHUR::Layer_assignment layerAssignement(congestion, output);
```

這段說明 NTHU-Route 的 routing 與 layer assignment 是分開的。也就是說，如果 routing 本身已經造成 overflow，layer assignment 不一定能完全修復；反過來，如果 routing result 合理但 layer assignment 過慢，替換 layer assignment 就可能帶來 end-to-end speedup。

### 4.2 Part 2 rip-up/reroute loop

主要 runtime bottleneck 在 `Construct_2d_tree` 的 Part 2 routing loop。每一輪會：

1. 根據目前 congestion 更新 edge cost。
2. 對 two-pin nets 執行 reroute。
3. 計算 overflow。
4. 計算 wirelength。
5. 若 overflow 低於 threshold，提前結束 Part 2，進入後續修復或 post-processing。

程式位置：[external/nthu-route/src/router/Construct_2d_tree.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Construct_2d_tree.cpp:786)

```cpp
congestion.pre_evaluate_congestion_cost();
route_2pinnets.route_all_2pin_net();
int cur_overflow = congestion.cal_max_overflow();
congestion.cal_total_wirelength();
if (cur_overflow <= routingparam.get_overflow_threshold()) {
    break;
}
BOXSIZE_INC += routingparam.get_box_size_inc_p2();
```

這段 flow 對實驗策略有直接影響：

- 如果只加速 `pre_evaluate_congestion_cost()` 或 `cal_max_overflow()`，收益可能很小。
- 如果能減少 `route_all_2pin_net()` 的工作量，收益較可能反映到 end-to-end runtime。
- 如果調整 `overflow_threshold`、P2/P3 iteration 或 box size，可以用較少 routing effort 換取速度，但可能犧牲 legality。

### 4.3 Parameter flow

P2/P3 的 iteration、box size、overflow threshold 都由 command-line parser 控制，因此很適合做 systematic sweep。

程式位置：[external/nthu-route/src/router/parameter.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/parameter.cpp:154)

```cpp
{ "p2-max-iteration", 1, nullptr, 1 },
{ "p3-max-iteration", 1, nullptr, 2 },
{ "overflow-threshold", 1, nullptr, 3 },
{ "p3-init-box-size", 1, nullptr, 4 },
{ "p3-box-expand-size", 1, nullptr, 5 },
```

這些參數形成 routing effort budget。調小 iteration 或提高 threshold 可以縮短 runtime，但也可能讓 overflow 沒有完全修掉。

## 5. 策略一：NTHU original baseline

### 5.1 設計目的

`nthu_original` 是所有 NTHU source-level speedup 的 denominator。它不啟用 OpenMP、CUDA、fast layer 或 post-processing sorting，只保留必要的 ISPD08 compatibility fixes，確保 NTHU-Route 能穩定處理 benchmark。

### 5.2 實驗設定

定義位置：[scripts/run_bench16_strategy_one.sh](/home/u3961564/hpc-final-router/scripts/run_bench16_strategy_one.sh:21)

```bash
nthu_original)
  NTHU_OPENMP=OFF
  NTHU_CUDA=OFF
  NTHU_EXTRA_ARGS=""
  ENV_ASSIGNMENTS=()
  ;;
```

### 5.3 結果解讀

16 組重測中，`nthu_original` 有 11 筆有效結果、5 筆 timeout。Timeout 的 testcase 包含 `bigblue4`、`newblue3`、`newblue4`、`newblue6`、`newblue7`。這表示在 30 分鐘 QoS 下，部分大 testcase 無法取得原始 NTHU baseline，因此那些 testcase 的 speedup 不能完整計算。這也是本報告後續比較中特別標註 `with baseline` 的原因。

## 6. 策略二：OpenMP analysis kernels

### 6.1 假設

NTHU-Route 有多個對 grid edges 做掃描與 reduction 的函式，例如 overflow 計算、wirelength 計算、edge cost 更新與 interval construction。這些函式理論上具有資料平行性，因此假設 OpenMP 可以提升速度。

### 6.2 介入位置

主要介入點：

- `Congestion::cal_max_overflow`
- `Congestion::pre_evaluate_congestion_cost`
- `Congestion::cal_total_wirelength`
- `RangeRouter::divide_grid_edge_into_interval`
- `Post_processing` candidate counter

代表程式位置：[external/nthu-route/src/router/Congestion.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Congestion.cpp:86)

```cpp
#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static) reduction(max:max_2d_of) reduction(+:dif_curmax)
#endif
for (std::ptrdiff_t i = 0; i < edge_count; ++i) {
    Edge_2d& edge = edge_data[i];
    pre_evaluate_congestion_cost_fp(edge);
    if (edge.isOverflow()) {
        max_2d_of = std::max(max_2d_of, edge.overUsage());
        dif_curmax += edge.overUsage();
    }
}
```

`pre_evaluate_congestion_cost()` 也被平行化：

```cpp
#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static)
#endif
for (std::ptrdiff_t i = 0; i < edge_count; ++i) {
    Edge_2d& edge = edge_data[i];
    pre_evaluate_congestion_cost_fp(edge);
    if (edge.isOverflow()) {
        ++edge.history;
    }
}
```

### 6.3 結果

16 組重測結果：

| Metric | Value |
| --- | ---: |
| Completed | 11 |
| Legal | 7 |
| Comparable with baseline | 11 |
| Median speedup | 1.019x |
| Geomean speedup | 1.024x |
| Best legal speedup | 1.049x on `adaptec2` |

### 6.4 分析

OpenMP 的正確性沒有問題，但加速幅度很小。原因是這些 reduction/scan kernel 不是 end-to-end bottleneck。Profiling 顯示 runtime 大多花在 sequential rip-up/reroute，尤其是 `route_all_2pin_net()` 與 range routing，而不是 grid-level analysis。因此 OpenMP 是一個合理但效果有限的嘗試，適合在報告中作為「負結果也有價值」的例子：它證明了不能只看函式是否可平行化，還要看它在整體 runtime 中的比例。

## 7. 策略三：Fast greedy layer assignment

### 7.1 假設

原始 layer assignment 使用較完整的 KLAT/DP 搜尋，能追求較好的 layer assignment，但可能很花時間。若改用 greedy 策略，對每條 2D edge 選擇 projected utilization 較低的 layer，可能大幅縮短 layer assignment 時間，同時保留一定合法性。

### 7.2 介入位置

介入點在 `Layer_assignment` constructor。若設定 `NTHU_FAST_GREEDY_LAYER=1`，就直接使用 `fast_greedy_layer_assignment()`，否則走原始 `sort_net_order()`。

程式位置：[external/nthu-route/src/router/Layerassignment.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Layerassignment.cpp:526)

```cpp
if (std::getenv("NTHU_FAST_GREEDY_LAYER") != nullptr) {
    log_sp->info("Using fast greedy layer assignment");
    fast_greedy_layer_assignment();
} else {
    sort_net_order();
}
```

Greedy assignment 的核心是逐 edge 嘗試 layer，優先選擇 projected demand 不超過 capacity 且 score 最低的 layer。

程式位置：[external/nthu-route/src/router/Layerassignment.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Layerassignment.cpp:407)

```cpp
auto consider_layer = [&](int z) {
    Edge_3d& edge = output.cur_map_3d.edge(
        Coordinate_3d { a, z }, Coordinate_3d { b, z });
    const int projected = static_cast<int>(edge.used_net.size() + 1) * 2;
    const bool legal = projected <= edge.max_cap;
    const double score = static_cast<double>(projected) /
                         static_cast<double>(edge.max_cap);
    if ((legal && !found_legal) ||
            (legal == found_legal && score < best_score)) {
        best_layer = z;
        found_legal = legal;
        best_score = score;
    }
};
```

### 7.3 實驗設定

定義位置：[scripts/run_bench16_strategy_one.sh](/home/u3961564/hpc-final-router/scripts/run_bench16_strategy_one.sh:41)

```bash
NTHU_EXTRA_ARGS="--p2-init-box-size=5 --p2-box-expand-size=5"
ENV_ASSIGNMENTS=(NTHU_FAST_GREEDY_LAYER=1)
```

### 7.4 結果

| Metric | Value |
| --- | ---: |
| Completed | 13 |
| Legal | 8 |
| Comparable with baseline | 11 |
| Median speedup | 1.555x |
| Geomean speedup | 1.514x |
| Best legal speedup | 1.886x on `adaptec2` |

### 7.5 分析

Fast layer 是本專題最穩定的 source-level 加速策略。它不像 edge-count post-processing 那樣只追求 runtime frontier，而是有較高比例的 legal result。其缺點是 wirelength 通常變高，因為 greedy assignment 不像原始 KLAT/DP 那樣全域考慮 layer cost。不過就期末專題重點而言，這個策略有清楚的演算法改動、明確的 code intervention、可重現的 speedup，且 legal coverage 相對最好。

## 8. 策略四：P2/P3 routing budget tuning

### 8.1 假設

NTHU-Route 原始 P2/P3 routing effort 偏保守，會花很多時間在反覆 reroute 與 repair。對於某些 testcase，較小的 P2 iteration、較高的 overflow threshold、較大的 P3 box size，可能讓 router 更快進入 refinement 或更快終止，進而提升速度。

這個策略不是單純調 compiler flags，而是直接改變 routing search policy：它決定 router 願意花多少 effort 去修 overflow。

### 8.2 介入位置

P2/P3 budget 透過 command-line parameters 進入 `RoutingParameters`，並影響 `Construct_2d_tree` 的 main loop。

程式位置：[external/nthu-route/src/router/parameter.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/parameter.cpp:167)

```cpp
case 1:
    routingParam.set_iteration_p2(atoi(parameter.c_str()));
    break;
case 2:
    routingParam.set_iteration_p3(atoi(parameter.c_str()));
    break;
case 3:
    routingParam.set_overflow_threshold(atoi(parameter.c_str()));
    break;
```

在 routing loop 中，`overflow_threshold` 會決定是否提前離開 P2：

```cpp
if (cur_overflow <= routingparam.get_overflow_threshold()) {
    break;
}
```

### 8.3 實驗設定

16 組重測設定：[scripts/run_bench16_strategy_one.sh](/home/u3961564/hpc-final-router/scripts/run_bench16_strategy_one.sh:48)

```bash
--p2-init-box-size=5 --p2-box-expand-size=5 \
--p2-max-iteration=6 --overflow-threshold=1800 \
--p3-init-box-size=66 --p3-box-expand-size=122
NTHU_FAST_GREEDY_LAYER=1
```

### 8.4 結果

| Metric | Value |
| --- | ---: |
| Completed | 10 |
| Legal | 4 |
| Comparable with baseline | 9 |
| Median speedup | 1.415x |
| Geomean speedup | 1.261x |
| Best legal speedup | 2.125x on `adaptec1` |
| Fastest runtime frontier | 2.198x on `adaptec5`, but illegal |

### 8.5 分析

P2/P3 budget tuning 對 `adaptec1` 很有效，並且能產生 legal 2x 以上 speedup。但泛化到所有 testcase 時，legal rate 下降。原因是固定 budget 無法適應每個 testcase 的 congestion pattern：某些 testcase 需要更多 repair effort；若太早結束，就會留下 overflow。這表示後續若要把此策略做成完成版，應該改成 adaptive policy，例如根據 early iteration overflow slope 動態決定 threshold 或 P3 effort。

## 9. 策略五：CUDA-assisted costed maze scoring

### 9.1 假設

GPU 不適合直接搬整個 NTHU-Route，因為 global routing 的 rip-up/reroute 有大量 sequential dependency。但 GPU 適合處理局部 bounded maze 或 candidate scoring，尤其是許多 candidate 的 cost evaluation 具有資料平行性。早期 standalone scorer 在真實候選資料上得到約 33x-38x kernel speedup，因此嘗試將 CUDA 整合進 NTHU reroute flow。

### 9.2 介入位置

介入點在 `RangeRouter::range_router()`。當舊 path 有 overflow，且 monotonic/L-shape fast path 無法找到可用 path 時，原本會進入 CPU maze route。本策略在 CPU maze 前加入 CUDA costed maze fast path。

程式位置：[external/nthu-route/src/router/Range_router.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Range_router.cpp:696)

```cpp
if (cuda_maze_under_call_limit &&
        cuda_maze_enabled_this_phase &&
        old_path_overflow_score >= cuda_maze_min_overflow_score() &&
        !cuda_maze_runtime_disabled && cuda_dogleg_available()) {
    const int box_width = end.x - start.x + 1;
    const int box_height = end.y - start.y + 1;
    const int box_area = box_width * box_height;
```

若 box area 在限制內，建立 local edge open/cost arrays，呼叫 CUDA：

程式位置：[external/nthu-route/src/router/Range_router.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Range_router.cpp:736)

```cpp
if (cuda_costed_maze_fastpath_enabled()) {
    find_path_flag = cuda_find_costed_maze_path(box_width, box_height,
            east_open, south_open, east_cost, south_cost,
            two_pin.pin1.x - start.x, two_pin.pin1.y - start.y,
            two_pin.pin2.x - start.x, two_pin.pin2.y - start.y,
            start.x, start.y, cuda_path);
}
```

CUDA function 本身位於 [external/nthu-route/src/router/CudaDogleg.cu](/home/u3961564/hpc-final-router/external/nthu-route/src/router/CudaDogleg.cu:632)：

```cpp
bool cuda_find_costed_maze_path(int box_width, int box_height,
        const std::vector<int>& east_open,
        const std::vector<int>& south_open,
        const std::vector<double>& east_cost,
        const std::vector<double>& south_cost,
        int source_x, int source_y,
        int target_x, int target_y,
        int global_left, int global_bottom,
        std::vector<Coordinate_2d>& path)
```

### 9.3 實驗設定

16 組重測設定：[scripts/run_bench16_strategy_one.sh](/home/u3961564/hpc-final-router/scripts/run_bench16_strategy_one.sh:56)

```bash
NTHU_CUDA_COSTED_MAZE_FASTPATH=1
NTHU_CUDA_MAZE_MAX_AREA=256
NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42
NTHU_DOGLEG_FASTPATH=1
NTHU_RANGE_SKIP_REMAINDER=1
```

### 9.4 結果

| Metric | Value |
| --- | ---: |
| Completed | 13 |
| Legal | 2 |
| Comparable with baseline | 10 |
| Median speedup | 1.531x |
| Geomean speedup | 1.217x |
| Best legal speedup | 2.759x on `adaptec3` |

### 9.5 分析

CUDA 的 isolated kernel acceleration 是有效的，但 end-to-end speedup 不如 kernel speedup。原因包含：

- Host/device copy overhead。
- CUDA fast path 只在部分 bounded maze 被觸發。
- Router 仍有 sequential rip-up/reroute dependency。
- 過度 aggressive 的 CUDA path 可能導致 overflow，legal coverage 不高。

因此 CUDA 結果應該被描述為「成功加速局部 kernel，但整體 router 還需要 algorithm restructuring」。如果未來要更激進地使用 GPU，方向應該是 batching 多個 candidate/path evaluation，降低每次呼叫 CUDA 的固定成本，而不是把單一小 box maze route 一次一次送到 GPU。

## 10. 策略六：Edge-count post-processing

### 10.1 假設

Post-processing 的時間應集中在最有可能降低 overflow 的 candidates 上。與其按照原始排序處理所有 overflow candidate，不如優先處理穿過最多 overflow edges 的 two-pin nets，並限制後期 reroute 數量以控制 runtime。

### 10.2 介入位置

在 `Post_processing` 中，先統計每個 candidate path 的：

- `total_overflow`
- `max_overflow_edge`
- `overflow_edge_count`
- bounding box size

程式位置：[external/nthu-route/src/router/Post_processing.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Post_processing.cpp:122)

```cpp
counter[i].total_overflow = 0;
counter[i].max_overflow_edge = 0;
counter[i].overflow_edge_count = 0;
for (int j = twopList.path.size() - 1; j > 0; --j) {
    Edge_2d& edge = congestion.congestionMap2d.edge(
        twopList.path[j - 1], twopList.path[j]);
    if (edge.isOverflow()) {
        const int overuse = max(0, edge.overUsage());
        counter[i].total_overflow += overuse;
        counter[i].max_overflow_edge = std::max(counter[i].max_overflow_edge, overuse);
        ++counter[i].overflow_edge_count;
    }
}
```

若設定 `NTHU_POST_SORT_MODE=edge_count`，則依 overflow edge count 排序：

程式位置：[external/nthu-route/src/router/Post_processing.cpp](/home/u3961564/hpc-final-router/external/nthu-route/src/router/Post_processing.cpp:236)

```cpp
} else if (post_sort_mode != nullptr && std::strcmp(post_sort_mode, "edge_count") == 0) {
    std::sort(counter.begin(), counter.end(), [](const COUNTER& a, const COUNTER& b) {
        if (a.overflow_edge_count != b.overflow_edge_count) {
            return a.overflow_edge_count > b.overflow_edge_count;
        }
        if (a.max_overflow_edge != b.max_overflow_edge) {
            return a.max_overflow_edge > b.max_overflow_edge;
        }
        return a.bsize < b.bsize;
    });
}
```

### 10.3 實驗設定

16 組重測設定：[scripts/run_bench16_strategy_one.sh](/home/u3961564/hpc-final-router/scripts/run_bench16_strategy_one.sh:76)

```bash
NTHU_POST_SORT_MODE=edge_count
NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80
NTHU_REROUTE_SCORE_P2_ONLY=1
NTHU_REROUTE_MIN_OVERFLOW_SCORE=5
NTHU_REROUTE_LATE_SCORE_AFTER_ITER=4
NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=4
```

### 10.4 結果

| Metric | Value |
| --- | ---: |
| Completed | 16 |
| Legal | 2 |
| Comparable with baseline | 11 |
| Median speedup | 4.331x |
| Geomean speedup | 4.202x |
| Best legal speedup | 1.611x on `newblue2` |
| Fastest runtime frontier | 21.300x on `newblue1`, but illegal |

### 10.5 分析

Edge-count post-processing 是速度最漂亮的策略，所有 16 組都能在 30 分鐘內完成。它證明 aggressive candidate filtering 與 reroute budget control 對 runtime 非常有效。但是 legal result 只有 2 筆，代表它犧牲太多修 overflow 的能力。這個策略的定位應是 runtime frontier 和 ablation study，而不是 final legal strategy。

特別值得注意的是 `bigblue1`：此策略過去曾達到約 5x runtime frontier，但仍有 overflow，因此不能宣稱為完成版 5x legal NTHU result。這個結果反而說明了本題的核心 trade-off：想要 5x 速度並不難，難的是在 5x 速度下仍保持 legal。

## 11. 16 組 ISPD08 重測結果

### 11.1 完成度

| Item | Count |
| --- | ---: |
| Strategy/testcase combinations | 96 |
| Effective completed summaries | 74 |
| Timeout/header-only | 22 |
| Missing | 0 |
| Testcases with all 6 strategies completed | 9 / 16 |

22 筆 timeout/header-only 主要來自大 testcase 在 30 分鐘 QoS 下跑不完。各 strategy timeout 數：

| Strategy | Timeout/header-only count |
| --- | ---: |
| `nthu_original` | 5 |
| `nthu_openmp_t4` | 5 |
| `nthu_fast_layer` | 3 |
| `nthu_p2p3_budget` | 6 |
| `nthu_cuda_score` | 3 |
| `nthu_edgecount_post` | 0 |

### 11.2 Strategy-level 統計

此表只統計有效 checker summary。`Comparable` 代表同一 testcase 有 `nthu_original` baseline，因此可以計算 speedup。

| Strategy | Completed | Legal | Comparable | Median speedup | Geomean speedup | Best legal | Best runtime frontier |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `nthu_original` | 11 | 6 | 11 | 1.000x | 1.000x | 1.000x on `adaptec1` | 1.000x on `adaptec1` |
| `nthu_openmp_t4` | 11 | 7 | 11 | 1.019x | 1.024x | 1.049x on `adaptec2` | 1.051x on `newblue5`, illegal |
| `nthu_fast_layer` | 13 | 8 | 11 | 1.555x | 1.514x | 1.886x on `adaptec2` | 1.886x on `adaptec2`, legal |
| `nthu_p2p3_budget` | 10 | 4 | 9 | 1.415x | 1.261x | 2.125x on `adaptec1` | 2.198x on `adaptec5`, illegal |
| `nthu_cuda_score` | 13 | 2 | 10 | 1.531x | 1.217x | 2.759x on `adaptec3` | 2.759x on `adaptec3`, legal |
| `nthu_edgecount_post` | 16 | 2 | 11 | 4.331x | 4.202x | 1.611x on `newblue2` | 21.300x on `newblue1`, illegal |

### 11.3 16 組 speedup matrix

下表列出每個 testcase 下各策略相對 `nthu_original` 的加速倍數。`*` 表示該結果 checker 有完成但不是 legal route，也就是 `total_overflow > 0`；`timeout` 表示該 strategy 在 30 分鐘 QoS 下沒有產生有效 summary；`done, no baseline` 表示該 strategy 有完成，但同 testcase 的 `nthu_original` baseline timeout，因此無法計算相對 speedup。

| benchmark | Original | OpenMP t4 | Fast layer | P2/P3 budget | CUDA score | Edge-count post |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `adaptec1.capo70.3d.35.50.90` | 1.000x | 1.003x | 1.415x | 2.125x | 1.581x * | 3.187x * |
| `adaptec2.mpl60.3d.35.20.100` | 1.000x | 1.049x | 1.886x | 0.424x * | 0.373x * | 3.932x * |
| `adaptec3.dragon70.3d.30.50.90` | 1.000x | 1.021x | 1.238x | 1.415x | 2.759x | 2.161x * |
| `adaptec4.aplace60.3d.30.50.90` | 1.000x | 1.013x | 1.240x | 1.368x | 1.482x * | 1.589x |
| `adaptec5.mfar50.3d.50.20.100` | 1.000x | 1.008x | 1.578x | 2.198x * | 0.768x * | 4.331x * |
| `bigblue1.capo60.3d.50.10.100` | 1.000x | 1.007x | 1.598x | 2.163x * | 1.433x * | 4.976x * |
| `bigblue2.mpl60.3d.40.60.60` | 1.000x | 1.012x * | 1.555x * | 0.944x * | 1.735x * | 6.839x * |
| `bigblue3.aplace70.3d.50.10.90.m8` | 1.000x | 1.047x * | 1.497x * | timeout | 0.481x * | 6.430x * |
| `bigblue4.fastplace70.3d.80.20.80` | timeout | timeout | timeout | timeout | done, no baseline | done, no baseline |
| `newblue1.ntup50.3d.30.50.90` | 1.000x | 1.040x * | 1.792x * | 0.673x * | 1.896x * | 21.300x * |
| `newblue2.fastplace90.3d.50.20.100` | 1.000x | 1.019x | 1.363x | 1.528x | 1.701x | 1.611x |
| `newblue3.kraftwerk80.3d.40.50.90` | timeout | timeout | timeout | timeout | done, no baseline | done, no baseline |
| `newblue4.mpl50.3d.40.10.95` | timeout | timeout | done, no baseline | timeout | done, no baseline | done, no baseline |
| `newblue5.ntup50.3d.40.10.100` | 1.000x | 1.051x * | 1.631x * | timeout | timeout | 5.147x * |
| `newblue6.mfar80.3d.60.10.100` | timeout | timeout | done, no baseline | done, no baseline | timeout | done, no baseline |
| `newblue7.kraftwerk70.3d.80.20.82.m8` | timeout | timeout | timeout | timeout | timeout | done, no baseline |

### 11.4 Best legal per testcase

| Benchmark | Original time | Best legal strategy | Best legal time | Speedup | Wirelength | Overflow |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| `adaptec1.capo70.3d.35.50.90` | 405.391s | `nthu_p2p3_budget` | 190.771s | 2.125x | 9429701 | 0 |
| `adaptec2.mpl60.3d.35.20.100` | 161.032s | `nthu_fast_layer` | 85.377s | 1.886x | 8876888 | 0 |
| `adaptec3.dragon70.3d.30.50.90` | 424.443s | `nthu_cuda_score` | 153.842s | 2.759x | 22444948 | 0 |
| `adaptec4.aplace60.3d.30.50.90` | 113.358s | `nthu_edgecount_post` | 71.332s | 1.589x | 20483808 | 0 |
| `adaptec5.mfar50.3d.50.20.100` | 1138.668s | `nthu_fast_layer` | 721.716s | 1.578x | 27283473 | 0 |
| `bigblue1.capo60.3d.50.10.100` | 872.046s | `nthu_fast_layer` | 545.744s | 1.598x | 10308678 | 0 |
| `bigblue2.mpl60.3d.40.60.60` | 708.483s | - | - | - | - | - |
| `bigblue3.aplace70.3d.50.10.90.m8` | 585.177s | - | - | - | - | - |
| `bigblue4.fastplace70.3d.80.20.80` | - | - | - | - | - | - |
| `newblue1.ntup50.3d.30.50.90` | 719.403s | - | - | - | - | - |
| `newblue2.fastplace90.3d.50.20.100` | 56.339s | `nthu_cuda_score` | 33.127s | 1.701x | 14140283 | 0 |
| `newblue3.kraftwerk80.3d.40.50.90` | - | - | - | - | - | - |
| `newblue4.mpl50.3d.40.10.95` | - | - | - | - | - | - |
| `newblue5.ntup50.3d.40.10.100` | 1441.967s | - | - | - | - | - |
| `newblue6.mfar80.3d.60.10.100` | - | - | - | - | - | - |
| `newblue7.kraftwerk70.3d.80.20.82.m8` | - | - | - | - | - | - |

這張表的重點是：fast layer 與 CUDA scoring 可以在部分 testcase 上提供 legal speedup，但沒有一個固定策略能在所有 16 組上同時滿足 speed 與 legality。

### 11.5 Fastest runtime frontier

下表列出每個 testcase 中最快的完成結果，不要求 legal。這張表用來觀察 runtime frontier，但不能直接當作最終合法成果。

| Benchmark | Fastest completed strategy | Runtime | Speedup | Legal | Overflow |
| --- | --- | ---: | ---: | --- | ---: |
| `adaptec1.capo70.3d.35.50.90` | `nthu_edgecount_post` | 127.186s | 3.187x | no | 1212 |
| `adaptec2.mpl60.3d.35.20.100` | `nthu_edgecount_post` | 40.956s | 3.932x | no | 866 |
| `adaptec3.dragon70.3d.30.50.90` | `nthu_cuda_score` | 153.842s | 2.759x | yes | 0 |
| `adaptec4.aplace60.3d.30.50.90` | `nthu_edgecount_post` | 71.332s | 1.589x | yes | 0 |
| `adaptec5.mfar50.3d.50.20.100` | `nthu_edgecount_post` | 262.917s | 4.331x | no | 4888 |
| `bigblue1.capo60.3d.50.10.100` | `nthu_edgecount_post` | 175.261s | 4.976x | no | 3882 |
| `bigblue2.mpl60.3d.40.60.60` | `nthu_edgecount_post` | 103.594s | 6.839x | no | 3004 |
| `bigblue3.aplace70.3d.50.10.90.m8` | `nthu_edgecount_post` | 91.012s | 6.430x | no | 1536 |
| `newblue1.ntup50.3d.30.50.90` | `nthu_edgecount_post` | 33.775s | 21.300x | no | 2368 |
| `newblue2.fastplace90.3d.50.20.100` | `nthu_cuda_score` | 33.127s | 1.701x | yes | 0 |
| `newblue5.ntup50.3d.40.10.100` | `nthu_edgecount_post` | 280.153s | 5.147x | no | 1962 |

這張 frontier table 說明 edge-count post-processing 很能壓 runtime，但通常留下 overflow。若只看速度，它確實能在多個 testcase 接近或超過 5x；但本專題必須同時考慮 checker legality，因此這些 row 只能作為設計方向與負面證據。

## 12. 最終可宣稱成果

16 組重測主要用於泛化檢查；最終最適合作為 main claim 的仍是早期 `adaptec1-3` best legal NTHU 組合，因為三組都有 baseline、都有 legal result，且 cross-validation checks 全部通過。

| Benchmark | Method | Baseline | Runtime | Speedup | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | P2/P3 budget tuning | 398.602398s | 188.156013s | 2.118467x | 0 |
| adaptec2 | P2 threshold tuning | 160.380428s | 81.880970s | 1.958702x | 0 |
| adaptec3 | CUDA-assisted scoring | 422.956177s | 152.142108s | 2.780007x | 0 |
| total | Best legal NTHU combination | 981.939003s | 422.179091s | 2.325883x | 0 |

這個結果的意義是：NTHU-Route source code 的加速不是來自單一 trick，而是來自不同 testcase 適用不同策略。`adaptec1` 適合 routing budget tuning；`adaptec2` 適合 threshold/fast-layer 類策略；`adaptec3` 則由 CUDA-assisted scoring 得到最佳 legal speedup。

## 13. Cross-router baseline：NCTU-GR

NCTU-GR 在本專題中不是主要可修改對象，但它是重要的 cross-router baseline。NCTU-GR tuned black-box 在 `adaptec1-3` 上能達到 5x 以上 legal speedup：

| Method | Benchmark set | Time | Speedup vs NTHU original | Overflow |
| --- | --- | ---: | ---: | ---: |
| NTHU original | adaptec1-3 | 981.939003s | 1.000000x | mixed |
| NCTU-GR default | adaptec1-3 | 274.320014s | 3.579538x | 0 |
| NCTU-GR tuned | adaptec1-3 | 193.550437s | 5.073298x | 0 |

這個比較有兩個意義。第一，它證明在這些 testcase 上 5x legal speedup 不是不可能，只是 NTHU-Route 的現有 source-level intervention 尚未達到。第二，它提醒我們 router 架構本身差異很大；NCTU-GR 的 5x 不能包裝成 NTHU source-code optimization。

## 14. 討論

### 14.1 為什麼 OpenMP 效果小

OpenMP 改到的是規則 grid scan 和 reduction，這些函式雖然可平行化，但不是主 runtime。NTHU-Route 的主要時間在 rip-up/reroute，而這部分有 net ordering、congestion update、path dependency。直接把 scan 平行化只能改善很小比例的總時間，因此 end-to-end speedup 接近 1x。

### 14.2 為什麼 fast layer 穩定

Fast layer 直接替換 layer assignment 的核心演算法，避免原始 KLAT/DP 的大量搜尋。這是粗粒度、流程層級的改動，因此能反映到 end-to-end runtime。它的代價是 wirelength 增加與部分 testcase legality 降低，但在所有策略中 legal coverage 最好。

### 14.3 為什麼 P2/P3 tuning 需要 adaptive

固定 budget 對部分 testcase 有效，但對不同 congestion pattern 不穩定。若 threshold 太高，router 太早停止，留下 overflow；若 threshold 太低，又回到原始長時間 repair。未來應根據 early overflow reduction slope、overflow edge distribution 或 testcase size 動態設定 budget。

### 14.4 為什麼 CUDA kernel 快但 end-to-end 不等比例變快

CUDA costed maze 的核心計算可以很快，但整合到 router 後會遇到 Amdahl's law：只有部分 reroute 會走 CUDA fast path，且每次呼叫需要準備 bounded grid、copy cost arrays、回傳 path。若每次處理的工作太小，GPU launch 與資料搬移成本會抵銷部分收益。未來應採用 batched CUDA candidate evaluation，而不是單一 candidate 一次呼叫。

### 14.5 為什麼 edge-count post-processing 速度漂亮但不 legal

Edge-count post-processing 的本質是 aggressive pruning。它把時間集中在少數看起來最重要的 overflow candidates，並限制後續 reroute 數量，因此 runtime 大幅下降。但 overflow 修復是全域問題，少處理 candidates 很容易留下殘餘 overflow。這也是它能產生 5x 以上 frontier、卻不能成為 final legal result 的原因。

## 15. 限制

本研究有幾個限制：

1. Slurm QoS 限制導致 16 組重測無法完整取得所有 baseline 與 strategy 結果。雖然 missing 已補到 0，但仍有 22 筆 timeout/header-only。
2. NCTU-GR 是 binary-only，無法分析內部 code flow，也無法公平比較 source-level intervention。
3. CUDA strategy 仍是局部 fast path，尚未重構整個 router 成 batched GPU pipeline。
4. 部分 aggressive strategy 的 wirelength 增加很大，雖然 runtime 快，但不適合作為實際 router 預設策略。
5. 目前 final legal result 是 best-per-benchmark 組合，不是單一 universal parameter set。

## 16. 結論

本專題完成了從 baseline 建立、code flow 分析、策略設計、source-level 修改、GPU 嘗試，到 16 組 benchmark cross-validation 的完整實驗流程。最重要的結論有三點。

第一，NTHU-Route 的主要瓶頸不在簡單 reduction，而在 sequential rip-up/reroute 與 routing policy。因此 OpenMP analysis kernels 雖然正確，但 end-to-end speedup 幾乎沒有突破。

第二，真正有效的 NTHU source-level 加速需要改變 routing flow 或 effort distribution。Fast greedy layer assignment 與 P2/P3 budget tuning 都屬於這類方法，因此能得到 1.5x-2x 以上的 legal speedup。CUDA-assisted scoring 在 `adaptec3` 上也能達到 2.78x legal speedup，但目前尚未泛化。

第三，5x 以上 runtime frontier 可以透過 edge-count post-processing 或 NCTU-GR black-box 看到，但 NTHU source-code legal 5x 尚未完成。最誠實且可重現的 final claim 是：本專題在 `adaptec1-3` 上達成 2.325883x legal NTHU source-code speedup，並透過 16 組 ISPD08 重測分析各策略的泛化能力與限制。

最終建議的報告主張如下：

> We achieved a reproducible 2.325883x legal source-code speedup for NTHU-Route on `adaptec1-3` through fast layer assignment, P2/P3 routing-effort tuning, and CUDA-assisted scoring. A 16-case ISPD08 retest shows that fast layer assignment is the most robust legal optimization, while edge-count post-processing exposes a strong but mostly illegal runtime frontier. Cross-router NCTU-GR tuning can reach 5x+ legal speedup, but it is a black-box router comparison rather than an NTHU source-code improvement.

## 17. 後續工作

若要繼續往 5x-10x legal NTHU speedup 推進，建議方向如下：

1. Adaptive P2/P3 policy：根據 overflow reduction slope 自動調整 iteration、threshold、box size。
2. Legal-aware fast layer：在 greedy layer assignment 中加入更強的 continuity 與 overflow recovery。
3. Batched GPU candidate evaluation：一次把多個 bounded maze/candidate 送到 GPU，降低 launch 與 copy overhead。
4. Hybrid strategy selector：根據 testcase 特徵選擇 fast layer、P2/P3 budget 或 CUDA strategy，而不是固定一組參數打全部 testcase。
5. 在 QoS 允許 1 小時以上時，重跑 22 筆 timeout case，補齊完整 16 組矩陣。
