#include "Range_router.h"

#include <boost/multi_array.hpp>
#include <boost/multi_array/base.hpp>
#include <boost/multi_array/multi_array_ref.hpp>
#include <sys/types.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <exception>
#include <fstream>
#include <functional>
#include <limits>
#include <queue>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#ifdef NTHU_ROUTE_OPENMP
#include <omp.h>
#endif

#include "../grdb/EdgePlane.h"
#include "../grdb/RoutingRegion.h"
#include "Congestion.h"
#include "Construct_2d_tree.h"
#include "MM_mazeroute.h"

//#define SPDLOG_TRACE_ON
#include "../spdlog/spdlog.h"
#include "misc/geometry.h"
#include "router/MonotonicRouting.h"

namespace {
using ProfileClock = std::chrono::steady_clock;

bool direct_overflow_candidates_enabled() {
    return std::getenv("NTHU_DIRECT_OVERFLOW_CANDIDATES") != nullptr;
}

bool l_shape_fastpath_enabled() {
    return std::getenv("NTHU_L_SHAPE_FASTPATH") != nullptr;
}

bool dogleg_fastpath_enabled() {
    return std::getenv("NTHU_DOGLEG_FASTPATH") != nullptr;
}

bool cuda_dogleg_preselect_enabled() {
    return std::getenv("NTHU_CUDA_DOGLEG_PRESELECT") != nullptr;
}

bool cuda_dogleg_legal_filter_enabled() {
    return std::getenv("NTHU_CUDA_DOGLEG_LEGAL_FILTER") != nullptr;
}

bool cuda_dogleg_trust_legal_filter_enabled() {
    return std::getenv("NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER") != nullptr;
}

bool cuda_dogleg_trust_final_check_enabled() {
    return std::getenv("NTHU_CUDA_DOGLEG_TRUST_FINAL_CHECK") != nullptr;
}

bool cuda_dogleg_skip_cpu_fallback_enabled() {
    return std::getenv("NTHU_CUDA_DOGLEG_SKIP_CPU_FALLBACK") != nullptr;
}

int cuda_dogleg_min_batch() {
    const char* value = std::getenv("NTHU_CUDA_DOGLEG_MIN_BATCH");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

bool cuda_maze_fastpath_enabled() {
    return std::getenv("NTHU_CUDA_MAZE_FASTPATH") != nullptr;
}

bool cuda_costed_maze_fastpath_enabled() {
    return std::getenv("NTHU_CUDA_COSTED_MAZE_FASTPATH") != nullptr;
}

bool cuda_maze_post_only_enabled() {
    return std::getenv("NTHU_CUDA_MAZE_POST_ONLY") != nullptr;
}

bool cuda_maze_trust_legal_path_enabled() {
    return std::getenv("NTHU_CUDA_MAZE_TRUST_LEGAL") != nullptr;
}

int cuda_maze_max_area() {
    const char* value = std::getenv("NTHU_CUDA_MAZE_MAX_AREA");
    if (value == nullptr || *value == '\0') {
        return 4096;
    }
    return std::max(1, std::atoi(value));
}

int cuda_maze_min_overflow_score() {
    const char* value = std::getenv("NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int cuda_maze_max_calls() {
    const char* value = std::getenv("NTHU_CUDA_MAZE_MAX_CALLS");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int dogleg_sample_step() {
    const char* value = std::getenv("NTHU_DOGLEG_STEP");
    if (value == nullptr || *value == '\0') {
        return 8;
    }
    return std::max(1, std::atoi(value));
}

int dogleg_sample_radius() {
    const char* value = std::getenv("NTHU_DOGLEG_RADIUS");
    if (value == nullptr || *value == '\0') {
        return 2;
    }
    return std::max(0, std::min(8, std::atoi(value)));
}

int dogleg_max_extra_length() {
    const char* value = std::getenv("NTHU_DOGLEG_MAX_EXTRA");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int dogleg_min_overflow_score() {
    const char* value = std::getenv("NTHU_DOGLEG_MIN_SCORE");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int reroute_min_overflow_score() {
    const char* value = std::getenv("NTHU_REROUTE_MIN_OVERFLOW_SCORE");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

bool reroute_score_p2_only_enabled() {
    return std::getenv("NTHU_REROUTE_SCORE_P2_ONLY") != nullptr;
}

int reroute_score_until_iter() {
    const char* value = std::getenv("NTHU_REROUTE_SCORE_UNTIL_ITER");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::max(0, std::atoi(value));
}

int reroute_late_score_after_iter() {
    const char* value = std::getenv("NTHU_REROUTE_LATE_SCORE_AFTER_ITER");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::max(0, std::atoi(value));
}

int reroute_late_min_overflow_score() {
    const char* value = std::getenv("NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::max(1, std::atoi(value));
}

int direct_overflow_candidate_limit() {
    const char* value = std::getenv("NTHU_DIRECT_OVERFLOW_LIMIT");
    if (value == nullptr || *value == '\0') {
        return std::numeric_limits<int>::max();
    }
    return std::max(0, std::atoi(value));
}

bool parallel_reroute_batches_enabled() {
    return std::getenv("NTHU_PARALLEL_REROUTE_BATCHES") != nullptr;
}

bool proposal_reroute_batches_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_BATCHES") != nullptr;
}

bool proposal_reroute_maze_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_MAZE") != nullptr;
}

bool proposal_reroute_log_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_LOG") != nullptr;
}

bool proposal_reroute_conflict_aware_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_CONFLICT_AWARE") != nullptr;
}

bool proposal_reroute_overflow_edge_conflict_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_CONFLICT") != nullptr;
}

bool proposal_reroute_improvement_commit_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_IMPROVEMENT_COMMIT") != nullptr;
}

bool proposal_reroute_global_commit_post_only_enabled() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_POST_ONLY");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool proposal_reroute_ripup_before_propose_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_RIPUP_BEFORE_PROPOSE") != nullptr;
}

bool proposal_reroute_safe_commit_enabled() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_SAFE_COMMIT");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool proposal_reroute_adaptive_rounds_enabled() {
    return std::getenv("NTHU_PROPOSAL_REROUTE_ADAPTIVE_ROUNDS") != nullptr;
}

bool v8_proposal_parallel_enabled() {
    const char* value = std::getenv("NTHU_V8_PROPOSAL_PARALLEL");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_transactional_proposal_waves_enabled() {
    const char* value = std::getenv("NTHU_V8_TRANSACTIONAL_PROPOSAL_WAVES");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int v8_transactional_proposal_wave_size() {
    const char* value = std::getenv("NTHU_V8_TRANSACTIONAL_PROPOSAL_WAVE_SIZE");
    if (value == nullptr || *value == '\0') {
        return 256;
    }
    return std::max(1, std::atoi(value));
}

bool v8_transactional_proposal_global_gate_enabled() {
    const char* value = std::getenv("NTHU_V8_TRANSACTIONAL_PROPOSAL_GLOBAL_GATE");
    if (value == nullptr || *value == '\0') {
        return true;
    }
    return std::atoi(value) != 0;
}

bool v8_transactional_proposal_require_progress_enabled() {
    const char* value = std::getenv("NTHU_V8_TRANSACTIONAL_PROPOSAL_REQUIRE_PROGRESS");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_reject_cooldown_enabled() {
    return std::getenv("NTHU_V8_REJECT_COOLDOWN") != nullptr;
}

bool v8_low_overflow_edge_oversubscribe_enabled() {
    return std::getenv("NTHU_V8_LOW_OVERFLOW_EDGE_OVERSUBSCRIBE") != nullptr;
}

bool v8_low_tail_global_repair_enabled() {
    return std::getenv("NTHU_V8_LOW_TAIL_GLOBAL_REPAIR") != nullptr;
}

bool v8_low_tail_post_only_enabled() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_POST_ONLY");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int v8_low_tail_global_repair_limit() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT");
    if (value == nullptr || *value == '\0') {
        return 16;
    }
    return std::max(0, std::atoi(value));
}

int v8_low_tail_global_repair_max_candidates() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_MAX_CANDIDATES");
    if (value == nullptr || *value == '\0') {
        return 128;
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int v8_low_tail_global_repair_rounds() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_ROUNDS");
    if (value == nullptr || *value == '\0') {
        return 4;
    }
    return std::max(1, std::atoi(value));
}

int v8_low_tail_box_inc() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_BOX_INC");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

bool v8_low_tail_self_ripup_enabled() {
    return std::getenv("NTHU_V8_LOW_TAIL_SELF_RIPUP") != nullptr;
}

int v8_low_tail_self_ripup_box_inc() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_SELF_RIPUP_BOX_INC");
    if (value == nullptr || *value == '\0') {
        return 122;
    }
    return std::max(0, std::atoi(value));
}

int v8_low_tail_self_ripup_max_tests() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_SELF_RIPUP_MAX_TESTS");
    if (value == nullptr || *value == '\0') {
        return 32;
    }
    return std::max(1, std::atoi(value));
}

bool v8_low_tail_strict_capacity_enabled() {
    const char* value = std::getenv("NTHU_V8_LOW_TAIL_STRICT_CAPACITY");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_post_only_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_POST_ONLY");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int v8_strict_legal_repair_trigger() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_TRIGGER");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(0, std::atoi(value));
}

int v8_strict_legal_repair_max_overflow() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_MAX_OVERFLOW");
    if (value == nullptr || *value == '\0') {
        return std::numeric_limits<int>::max();
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int v8_strict_legal_repair_rounds() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_ROUNDS");
    if (value == nullptr || *value == '\0') {
        return 4;
    }
    return std::max(1, std::atoi(value));
}

int v8_strict_legal_repair_max_candidates() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_MAX_CANDIDATES");
    if (value == nullptr || *value == '\0') {
        return 1024;
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int v8_strict_legal_repair_batch_size() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_BATCH_SIZE");
    if (value == nullptr || *value == '\0') {
        return 256;
    }
    return std::max(1, std::atoi(value));
}

int v8_strict_legal_repair_edge_quota() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_EDGE_QUOTA");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int v8_strict_legal_repair_base_box() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_BASE_BOX");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int v8_strict_legal_repair_fixed_base_box() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_FIXED_BASE_BOX");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::max(0, std::atoi(value));
}

int v8_strict_legal_repair_box_inc() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_BOX_INC");
    if (value == nullptr || *value == '\0') {
        return 64;
    }
    return std::max(0, std::atoi(value));
}

int v8_strict_legal_repair_max_no_progress() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_MAX_NO_PROGRESS");
    if (value == nullptr || *value == '\0') {
        return 2;
    }
    return std::max(1, std::atoi(value));
}

bool v8_strict_legal_repair_snapshot_commit_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_COMMIT");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int v8_strict_legal_repair_snapshot_commit_max_overflow() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_COMMIT_MAX_OVERFLOW");
    if (value == nullptr || *value == '\0') {
        return std::numeric_limits<int>::max();
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

bool v8_strict_legal_repair_snapshot_rollback_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_ROLLBACK");
    if (value == nullptr || *value == '\0') {
        return true;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_rollback_no_progress_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_ROLLBACK_NO_PROGRESS");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_snapshot_global_gate_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_GLOBAL_GATE");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int v8_strict_legal_repair_snapshot_burst_total() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_BURST_TOTAL");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int v8_strict_legal_repair_snapshot_burst_max() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_SNAPSHOT_BURST_MAX");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

bool v8_strict_legal_repair_improvement_commit_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_IMPROVEMENT_COMMIT");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_reuse_inputs_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_REUSE_INPUTS");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_legal_repair_overflow_net_inputs_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_LEGAL_REPAIR_OVERFLOW_NET_INPUTS");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool v8_strict_repair_allow_same_net_enabled() {
    const char* value = std::getenv("NTHU_V8_STRICT_REPAIR_ALLOW_SAME_NET");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int proposal_reroute_overflow_edge_quota() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_QUOTA");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int proposal_reroute_max_candidates() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES");
    if (value == nullptr || *value == '\0') {
        return std::numeric_limits<int>::max();
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int proposal_reroute_batch_size() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_BATCH_SIZE");
    if (value == nullptr || *value == '\0') {
        return 4096;
    }
    return std::max(1, std::atoi(value));
}

int proposal_reroute_max_rounds() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_MAX_ROUNDS");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

bool parallel_reroute_log_enabled() {
    return std::getenv("NTHU_PARALLEL_REROUTE_LOG") != nullptr;
}

int parallel_reroute_batch_limit() {
    const char* value = std::getenv("NTHU_PARALLEL_REROUTE_BATCH_LIMIT");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(1, std::atoi(value));
}

int parallel_reroute_max_candidates() {
    const char* value = std::getenv("NTHU_PARALLEL_REROUTE_MAX_CANDIDATES");
    if (value == nullptr || *value == '\0') {
        return 4096;
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int proposal_reroute_low_overflow_limit() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_LOW_OVERFLOW_LIMIT");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int proposal_reroute_low_max_rounds() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_LOW_MAX_ROUNDS");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int proposal_reroute_global_commit_limit() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_LIMIT");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

int proposal_reroute_global_commit_max_tests() {
    const char* value = std::getenv("NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_MAX_TESTS");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

bool profile_enabled() {
    return std::getenv("NTHU_PROFILE") != nullptr;
}

bool dump_candidates_enabled() {
    const char* value = std::getenv("NTHU_DUMP_REROUTE_CANDIDATES");
    return value != nullptr && *value != '\0';
}

int dump_candidate_limit() {
    const char* value = std::getenv("NTHU_DUMP_CANDIDATE_LIMIT");
    if (value == nullptr || *value == '\0') {
        return 200000;
    }
    return std::max(0, std::atoi(value));
}

void dump_reroute_candidate(const NTHUR::Two_pin_element_2d& two_pin, int iteration, int overflow_score) {
    static std::ofstream out;
    static bool opened = false;
    static int rows = 0;

    if (!dump_candidates_enabled()) {
        return;
    }
    const int limit = dump_candidate_limit();
    if (rows >= limit) {
        return;
    }
    if (!opened) {
        out.open(std::getenv("NTHU_DUMP_REROUTE_CANDIDATES"));
        out << "iteration,net_id,pin1_x,pin1_y,pin2_x,pin2_y,box_size,path_edges,overflow_score\n";
        opened = true;
    }
    out << iteration << ',' << two_pin.net_id << ','
        << two_pin.pin1.x << ',' << two_pin.pin1.y << ','
        << two_pin.pin2.x << ',' << two_pin.pin2.y << ','
        << two_pin.boxSize() << ','
        << (two_pin.path.empty() ? 0 : static_cast<int>(two_pin.path.size()) - 1) << ','
        << overflow_score << '\n';
    ++rows;
}

bool skip_remainder_candidates_enabled() {
    return std::getenv("NTHU_RANGE_SKIP_REMAINDER") != nullptr;
}

bool range_sort_by_overflow_score_enabled() {
    return std::getenv("NTHU_RANGE_SORT_BY_OVERFLOW_SCORE") != nullptr;
}

bool post_accept_improvement_enabled() {
    return std::getenv("NTHU_POST_ACCEPT_IMPROVEMENT") != nullptr;
}

bool strict_legal_maze_enabled() {
    const char* value = std::getenv("NTHU_STRICT_LEGAL_MAZE");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

bool bounded_length_reroute_enabled() {
    return std::getenv("NTHU_BOUNDED_LENGTH_REROUTE") != nullptr;
}

bool bounded_length_post_only_enabled() {
    return std::getenv("NTHU_BOUNDED_LENGTH_POST_ONLY") != nullptr;
}

int bounded_length_min_iter() {
    const char* value = std::getenv("NTHU_BOUNDED_LENGTH_MIN_ITER");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::atoi(value);
}

int bounded_length_extra_edges() {
    const char* value = std::getenv("NTHU_BOUNDED_LENGTH_EXTRA");
    if (value == nullptr || *value == '\0') {
        return 8;
    }
    return std::max(0, std::atoi(value));
}

int bounded_length_original_extra_edges() {
    const char* value = std::getenv("NTHU_BOUNDED_LENGTH_ORIGINAL_EXTRA");
    if (value == nullptr || *value == '\0') {
        return 0;
    }
    return std::max(0, std::atoi(value));
}

double bounded_length_ratio() {
    const char* value = std::getenv("NTHU_BOUNDED_LENGTH_RATIO");
    if (value == nullptr || *value == '\0') {
        return 1.20;
    }
    return std::max(1.0, std::atof(value));
}

bool strict_legal_maze_post_only_enabled() {
    const char* value = std::getenv("NTHU_STRICT_LEGAL_MAZE_POST_ONLY");
    if (value == nullptr || *value == '\0') {
        return false;
    }
    return std::atoi(value) != 0;
}

int strict_legal_maze_max_area() {
    const char* value = std::getenv("NTHU_STRICT_LEGAL_MAZE_MAX_AREA");
    if (value == nullptr || *value == '\0') {
        return 250000;
    }
    return std::max(1, std::atoi(value));
}

int strict_legal_maze_min_iter() {
    const char* value = std::getenv("NTHU_STRICT_LEGAL_MAZE_MIN_ITER");
    if (value == nullptr || *value == '\0') {
        return -1;
    }
    return std::atoi(value);
}

int post_accept_min_delta() {
    const char* value = std::getenv("NTHU_POST_ACCEPT_MIN_DELTA");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int remainder_min_box_size() {
    const char* value = std::getenv("NTHU_RANGE_REMAINDER_MIN_BOX");
    if (value == nullptr || *value == '\0') {
        return 2;
    }
    return std::max(1, std::atoi(value));
}

double profile_ms(ProfileClock::time_point start, ProfileClock::time_point end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

int path_overflow_score(const NTHUR::Two_pin_element_2d& two_pin, const NTHUR::Congestion& congestion) {
    int overflow_score = 0;
    for (int path_index = static_cast<int>(two_pin.path.size()) - 2; path_index >= 0; --path_index) {
        const NTHUR::Edge_2d& edge = congestion.congestionMap2d.edge(two_pin.path[path_index], two_pin.path[path_index + 1]);
        overflow_score += std::max(0, edge.overUsage());
    }
    return overflow_score;
}

int inserted_path_overflow_score(const std::vector<NTHUR::Coordinate_2d>& path,
        int net_id,
        const NTHUR::Congestion& congestion) {
    int overflow_score = 0;
    for (int path_index = static_cast<int>(path.size()) - 2; path_index >= 0; --path_index) {
        const NTHUR::Edge_2d& edge = congestion.congestionMap2d.edge(path[path_index], path[path_index + 1]);
        const int inc = edge.lookupNet(net_id) ? 0 : 1;
        overflow_score += std::max(0, static_cast<int>(edge.cur_cap + inc - edge.max_cap));
    }
    return overflow_score;
}

int path_edges(const std::vector<NTHUR::Coordinate_2d>& path) {
    return path.empty() ? 0 : static_cast<int>(path.size()) - 1;
}

int path_manhattan_endpoints(const std::vector<NTHUR::Coordinate_2d>& path) {
    if (path.size() < 2) {
        return 0;
    }
    const NTHUR::Coordinate_2d& a = path.front();
    const NTHUR::Coordinate_2d& b = path.back();
    return std::abs(a.x - b.x) + std::abs(a.y - b.y);
}

bool bounded_length_phase_enabled(int version, int current_iter) {
    if (!bounded_length_reroute_enabled()) {
        return false;
    }
    if (bounded_length_post_only_enabled() && version != 3) {
        return false;
    }
    return current_iter >= bounded_length_min_iter();
}

int bounded_length_limit(const std::vector<NTHUR::Coordinate_2d>& original_path) {
    const int manhattan = path_manhattan_endpoints(original_path);
    const int original_edges = path_edges(original_path);
    const int ratio_limit = static_cast<int>(std::ceil(
            static_cast<double>(manhattan) * bounded_length_ratio())) +
            bounded_length_extra_edges();
    const int original_limit = original_edges + bounded_length_original_extra_edges();
    return std::max(manhattan, std::max(ratio_limit, original_limit));
}

bool find_strict_legal_maze_path(const NTHUR::Two_pin_element_2d& two_pin,
        const NTHUR::Congestion& congestion,
        const NTHUR::Coordinate_2d& start,
        const NTHUR::Coordinate_2d& end,
        std::vector<NTHUR::Coordinate_2d>& path) {
    const int width = end.x - start.x + 1;
    const int height = end.y - start.y + 1;
    if (width <= 0 || height <= 0) {
        return false;
    }
    const int max_area = strict_legal_maze_max_area();
    if (width > max_area / height) {
        return false;
    }

    auto in_box = [&](const NTHUR::Coordinate_2d& c) {
        return c.x >= start.x && c.x <= end.x && c.y >= start.y && c.y <= end.y;
    };
    if (!in_box(two_pin.pin1) || !in_box(two_pin.pin2)) {
        return false;
    }

    const int area = width * height;
    auto index_of = [&](const NTHUR::Coordinate_2d& c) {
        return (c.y - start.y) * width + (c.x - start.x);
    };
    auto coordinate_of = [&](int index) {
        return NTHUR::Coordinate_2d { start.x + (index % width), start.y + (index / width) };
    };

    const int source = index_of(two_pin.pin1);
    const int target = index_of(two_pin.pin2);
    const bool allow_same_net = v8_strict_repair_allow_same_net_enabled();
    std::vector<double> dist(area, std::numeric_limits<double>::infinity());
    std::vector<int> parent(area, -1);
    using QueueItem = std::pair<double, int>;
    std::priority_queue<QueueItem, std::vector<QueueItem>, std::greater<QueueItem>> queue;
    dist[source] = 0.0;
    queue.push({ 0.0, source });

    const std::array<NTHUR::Coordinate_2d, 4> directions {
            NTHUR::Coordinate_2d { 1, 0 },
            NTHUR::Coordinate_2d { -1, 0 },
            NTHUR::Coordinate_2d { 0, 1 },
            NTHUR::Coordinate_2d { 0, -1 } };

    while (!queue.empty()) {
        const QueueItem item = queue.top();
        const double cost = item.first;
        const int current_index = item.second;
        queue.pop();
        if (cost != dist[current_index]) {
            continue;
        }
        if (current_index == target) {
            break;
        }
        const NTHUR::Coordinate_2d current = coordinate_of(current_index);
        for (const NTHUR::Coordinate_2d& direction : directions) {
            const NTHUR::Coordinate_2d next { current.x + direction.x, current.y + direction.y };
            if (!in_box(next)) {
                continue;
            }
            const NTHUR::Edge_2d& edge = congestion.congestionMap2d.edge(current, next);
            const bool same_net_edge = edge.lookupNet(two_pin.net_id);
            if (!allow_same_net && same_net_edge) {
                continue;
            }
            const double demand_increment = same_net_edge ? 0.0 : 1.0;
            if (edge.cur_cap + demand_increment > edge.max_cap) {
                continue;
            }
            const int next_index = index_of(next);
            const double edge_cost = (same_net_edge ? 0.05 : 1.0) + std::max(0.0, edge.cost);
            const double next_cost = cost + edge_cost;
            if (next_cost < dist[next_index]) {
                dist[next_index] = next_cost;
                parent[next_index] = current_index;
                queue.push({ next_cost, next_index });
            }
        }
    }

    if (!std::isfinite(dist[target])) {
        return false;
    }
    path.clear();
    for (int at = target; at != -1; at = parent[at]) {
        path.push_back(coordinate_of(at));
        if (at == source) {
            break;
        }
    }
    if (path.empty() || path.back() != two_pin.pin1) {
        path.clear();
        return false;
    }
    std::reverse(path.begin(), path.end());
    return path.size() >= 2;
}

bool find_strict_legal_path_with_box(const NTHUR::Two_pin_element_2d& two_pin,
        const NTHUR::Congestion& congestion,
        const NTHUR::Construct_2d_tree& construct_2d_tree,
        int box_size,
        std::vector<NTHUR::Coordinate_2d>& path) {
    NTHUR::Coordinate_2d start;
    NTHUR::Coordinate_2d end;

    start.x = std::min(two_pin.pin1.x, two_pin.pin2.x);
    start.y = std::min(two_pin.pin1.y, two_pin.pin2.y);
    end.x = std::max(two_pin.pin1.x, two_pin.pin2.x);
    end.y = std::max(two_pin.pin1.y, two_pin.pin2.y);

    start.x = std::max(0, start.x - box_size);
    start.y = std::max(0, start.y - box_size);
    end.x = std::min(construct_2d_tree.rr_map.get_gridx() - 1, end.x + box_size);
    end.y = std::min(construct_2d_tree.rr_map.get_gridy() - 1, end.y + box_size);

    return find_strict_legal_maze_path(two_pin, congestion, start, end, path);
}

void sort_twopins_by_overflow_score(std::vector<NTHUR::Two_pin_element_2d*>& twopin_list,
        const NTHUR::Congestion& congestion) {
    struct ScoredTwoPin {
        NTHUR::Two_pin_element_2d* two_pin;
        int overflow_score;
    };

    std::vector<ScoredTwoPin> scored;
    scored.reserve(twopin_list.size());
    for (NTHUR::Two_pin_element_2d* two_pin : twopin_list) {
        scored.push_back(ScoredTwoPin { two_pin, path_overflow_score(*two_pin, congestion) });
    }
    std::sort(scored.begin(), scored.end(), [](const ScoredTwoPin& a, const ScoredTwoPin& b) {
        if (a.overflow_score != b.overflow_score) {
            return a.overflow_score > b.overflow_score;
        }
        return NTHUR::Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
    });
    for (std::size_t i = 0; i < scored.size(); ++i) {
        twopin_list[i] = scored[i].two_pin;
    }
}

struct RangeProfile {
    double interval_sort_ms = 0;
    double expand_ms = 0;
    double query_ms = 0;
    double candidate_sort_ms = 0;
    double direct_candidate_scan_ms = 0;
    double reroute_ms = 0;
    double check_old_path_ms = 0;
    double remove_ms = 0;
    double monotonic_ms = 0;
    double l_shape_ms = 0;
    double check_new_path_ms = 0;
    double maze_ms = 0;
    double insert_ms = 0;
    double cuda_prepare_ms = 0;
    double cuda_maze_ms = 0;
    double proposal_ms = 0;
    double proposal_commit_ms = 0;
    int ranges = 0;
    int candidates = 0;
    int route_calls = 0;
    int actual_reroutes = 0;
    int l_shape_success = 0;
    int cuda_batches = 0;
    int cuda_skipped_small_batches = 0;
    int cuda_inputs = 0;
    int cuda_valid_choices = 0;
    int cuda_maze_attempts = 0;
    int cuda_maze_success = 0;
    int cuda_maze_area_skips = 0;
    int cuda_maze_score_skips = 0;
    int cuda_maze_call_limit_skips = 0;
    int parallel_batches = 0;
    int parallel_batches_with_work = 0;
    int parallel_inputs = 0;
    int parallel_serialized_inputs = 0;
    int parallel_max_batch = 0;
    int proposal_inputs = 0;
    int proposal_success = 0;
    int proposal_commits = 0;
    int proposal_commit_rejects = 0;
    int proposal_skipped = 0;

    void reset() {
        *this = RangeProfile {};
    }
};

struct RerouteProposal {
    NTHUR::Two_pin_element_2d* two_pin = nullptr;
    std::vector<NTHUR::Coordinate_2d> path;
    bool proposed = false;
    bool committed = false;
    bool rejected = false;
};

struct StrictRepairInput {
    NTHUR::Two_pin_element_2d* two_pin = nullptr;
    int overflow_score = 0;
};

struct StrictRepairState {
    std::vector<NTHUR::Coordinate_2d> original_path;
    NTHUR::Coordinate_2d original_pin1;
    NTHUR::Coordinate_2d original_pin2;
};

struct RerouteCandidateBox {
    NTHUR::Two_pin_element_2d* two_pin;
    NTHUR::Rectangle box;
};

bool boxes_overlap(const NTHUR::Rectangle& a, const NTHUR::Rectangle& b) {
    return !(a.downRight.x < b.upLeft.x || b.downRight.x < a.upLeft.x ||
            a.downRight.y < b.upLeft.y || b.downRight.y < a.upLeft.y);
}

std::uint64_t route_edge_key(const NTHUR::Coordinate_2d& c1, const NTHUR::Coordinate_2d& c2) {
    NTHUR::Coordinate_2d low = c1;
    NTHUR::Coordinate_2d high = c2;
    if (std::tie(high.x, high.y) < std::tie(low.x, low.y)) {
        std::swap(low, high);
    }
    const std::uint64_t orientation = low.x == high.x ? 1ULL : 0ULL;
    return (static_cast<std::uint64_t>(low.x) << 33) ^
            (static_cast<std::uint64_t>(low.y) << 1) ^ orientation;
}

struct OverflowEdgeRef {
    std::uint64_t key;
    int overuse;
};

struct OverflowStats {
    int max_overflow = 0;
    int total_overflow = 0;
};

struct AffectedOverflowEdge {
    NTHUR::Coordinate_2d from;
    NTHUR::Coordinate_2d to;
    int before_overflow = 0;
};

OverflowStats current_overflow_stats(const NTHUR::Congestion& congestion) {
    OverflowStats stats;
    for (const NTHUR::Edge_2d& edge : congestion.congestionMap2d.all()) {
        const int overuse = std::max(0, edge.overUsage());
        stats.max_overflow = std::max(stats.max_overflow, overuse);
        stats.total_overflow += overuse;
    }
    return stats;
}

void collect_affected_overflow_edges(const std::vector<NTHUR::Coordinate_2d>& path,
        const NTHUR::Congestion& congestion,
        std::vector<AffectedOverflowEdge>& edges,
        std::unordered_set<std::uint64_t>& seen_edges) {
    for (int path_index = static_cast<int>(path.size()) - 2; path_index >= 0; --path_index) {
        const NTHUR::Coordinate_2d& from = path[path_index];
        const NTHUR::Coordinate_2d& to = path[path_index + 1];
        if (!seen_edges.insert(route_edge_key(from, to)).second) {
            continue;
        }
        const NTHUR::Edge_2d& edge = congestion.congestionMap2d.edge(from, to);
        edges.push_back(AffectedOverflowEdge {
                from, to, std::max(0, edge.overUsage()) });
    }
}

OverflowStats affected_overflow_stats(const NTHUR::Congestion& congestion,
        const std::vector<AffectedOverflowEdge>& affected_edges) {
    OverflowStats stats;
    for (const AffectedOverflowEdge& affected : affected_edges) {
        const NTHUR::Edge_2d& edge =
                congestion.congestionMap2d.edge(affected.from, affected.to);
        const int overuse = std::max(0, edge.overUsage());
        stats.max_overflow = std::max(stats.max_overflow, overuse);
        stats.total_overflow += overuse;
    }
    return stats;
}

int affected_overflow_before_total(
        const std::vector<AffectedOverflowEdge>& affected_edges) {
    int total = 0;
    for (const AffectedOverflowEdge& affected : affected_edges) {
        total += affected.before_overflow;
    }
    return total;
}

void collect_overflow_net_ids(const NTHUR::Congestion& congestion, std::vector<int>& net_ids) {
    net_ids.clear();
    std::unordered_set<int> seen;
    for (const NTHUR::Edge_2d& edge : congestion.congestionMap2d.all()) {
        if (!edge.isOverflow()) {
            continue;
        }
        for (const auto& net_usage : edge.used_net) {
            if (seen.insert(net_usage.first).second) {
                net_ids.push_back(net_usage.first);
            }
        }
    }
    std::sort(net_ids.begin(), net_ids.end());
}

void collect_overflow_route_edges(const NTHUR::Two_pin_element_2d& two_pin,
        const NTHUR::Congestion& congestion,
        std::vector<OverflowEdgeRef>& edges) {
    edges.clear();
    for (int path_index = static_cast<int>(two_pin.path.size()) - 2; path_index >= 0; --path_index) {
        const NTHUR::Coordinate_2d& from = two_pin.path[path_index];
        const NTHUR::Coordinate_2d& to = two_pin.path[path_index + 1];
        const NTHUR::Edge_2d& edge = congestion.congestionMap2d.edge(from, to);
        if (edge.isOverflow()) {
            edges.push_back(OverflowEdgeRef { route_edge_key(from, to), std::max(1, edge.overUsage()) });
        }
    }
}

void include_point_in_box(NTHUR::Rectangle& box, const NTHUR::Coordinate_2d& point) {
    box.upLeft.x = std::min(box.upLeft.x, point.x);
    box.upLeft.y = std::min(box.upLeft.y, point.y);
    box.downRight.x = std::max(box.downRight.x, point.x);
    box.downRight.y = std::max(box.downRight.y, point.y);
}

void include_path_in_box(NTHUR::Rectangle& box, const std::vector<NTHUR::Coordinate_2d>& path) {
    for (const NTHUR::Coordinate_2d& point : path) {
        include_point_in_box(box, point);
    }
}

void include_box_in_box(NTHUR::Rectangle& box, const NTHUR::Rectangle& other) {
    include_point_in_box(box, other.upLeft);
    include_point_in_box(box, other.downRight);
}

NTHUR::Rectangle reroute_conflict_box(const NTHUR::Two_pin_element_2d& two_pin,
        const NTHUR::Construct_2d_tree& construct_2d_tree,
        const NTHUR::Rectangle* net_path_box) {
    NTHUR::Rectangle box { two_pin.pin1, two_pin.pin2 };
    include_path_in_box(box, two_pin.path);
    if (net_path_box != nullptr) {
        include_box_in_box(box, *net_path_box);
    }

    const int dogleg_margin = dogleg_sample_step() * dogleg_sample_radius();
    box.expand(std::max(construct_2d_tree.BOXSIZE_INC, dogleg_margin) + 1);

    NTHUR::Rectangle grid_bound {
            NTHUR::Coordinate_2d { 0, 0 },
            NTHUR::Coordinate_2d {
                    construct_2d_tree.rr_map.get_gridx() - 1,
                    construct_2d_tree.rr_map.get_gridy() - 1 } };
    grid_bound.clip(box);
    return box;
}

RangeProfile range_profile;
}

bool NTHUR::RangeRouter::double_equal(double a, double b) {
    double diff = a - b;
    return !(diff > 0.00001 || diff < -0.00001);
}

/*sort grid_edge in decending order*/
bool NTHUR::RangeRouter::comp_grid_edge(const Grid_edge_element& a, const Grid_edge_element& b) {
    return congestion.congestionMap2d.edge(a.grid, a.c2).congestion() > congestion.congestionMap2d.edge(b.grid, b.c2).congestion();
}

/*
 determine INTERVAL_NUM(10) intervals between min and max,
 and also compute average congestion value (sum of demand / sum of capacity)
 */
void NTHUR::RangeRouter::define_interval() {

    Congestion::Statistic s = congestion.stat_congestion();

    interval_list[0].begin_value = s.max;

    for (u_int32_t i = 1; i < interval_list.size(); ++i) {
        interval_list[i].begin_value = s.max - ((double) i / interval_list.size()) * (s.max - 1.0);
        interval_list[i - 1].end_value = interval_list[i].begin_value;
    }
    interval_list[interval_list.size() - 1].end_value = 1.;
    for (Interval_element& ele : interval_list) {
        ele.grid_edge_vector.clear();
    }

}

std::string NTHUR::RangeRouter::print_interval() const {

    std::string s("interval value: ");
    for (uint32_t i = 0; i < interval_list.size(); ++i) {
        s += std::to_string(interval_list[i].begin_value) + " ";
    }
    s += std::to_string(interval_list[interval_list.size() - 1].end_value) + "\n";
    return s;
}

void NTHUR::RangeRouter::insert_to_interval(Coordinate_2d coor_2d, Coordinate_2d c2) {
    double cong_value = congestion.congestionMap2d.edge(coor_2d, c2).congestion();
    if (cong_value > 1) {
        for (int i = interval_list.size() - 1; i >= 0; --i) {
            Interval_element& ele = interval_list[i];
            if (((cong_value < ele.begin_value) || double_equal(cong_value, ele.begin_value)) && //
                    cong_value > ele.end_value) {
                ele.grid_edge_vector.push_back(Grid_edge_element(coor_2d, c2));
                return;
            }
        }
    }
}

void NTHUR::RangeRouter::divide_grid_edge_into_interval() {

#ifdef NTHU_ROUTE_OPENMP
    using LocalIntervals = std::array<std::vector<Grid_edge_element>, INTERVAL_NUM>;
    const int x_size = congestion.congestionMap2d.getXSize();
    const int y_size = congestion.congestionMap2d.getYSize();

    auto insert_local = [&](LocalIntervals& local, Coordinate_2d coor_2d, Coordinate_2d c2) {
        double cong_value = congestion.congestionMap2d.edge(coor_2d, c2).congestion();
        if (cong_value > 1) {
            for (int i = static_cast<int>(interval_list.size()) - 1; i >= 0; --i) {
                const Interval_element& ele = interval_list[i];
                if (((cong_value < ele.begin_value) || double_equal(cong_value, ele.begin_value)) && //
                        cong_value > ele.end_value) {
                    local[i].push_back(Grid_edge_element(coor_2d, c2));
                    return;
                }
            }
        }
    };

#pragma omp parallel
    {
        LocalIntervals local_intervals;

#pragma omp for schedule(static) nowait
        for (int i = 0; i < x_size - 1; ++i) {
            for (int j = 0; j < y_size; ++j) {
                insert_local(local_intervals, Coordinate_2d { i, j }, Coordinate_2d { i + 1, j });
            }
        }

#pragma omp for schedule(static) nowait
        for (int i = 0; i < x_size; ++i) {
            for (int j = 0; j < y_size - 1; ++j) {
                insert_local(local_intervals, Coordinate_2d { i, j }, Coordinate_2d { i, j + 1 });
            }
        }

#pragma omp critical
        {
            for (std::size_t i = 0; i < interval_list.size(); ++i) {
                interval_list[i].grid_edge_vector.insert(
                        interval_list[i].grid_edge_vector.end(),
                        local_intervals[i].begin(),
                        local_intervals[i].end());
            }
        }
    }
#else
    for (int i = 0; i < congestion.congestionMap2d.getXSize() - 1; ++i) {
        for (int j = 0; j < congestion.congestionMap2d.getYSize(); ++j) {
            insert_to_interval(Coordinate_2d { i, j }, Coordinate_2d { i + 1, j });
        }
    }
    for (int i = 0; i < congestion.congestionMap2d.getXSize(); ++i) {
        for (int j = 0; j < congestion.congestionMap2d.getYSize() - 1; ++j) {
            insert_to_interval(Coordinate_2d { i, j }, Coordinate_2d { i, j + 1 });
        }

    }
#endif

}

void NTHUR::RangeRouter::walkFrame(const Rectangle& r, std::function<void(Coordinate_2d& i, Coordinate_2d& before)> accumulate) {

    const Coordinate_2d& upLeft = r.upLeft;
    const Coordinate_2d& downRight = r.downRight;

    Coordinate_2d before { upLeft.x, std::min(upLeft.y + 1, downRight.y) };
    {
        Coordinate_2d corner { upLeft.x, upLeft.y };
        accumulate(corner, before);
        before.set(corner);
    }
    for (Coordinate_2d i { upLeft.x + 1, upLeft.y }; i.x < downRight.x; ++i.x) {
        accumulate(i, before);
        before.set(i);
        Coordinate_2d center { i.x, std::min(upLeft.y + 1, downRight.y) };
        accumulate(i, center);
    }

    {
        Coordinate_2d corner { downRight.x, upLeft.y };
        accumulate(corner, before);
        before.set(corner);
    }

    for (Coordinate_2d i { downRight.x, upLeft.y + 1 }; i.y < downRight.y; ++i.y) {
        accumulate(i, before);
        before.set(i);
        Coordinate_2d center { std::max(upLeft.x, downRight.x - 1), i.y };
        accumulate(i, center);

    }

    if (!downRight.isAligned(upLeft)) {
        {
            Coordinate_2d corner { downRight.x, downRight.y };
            accumulate(corner, before);
            before.set(corner);
        }
        for (Coordinate_2d i { downRight.x - 1, downRight.y }; i.x > upLeft.x; --i.x) {
            accumulate(i, before);
            before.set(i);
            if (upLeft.y < downRight.y - 1) {
                Coordinate_2d center { i.x, downRight.y - 1 };
                accumulate(i, center);
            }
        }
        {
            Coordinate_2d corner { upLeft.x, downRight.y };
            accumulate(corner, before);
            before.set(corner);
        }
        for (Coordinate_2d i { upLeft.x, downRight.y - 1 }; i.y > upLeft.y; --i.y) {
            accumulate(i, before);
            before.set(i);
            if (upLeft.x + 1 < downRight.x) {
                Coordinate_2d center { upLeft.x + 1, i.y };
                accumulate(i, center);
            }
        }
    }

}

void NTHUR::RangeRouter::expand_range(Coordinate_2d c1, Coordinate_2d c2, int interval_index) {

    Rectangle r { c1, c2 };
    Rectangle bound { Coordinate_2d { 0, 0 }, congestion.congestionMap2d.getSize() + Coordinate_2d { -1, -1 } };

    double total_cong = 0;
    int edge_num = 0;

    while (total_cong >= edge_num * interval_list[interval_index].end_value && !r.contains(bound)) {

        walkFrame(r, [&](Coordinate_2d& i,Coordinate_2d& before) {
            if (before != i) {
                if (bound.contains(i) && bound.contains(before)) {
                    total_cong += congestion.congestionMap2d.edge(i, before).congestion();
                    ++edge_num;
                    colorMap[i.x][i.y].expand = interval_index;
                }
            }
        });
        r.expand(1);
        SPDLOG_TRACE(log_sp, "r after  r.expand(1): {}", r.toString());
    }
    SPDLOG_TRACE(log_sp, "r: {} bound: {}", r.toString(), bound.toString());
    SPDLOG_TRACE(log_sp, "printIfBound:{}", printIfBound(r, bound, interval_index, c1, c2));

    r.expand(congestion.cur_iter / 10); // extraExpandRange
    bound.clip(r);
    SPDLOG_TRACE(log_sp, "r after clip: {}  bound: {}", r.toString(), bound.toString());
    range_vector.push_back(r);
}

std::string NTHUR::RangeRouter::printIfBound(const Rectangle& r, const Rectangle& bound, const int interval_index, const Coordinate_2d& c1, const Coordinate_2d& c2) const {
    std::string s;
    if (r.contains(bound)) {
        s += "for interval " + std::to_string(interval_index);
        s += ", its range is equal to the grid size, ";
        s += r.toString();
        s += " from edge (" + c1.toString() + ") (" + c2.toString() + ")";

    }
    return s;
}
//Rip-up the path that pass any overflowed edges, then route with monotonic 
//routing or multi-source multi-sink routing.
//If there is no overflowed path by using the two methods above, then remain 
//the original path.
void NTHUR::RangeRouter::range_router(Two_pin_element_2d& two_pin, int version) {
    (void) range_router(two_pin, version, nullptr, nullptr, true);
}

bool NTHUR::RangeRouter::range_router(Two_pin_element_2d& two_pin, int version,
        MonotonicRouting* local_monotonic, Multisource_multisink_mazeroute* local_maze,
        bool allow_maze) {
    static bool cuda_maze_runtime_disabled = false;
    static int cuda_maze_calls_used = 0;
    const bool use_local_scratch = local_monotonic != nullptr || local_maze != nullptr;
    const bool do_profile = profile_enabled() && !use_local_scratch;
    ProfileClock::time_point phase_start;
    if (do_profile) {
        ++range_profile.route_calls;
        phase_start = ProfileClock::now();
    }
    const bool old_path_has_overflow = !congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false);
    if (do_profile) {
        auto after_check = ProfileClock::now();
        range_profile.check_old_path_ms += profile_ms(phase_start, after_check);
        phase_start = after_check;
    }
    if (old_path_has_overflow) {
        int old_path_overflow_score = 0;
        int min_reroute_score = reroute_min_overflow_score();
        const int score_until_iter = reroute_score_until_iter();
        const int late_score_after_iter = reroute_late_score_after_iter();
        const int late_min_reroute_score = reroute_late_min_overflow_score();
        const bool require_post_improvement = version == 3 && post_accept_improvement_enabled();
        if (version == 2 && late_score_after_iter >= 0 && late_min_reroute_score > 0 &&
                congestion.cur_iter > late_score_after_iter) {
            min_reroute_score = late_min_reroute_score;
        }
        if ((version == 3 && reroute_score_p2_only_enabled()) ||
                (score_until_iter >= 0 && (version == 3 || congestion.cur_iter > score_until_iter))) {
            min_reroute_score = 1;
        }
        const bool cuda_maze_enabled_this_phase = !use_local_scratch &&
                (cuda_maze_fastpath_enabled() || cuda_costed_maze_fastpath_enabled()) &&
                (!cuda_maze_post_only_enabled() || version == 3);
        const bool bounded_length_enabled_this_phase =
                bounded_length_phase_enabled(version, congestion.cur_iter);
        if (dogleg_fastpath_enabled() || (!use_local_scratch && dump_candidates_enabled()) || min_reroute_score > 1 ||
                cuda_maze_enabled_this_phase || require_post_improvement ||
                bounded_length_enabled_this_phase) {
            for (int i = static_cast<int>(two_pin.path.size()) - 2; i >= 0; --i) {
                const Edge_2d& edge = congestion.congestionMap2d.edge(two_pin.path[i], two_pin.path[i + 1]);
                old_path_overflow_score += std::max(0, edge.overUsage());
            }
        }
        if (min_reroute_score > 1 && old_path_overflow_score < min_reroute_score) {
            return true;
        }
        if (!use_local_scratch) {
            dump_reroute_candidate(two_pin, congestion.cur_iter, old_path_overflow_score);
        }
        if (do_profile) {
            ++range_profile.actual_reroutes;
        }
#ifdef NTHU_ROUTE_OPENMP
#pragma omp atomic update
#endif
        ++total_twopin;

        if (use_local_scratch) {
#ifdef NTHU_ROUTE_OPENMP
#pragma omp critical(nthu_net_dirty)
#endif
            {
                construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
            }
        } else {
            construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
        }

        const std::vector<Coordinate_2d> original_path(two_pin.path);
        congestion.update_congestion_map_remove_two_pin_net(two_pin.path, two_pin.net_id);
        if (do_profile) {
            auto after_remove = ProfileClock::now();
            range_profile.remove_ms += profile_ms(phase_start, after_remove);
            phase_start = after_remove;
        }

        std::vector<Coordinate_2d> bound_path(two_pin.path);

        Bound bound;
        bool find_path_flag = false;
        bool used_trusted_cuda_dogleg = false;
        if (dogleg_fastpath_enabled() && old_path_overflow_score >= dogleg_min_overflow_score()) {
            const bool cuda_choice_available = cuda_dogleg_choices.find(&two_pin) != cuda_dogleg_choices.end();
            find_path_flag = try_cuda_dogleg_choice(two_pin);
            used_trusted_cuda_dogleg = find_path_flag && cuda_dogleg_legal_filter_enabled() &&
                    cuda_dogleg_trust_legal_filter_enabled();
            if (!find_path_flag &&
                    !(cuda_choice_available && cuda_dogleg_skip_cpu_fallback_enabled())) {
                find_path_flag = try_dogleg_fastpath(two_pin);
                used_trusted_cuda_dogleg = false;
            }
            if (find_path_flag) {
                bound_path = two_pin.path;
                if (do_profile) {
                    ++range_profile.l_shape_success;
                }
            }
        } else if (l_shape_fastpath_enabled()) {
            find_path_flag = try_l_shape_fastpath(two_pin);
            if (find_path_flag) {
                bound_path = two_pin.path;
                if (do_profile) {
                    ++range_profile.l_shape_success;
                }
            }
        }
        if (do_profile) {
            auto after_l_shape = ProfileClock::now();
            range_profile.l_shape_ms += profile_ms(phase_start, after_l_shape);
            phase_start = after_l_shape;
        }
        if (!find_path_flag) {
            MonotonicRouting& monotonic_router = local_monotonic != nullptr ? *local_monotonic : monotonicRouter;
            find_path_flag = monotonic_router.monotonicRoute(two_pin, bound, bound_path);
        }
        if (do_profile) {
            auto after_monotonic = ProfileClock::now();
            range_profile.monotonic_ms += profile_ms(phase_start, after_monotonic);
            phase_start = after_monotonic;
        }

        if (version == 2) {
            two_pin.done = construct_2d_tree.done_iter;
        }
        bool new_path_has_overflow = false;
        if (find_path_flag) {
            if (used_trusted_cuda_dogleg && cuda_dogleg_trust_final_check_enabled()) {
                new_path_has_overflow = false;
            } else {
                new_path_has_overflow = !congestion.check_path_no_overflow(bound_path, two_pin.net_id, true);
            }
        }
        if (do_profile) {
            auto after_new_check = ProfileClock::now();
            range_profile.check_new_path_ms += profile_ms(phase_start, after_new_check);
            phase_start = after_new_check;
        }
        if ((!find_path_flag) || new_path_has_overflow) {
            if (!allow_maze) {
                two_pin.path = original_path;
                two_pin.pin1 = two_pin.path.front();
                two_pin.pin2 = two_pin.path.back();
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
                return false;
            }
            Coordinate_2d start;
            Coordinate_2d end;

            start.x = min(two_pin.pin1.x, two_pin.pin2.x);
            start.y = min(two_pin.pin1.y, two_pin.pin2.y);
            end.x = max(two_pin.pin1.x, two_pin.pin2.x);
            end.y = max(two_pin.pin1.y, two_pin.pin2.y);

            int size = construct_2d_tree.BOXSIZE_INC;
            start.x = max(0, start.x - size);
            start.y = max(0, start.y - size);
            end.x = min(construct_2d_tree.rr_map.get_gridx() - 1, end.x + size);
            end.y = min(construct_2d_tree.rr_map.get_gridy() - 1, end.y + size);

            find_path_flag = false;
            const int cuda_maze_call_limit = cuda_maze_max_calls();
            const bool cuda_maze_under_call_limit =
                    cuda_maze_call_limit == 0 || cuda_maze_calls_used < cuda_maze_call_limit;
            if (cuda_maze_enabled_this_phase &&
                    old_path_overflow_score < cuda_maze_min_overflow_score() && do_profile) {
                ++range_profile.cuda_maze_score_skips;
            }
            if (cuda_maze_enabled_this_phase &&
                    !cuda_maze_under_call_limit && do_profile) {
                ++range_profile.cuda_maze_call_limit_skips;
            }
            if (cuda_maze_under_call_limit &&
                    cuda_maze_enabled_this_phase &&
                    old_path_overflow_score >= cuda_maze_min_overflow_score() &&
                    !cuda_maze_runtime_disabled && cuda_dogleg_available()) {
                const int box_width = end.x - start.x + 1;
                const int box_height = end.y - start.y + 1;
                const int box_area = box_width * box_height;
                if (box_area <= cuda_maze_max_area()) {
                    ++cuda_maze_calls_used;
                    std::vector<int> east_open(static_cast<std::size_t>(box_area), 0);
                    std::vector<int> south_open(static_cast<std::size_t>(box_area), 0);
                    std::vector<double> east_cost(static_cast<std::size_t>(box_area), 1.0e100);
                    std::vector<double> south_cost(static_cast<std::size_t>(box_area), 1.0e100);
                    for (int lx = 0; lx < box_width; ++lx) {
                        for (int ly = 0; ly < box_height; ++ly) {
                            const int index = ly * box_width + lx;
                            const Coordinate_2d c { start.x + lx, start.y + ly };
                            if (lx + 1 < box_width) {
                                const Coordinate_2d n { c.x + 1, c.y };
                                const Edge_2d& edge = congestion.congestionMap2d.edge(c, n);
                                east_open[index] = (edge.lookupNet(two_pin.net_id) ||
                                        edge.cur_cap + 1.0 <= edge.max_cap) ? 1 : 0;
                                east_cost[index] = edge.cost;
                            }
                            if (ly + 1 < box_height) {
                                const Coordinate_2d n { c.x, c.y + 1 };
                                const Edge_2d& edge = congestion.congestionMap2d.edge(c, n);
                                south_open[index] = (edge.lookupNet(two_pin.net_id) ||
                                        edge.cur_cap + 1.0 <= edge.max_cap) ? 1 : 0;
                                south_cost[index] = edge.cost;
                            }
                        }
                    }

                    std::vector<Coordinate_2d> cuda_path;
                    try {
                        auto cuda_maze_start = ProfileClock::now();
                        if (do_profile) {
                            ++range_profile.cuda_maze_attempts;
                        }
                        if (cuda_costed_maze_fastpath_enabled()) {
                            find_path_flag = cuda_find_costed_maze_path(box_width, box_height,
                                    east_open, south_open, east_cost, south_cost,
                                    two_pin.pin1.x - start.x, two_pin.pin1.y - start.y,
                                    two_pin.pin2.x - start.x, two_pin.pin2.y - start.y,
                                    start.x, start.y, cuda_path);
                        } else {
                            find_path_flag = cuda_find_legal_maze_path(box_width, box_height,
                                    east_open, south_open,
                                    two_pin.pin1.x - start.x, two_pin.pin1.y - start.y,
                                    two_pin.pin2.x - start.x, two_pin.pin2.y - start.y,
                                    start.x, start.y, cuda_path);
                        }
                        if (do_profile) {
                            range_profile.cuda_maze_ms += profile_ms(cuda_maze_start, ProfileClock::now());
                        }
                    } catch (const std::exception& e) {
                        cuda_maze_runtime_disabled = true;
                        log_sp->warn("CUDA maze fastpath disabled for this run: {}", e.what());
                        find_path_flag = false;
                    }
                    if (find_path_flag &&
                            (cuda_maze_trust_legal_path_enabled() ||
                                    congestion.check_path_no_overflow(cuda_path, two_pin.net_id, true))) {
                        two_pin.path = std::move(cuda_path);
                        if (do_profile) {
                            ++range_profile.cuda_maze_success;
                        }
                    } else {
                        find_path_flag = false;
                    }
                } else if (do_profile) {
                    ++range_profile.cuda_maze_area_skips;
                }
            }

            if (!find_path_flag) {
                const bool strict_legal_enabled_this_phase = strict_legal_maze_enabled() &&
                        (!strict_legal_maze_post_only_enabled() || version == 3) &&
                        congestion.cur_iter >= strict_legal_maze_min_iter();
                if (strict_legal_enabled_this_phase) {
                    std::vector<Coordinate_2d> legal_path;
                    if (find_strict_legal_maze_path(two_pin, congestion, start, end, legal_path)) {
                        two_pin.path = std::move(legal_path);
                        two_pin.pin1 = two_pin.path.front();
                        two_pin.pin2 = two_pin.path.back();
                        find_path_flag = true;
                    }
                }
            }

            if (!find_path_flag) {
                Multisource_multisink_mazeroute& maze_router =
                        local_maze != nullptr ? *local_maze : construct_2d_tree.mazeroute_in_range;
                const int max_path_edges =
                        bounded_length_enabled_this_phase ? bounded_length_limit(original_path) : -1;
                find_path_flag = maze_router.mm_maze_route_p(two_pin, bound.cost, bound.distance,
                        bound.via_num, start, end, version, max_path_edges);
            }
            if (do_profile) {
                auto after_maze = ProfileClock::now();
                range_profile.maze_ms += profile_ms(phase_start, after_maze);
                phase_start = after_maze;
            }

            if (!find_path_flag) {
                two_pin.path.insert(two_pin.path.begin(), bound_path.begin(), bound_path.end());
            }
        }

        if (find_path_flag && require_post_improvement) {
            const int new_path_overflow_score =
                    inserted_path_overflow_score(two_pin.path, two_pin.net_id, congestion);
            if (new_path_overflow_score + post_accept_min_delta() > old_path_overflow_score) {
                two_pin.path = original_path;
                two_pin.pin1 = two_pin.path.front();
                two_pin.pin2 = two_pin.path.back();
            }
        }

        if (find_path_flag && bounded_length_enabled_this_phase) {
            const int new_edges = path_edges(two_pin.path);
            const int max_edges = bounded_length_limit(original_path);
            if (new_edges > max_edges) {
                if (parallel_reroute_log_enabled() || profile_enabled()) {
                    log_sp->info("bounded-length reroute reject: net={} version={} iter={} old_edges={} new_edges={} max_edges={} old_overflow={}",
                            two_pin.net_id, version, congestion.cur_iter, path_edges(original_path),
                            new_edges, max_edges, old_path_overflow_score);
                }
                two_pin.path = original_path;
                two_pin.pin1 = two_pin.path.front();
                two_pin.pin2 = two_pin.path.back();
            }
        }

        congestion.update_congestion_map_insert_two_pin_net(two_pin);
        if (do_profile) {
            auto after_insert = ProfileClock::now();
            range_profile.insert_ms += profile_ms(phase_start, after_insert);
        }

    }
    return true;
}

bool NTHUR::RangeRouter::try_l_shape_fastpath(Two_pin_element_2d& two_pin) {
    auto build_path = [&](bool horizontal_first) {
        std::vector<Coordinate_2d> path;
        Coordinate_2d cur = two_pin.pin1;
        path.push_back(cur);
        auto move_x = [&]() {
            while (cur.x != two_pin.pin2.x) {
                cur.x += (two_pin.pin2.x > cur.x) ? 1 : -1;
                path.push_back(cur);
            }
        };
        auto move_y = [&]() {
            while (cur.y != two_pin.pin2.y) {
                cur.y += (two_pin.pin2.y > cur.y) ? 1 : -1;
                path.push_back(cur);
            }
        };
        if (horizontal_first) {
            move_x();
            move_y();
        } else {
            move_y();
            move_x();
        }
        return path;
    };

    auto path_cost = [&](const std::vector<Coordinate_2d>& path) {
        double cost = 0.0;
        for (int i = static_cast<int>(path.size()) - 2; i >= 0; --i) {
            cost += congestion.congestionMap2d.edge(path[i], path[i + 1]).cost;
        }
        return cost;
    };

    std::vector<Coordinate_2d> hv = build_path(true);
    std::vector<Coordinate_2d> vh = build_path(false);
    const bool hv_ok = congestion.check_path_no_overflow(hv, two_pin.net_id, true);
    const bool vh_ok = congestion.check_path_no_overflow(vh, two_pin.net_id, true);
    if (!hv_ok && !vh_ok) {
        return false;
    }
    if (hv_ok && (!vh_ok || path_cost(hv) <= path_cost(vh))) {
        two_pin.path = std::move(hv);
    } else {
        two_pin.path = std::move(vh);
    }
    two_pin.pin1 = two_pin.path.front();
    two_pin.pin2 = two_pin.path.back();
    return true;
}

bool NTHUR::RangeRouter::try_cuda_dogleg_choice(Two_pin_element_2d& two_pin) {
    auto choice_it = cuda_dogleg_choices.find(&two_pin);
    if (choice_it == cuda_dogleg_choices.end() || choice_it->second.valid == 0) {
        return false;
    }

    const int original_edges = static_cast<int>(two_pin.path.size()) - 1;
    const int max_edges = original_edges + dogleg_max_extra_length();
    const CudaDoglegChoice choice = choice_it->second;

    auto append_segment = [](std::vector<Coordinate_2d>& path, Coordinate_2d& cur, const Coordinate_2d& target) {
        while (cur.x != target.x) {
            cur.x += (target.x > cur.x) ? 1 : -1;
            if (path.empty() || path.back() != cur) {
                path.push_back(cur);
            }
        }
        while (cur.y != target.y) {
            cur.y += (target.y > cur.y) ? 1 : -1;
            if (path.empty() || path.back() != cur) {
                path.push_back(cur);
            }
        }
    };

    std::vector<Coordinate_2d> path;
    Coordinate_2d cur = two_pin.pin1;
    path.push_back(cur);
    if (choice.kind == 0) {
        append_segment(path, cur, Coordinate_2d { two_pin.pin2.x, two_pin.pin1.y });
    } else if (choice.kind == 1) {
        append_segment(path, cur, Coordinate_2d { two_pin.pin1.x, two_pin.pin2.y });
    } else if (choice.kind == 2) {
        append_segment(path, cur, Coordinate_2d { two_pin.pin1.x, choice.mid });
        append_segment(path, cur, Coordinate_2d { two_pin.pin2.x, choice.mid });
    } else if (choice.kind == 3) {
        append_segment(path, cur, Coordinate_2d { choice.mid, two_pin.pin1.y });
        append_segment(path, cur, Coordinate_2d { choice.mid, two_pin.pin2.y });
    } else {
        return false;
    }
    append_segment(path, cur, two_pin.pin2);

    const int path_edges = static_cast<int>(path.size()) - 1;
    const bool trust_cuda_legal_filter =
            cuda_dogleg_legal_filter_enabled() && cuda_dogleg_trust_legal_filter_enabled();
    if (path.size() < 2 || path_edges > max_edges) {
        return false;
    }
    if (!trust_cuda_legal_filter && !congestion.check_path_no_overflow(path, two_pin.net_id, true)) {
        return false;
    }

    two_pin.path = std::move(path);
    two_pin.pin1 = two_pin.path.front();
    two_pin.pin2 = two_pin.path.back();
    return true;
}

bool NTHUR::RangeRouter::try_dogleg_fastpath(Two_pin_element_2d& two_pin) {
    const int original_edges = static_cast<int>(two_pin.path.size()) - 1;
    const int max_edges = original_edges + dogleg_max_extra_length();

    auto append_segment = [](std::vector<Coordinate_2d>& path, Coordinate_2d& cur, const Coordinate_2d& target) {
        while (cur.x != target.x) {
            cur.x += (target.x > cur.x) ? 1 : -1;
            if (path.empty() || path.back() != cur) {
                path.push_back(cur);
            }
        }
        while (cur.y != target.y) {
            cur.y += (target.y > cur.y) ? 1 : -1;
            if (path.empty() || path.back() != cur) {
                path.push_back(cur);
            }
        }
    };

    auto build_via_y = [&](int mid_y) {
        std::vector<Coordinate_2d> path;
        Coordinate_2d cur = two_pin.pin1;
        path.push_back(cur);
        append_segment(path, cur, Coordinate_2d { two_pin.pin1.x, mid_y });
        append_segment(path, cur, Coordinate_2d { two_pin.pin2.x, mid_y });
        append_segment(path, cur, two_pin.pin2);
        return path;
    };

    auto build_via_x = [&](int mid_x) {
        std::vector<Coordinate_2d> path;
        Coordinate_2d cur = two_pin.pin1;
        path.push_back(cur);
        append_segment(path, cur, Coordinate_2d { mid_x, two_pin.pin1.y });
        append_segment(path, cur, Coordinate_2d { mid_x, two_pin.pin2.y });
        append_segment(path, cur, two_pin.pin2);
        return path;
    };

    auto path_cost = [&](const std::vector<Coordinate_2d>& path) {
        double cost = 0.0;
        for (int i = static_cast<int>(path.size()) - 2; i >= 0; --i) {
            cost += congestion.congestionMap2d.edge(path[i], path[i + 1]).cost;
        }
        return cost;
    };

    auto add_unique = [](std::vector<int>& values, int value, int low, int high) {
        value = std::max(low, std::min(high, value));
        if (std::find(values.begin(), values.end(), value) == values.end()) {
            values.push_back(value);
        }
    };

    const int x_low = 0;
    const int y_low = 0;
    const int x_high = congestion.congestionMap2d.getXSize() - 1;
    const int y_high = congestion.congestionMap2d.getYSize() - 1;
    const int step = dogleg_sample_step();
    const int radius = dogleg_sample_radius();
    const int mid_x = (two_pin.pin1.x + two_pin.pin2.x) / 2;
    const int mid_y = (two_pin.pin1.y + two_pin.pin2.y) / 2;

    std::vector<int> x_candidates;
    std::vector<int> y_candidates;
    for (int abs_r = 0; abs_r <= radius; ++abs_r) {
        for (int sign : { 1, -1 }) {
            if (abs_r == 0 && sign < 0) {
                continue;
            }
            const int delta = sign * abs_r * step;
            add_unique(x_candidates, two_pin.pin1.x + delta, x_low, x_high);
            add_unique(x_candidates, two_pin.pin2.x + delta, x_low, x_high);
            add_unique(x_candidates, mid_x + delta, x_low, x_high);
            add_unique(y_candidates, two_pin.pin1.y + delta, y_low, y_high);
            add_unique(y_candidates, two_pin.pin2.y + delta, y_low, y_high);
            add_unique(y_candidates, mid_y + delta, y_low, y_high);
        }
    }

    bool found = false;
    double best_cost = std::numeric_limits<double>::infinity();
    std::vector<Coordinate_2d> best_path;
    auto consider = [&](std::vector<Coordinate_2d> path) {
        const int path_edges = static_cast<int>(path.size()) - 1;
        if (path.size() < 2 || path_edges > max_edges ||
                !congestion.check_path_no_overflow(path, two_pin.net_id, true)) {
            return;
        }
        const double cost = path_cost(path);
        if (!found || cost < best_cost) {
            found = true;
            best_cost = cost;
            best_path = std::move(path);
        }
    };

    for (int y : y_candidates) {
        consider(build_via_y(y));
    }
    for (int x : x_candidates) {
        consider(build_via_x(x));
    }

    if (!found) {
        return false;
    }
    two_pin.path = std::move(best_path);
    two_pin.pin1 = two_pin.path.front();
    two_pin.pin2 = two_pin.path.back();
    return true;
}

bool NTHUR::RangeRouter::propose_reroute_path(const Two_pin_element_2d& two_pin, int version,
        MonotonicRouting& local_monotonic, Multisource_multisink_mazeroute* local_maze,
        bool allow_maze, std::vector<Coordinate_2d>& proposed_path,
        bool old_path_removed, int known_old_path_overflow_score) {
    proposed_path.clear();
    if (!old_path_removed && congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false)) {
        return false;
    }

    int old_path_overflow_score = known_old_path_overflow_score;
    if (old_path_overflow_score < 0) {
        old_path_overflow_score = 0;
        for (int i = static_cast<int>(two_pin.path.size()) - 2; i >= 0; --i) {
            const Edge_2d& edge = congestion.congestionMap2d.edge(two_pin.path[i], two_pin.path[i + 1]);
            old_path_overflow_score += std::max(0, edge.overUsage());
        }
    }

    int min_reroute_score = reroute_min_overflow_score();
    const int score_until_iter = reroute_score_until_iter();
    const int late_score_after_iter = reroute_late_score_after_iter();
    const int late_min_reroute_score = reroute_late_min_overflow_score();
    const bool require_post_improvement = version == 3 && post_accept_improvement_enabled();
    if (version == 2 && late_score_after_iter >= 0 && late_min_reroute_score > 0 &&
            congestion.cur_iter > late_score_after_iter) {
        min_reroute_score = late_min_reroute_score;
    }
    if ((version == 3 && reroute_score_p2_only_enabled()) ||
            (score_until_iter >= 0 && (version == 3 || congestion.cur_iter > score_until_iter))) {
        min_reroute_score = 1;
    }
    if (min_reroute_score > 1 && old_path_overflow_score < min_reroute_score) {
        return false;
    }

    Two_pin_element_2d candidate(two_pin);
    const std::vector<Coordinate_2d> original_path(two_pin.path);
    std::vector<Coordinate_2d> bound_path(two_pin.path);

    Bound bound;
    bool find_path_flag = false;
    if (dogleg_fastpath_enabled() && old_path_overflow_score >= dogleg_min_overflow_score()) {
        find_path_flag = try_dogleg_fastpath(candidate);
        if (find_path_flag) {
            bound_path = candidate.path;
        }
    } else if (l_shape_fastpath_enabled()) {
        find_path_flag = try_l_shape_fastpath(candidate);
        if (find_path_flag) {
            bound_path = candidate.path;
        }
    }

    if (!find_path_flag) {
        find_path_flag = local_monotonic.monotonicRoute(candidate, bound, bound_path);
    } else {
        Monotonic_element mn;
        local_monotonic.compute_path_total_cost_and_distance(candidate, mn);
        bound.cost = mn.total_cost;
        bound.distance = mn.distance;
        bound.via_num = mn.via_num;
        bound.flag = true;
    }

    bool new_path_has_overflow = false;
    if (find_path_flag) {
        new_path_has_overflow = !congestion.check_path_no_overflow(bound_path, candidate.net_id, true);
    }

    if ((!find_path_flag || new_path_has_overflow) && allow_maze && local_maze != nullptr) {
        Coordinate_2d start;
        Coordinate_2d end;

        start.x = min(two_pin.pin1.x, two_pin.pin2.x);
        start.y = min(two_pin.pin1.y, two_pin.pin2.y);
        end.x = max(two_pin.pin1.x, two_pin.pin2.x);
        end.y = max(two_pin.pin1.y, two_pin.pin2.y);

        int size = construct_2d_tree.BOXSIZE_INC;
        start.x = max(0, start.x - size);
        start.y = max(0, start.y - size);
        end.x = min(construct_2d_tree.rr_map.get_gridx() - 1, end.x + size);
        end.y = min(construct_2d_tree.rr_map.get_gridy() - 1, end.y + size);

        candidate = two_pin;
        const bool bounded_length_enabled_this_phase =
                bounded_length_phase_enabled(version, congestion.cur_iter);
        const int max_path_edges =
                bounded_length_enabled_this_phase ? bounded_length_limit(original_path) : -1;
        const bool strict_legal_enabled_this_phase = strict_legal_maze_enabled() &&
                (!strict_legal_maze_post_only_enabled() || version == 3) &&
                congestion.cur_iter >= strict_legal_maze_min_iter();
        if (strict_legal_enabled_this_phase) {
            std::vector<Coordinate_2d> legal_path;
            if (find_strict_legal_maze_path(candidate, congestion, start, end, legal_path)) {
                candidate.path = std::move(legal_path);
                candidate.pin1 = candidate.path.front();
                candidate.pin2 = candidate.path.back();
                find_path_flag = true;
            }
        }
        if (!find_path_flag) {
            find_path_flag = local_maze->mm_maze_route_p(candidate, bound.cost, bound.distance,
                    bound.via_num, start, end, version, max_path_edges);
        }
    }

    if (!find_path_flag || candidate.path.size() < 2) {
        return false;
    }

    const bool bounded_length_enabled_this_phase =
            bounded_length_phase_enabled(version, congestion.cur_iter);
    if (bounded_length_enabled_this_phase &&
            path_edges(candidate.path) > bounded_length_limit(original_path)) {
        return false;
    }

    if (require_post_improvement) {
        const int new_path_overflow_score =
                inserted_path_overflow_score(candidate.path, candidate.net_id, congestion);
        if (new_path_overflow_score + post_accept_min_delta() > old_path_overflow_score) {
            return false;
        }
    }

    proposed_path = std::move(candidate.path);
    return true;
}

bool NTHUR::RangeRouter::commit_reroute_proposal(Two_pin_element_2d& two_pin,
        const std::vector<Coordinate_2d>& proposed_path, int version,
        bool old_path_removed, int known_old_path_overflow_score,
        int phase_start_total_overflow, bool* accepted_by_global_gate,
        bool* evaluated_global_gate) {
    if (accepted_by_global_gate != nullptr) {
        *accepted_by_global_gate = false;
    }
    if (evaluated_global_gate != nullptr) {
        *evaluated_global_gate = false;
    }
    if (proposed_path.size() < 2 ||
            (!old_path_removed && congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false))) {
        return false;
    }

    const bool improvement_commit = proposal_reroute_improvement_commit_enabled();
    int old_path_overflow_score = improvement_commit ? known_old_path_overflow_score : 0;
    if (improvement_commit && old_path_overflow_score < 0) {
        old_path_overflow_score = path_overflow_score(two_pin, congestion);
    }
    const std::vector<Coordinate_2d> original_path(two_pin.path);
    const Coordinate_2d original_pin1 = two_pin.pin1;
    const Coordinate_2d original_pin2 = two_pin.pin2;

    if (!old_path_removed) {
        congestion.update_congestion_map_remove_two_pin_net(original_path, two_pin.net_id);
    }
    bool accept = false;
    if (improvement_commit) {
        const int new_path_overflow_score =
                inserted_path_overflow_score(proposed_path, two_pin.net_id, congestion);
        accept = new_path_overflow_score + post_accept_min_delta() <= old_path_overflow_score;
    } else {
        accept = congestion.check_path_no_overflow(proposed_path, two_pin.net_id, true);
    }

    const int global_commit_limit = proposal_reroute_global_commit_limit();
    if (!accept && improvement_commit && global_commit_limit > 0 &&
            phase_start_total_overflow > 0 && phase_start_total_overflow <= global_commit_limit) {
        if (evaluated_global_gate != nullptr) {
            *evaluated_global_gate = true;
        }
        two_pin.path = original_path;
        two_pin.pin1 = original_pin1;
        two_pin.pin2 = original_pin2;
        congestion.update_congestion_map_insert_two_pin_net(two_pin);
        const OverflowStats old_stats = current_overflow_stats(congestion);
        congestion.update_congestion_map_remove_two_pin_net(original_path, two_pin.net_id);

        if (old_stats.total_overflow > 0 && old_stats.total_overflow <= global_commit_limit) {
            two_pin.path = proposed_path;
            two_pin.pin1 = two_pin.path.front();
            two_pin.pin2 = two_pin.path.back();
            congestion.update_congestion_map_insert_two_pin_net(two_pin);
            const OverflowStats new_stats = current_overflow_stats(congestion);
            congestion.update_congestion_map_remove_two_pin_net(proposed_path, two_pin.net_id);

            accept = new_stats.total_overflow < old_stats.total_overflow;
            if (accept && accepted_by_global_gate != nullptr) {
                *accepted_by_global_gate = true;
            }
        }
    }

    if (!accept) {
        two_pin.path = original_path;
        two_pin.pin1 = original_pin1;
        two_pin.pin2 = original_pin2;
        congestion.update_congestion_map_insert_two_pin_net(two_pin);
        return false;
    }

    two_pin.path = proposed_path;
    two_pin.pin1 = two_pin.path.front();
    two_pin.pin2 = two_pin.path.back();
    if (version == 2) {
        two_pin.done = construct_2d_tree.done_iter;
    }
    construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
    congestion.update_congestion_map_insert_two_pin_net(two_pin);
    return true;
}

void NTHUR::RangeRouter::run_v8_strict_legal_repair(
        std::vector<Two_pin_element_2d*>& twopin_list, int version) {
    if (!v8_strict_legal_repair_enabled() || twopin_list.empty()) {
        return;
    }

    const bool do_log = profile_enabled() || proposal_reroute_log_enabled();
    if (v8_strict_legal_repair_post_only_enabled() && version != 3) {
        if (do_log) {
            log_sp->info("v8 strict legal repair skipped: post_only=1 version={}", version);
        }
        return;
    }
    OverflowStats stats = current_overflow_stats(congestion);
    const int trigger = v8_strict_legal_repair_trigger();
    const int max_overflow = v8_strict_legal_repair_max_overflow();
    if (stats.total_overflow <= 0 || stats.total_overflow < trigger ||
            stats.total_overflow > max_overflow) {
        if (do_log) {
            log_sp->info("v8 strict legal repair skipped: total_overflow={} max_overflow={} trigger={} max_total={}",
                    stats.total_overflow, stats.max_overflow, trigger, max_overflow);
        }
        return;
    }

    const int rounds = v8_strict_legal_repair_rounds();
    const int max_candidates = v8_strict_legal_repair_max_candidates();
    const int batch_size = v8_strict_legal_repair_batch_size();
    const int edge_quota = v8_strict_legal_repair_edge_quota();
    const int fixed_base_box = v8_strict_legal_repair_fixed_base_box();
    const int base_box = fixed_base_box >= 0
            ? fixed_base_box
            : std::max(construct_2d_tree.BOXSIZE_INC,
                    v8_strict_legal_repair_base_box());
    const int box_inc = v8_strict_legal_repair_box_inc();
    const int max_no_progress = v8_strict_legal_repair_max_no_progress();
    const bool snapshot_commit = v8_strict_legal_repair_snapshot_commit_enabled();
    const int snapshot_commit_max_overflow =
            v8_strict_legal_repair_snapshot_commit_max_overflow();
    const bool snapshot_rollback =
            v8_strict_legal_repair_snapshot_rollback_enabled();
    const bool rollback_no_progress =
            v8_strict_legal_repair_rollback_no_progress_enabled();
    const bool snapshot_global_gate =
            v8_strict_legal_repair_snapshot_global_gate_enabled();
    const int snapshot_burst_total =
            v8_strict_legal_repair_snapshot_burst_total();
    const int snapshot_burst_max =
            v8_strict_legal_repair_snapshot_burst_max();
    const bool improvement_commit = v8_strict_legal_repair_improvement_commit_enabled();
    const bool reuse_inputs = v8_strict_legal_repair_reuse_inputs_enabled();
    const bool overflow_net_inputs =
            v8_strict_legal_repair_overflow_net_inputs_enabled();

    int total_inputs = 0;
    int total_selected = 0;
    int total_proposed = 0;
    int total_committed = 0;
    int total_rejected = 0;
    int total_rolled_back = 0;
    int total_global_gated = 0;
    int total_snapshot_burst = 0;
    int total_global_burst_committed = 0;
    int no_progress_rounds = 0;
    double total_proposal_ms = 0.0;
    double total_commit_ms = 0.0;

    if (do_log) {
        log_sp->info("v8 strict legal repair enabled: total_overflow={} max_overflow={} trigger={} max_total={} rounds={} max_candidates={} batch_size={} edge_quota={} base_box={} fixed_base_box={} box_inc={} snapshot_commit={} snapshot_commit_max={} snapshot_rollback={} rollback_no_progress={} snapshot_global_gate={} snapshot_burst_total={} snapshot_burst_max={} improvement_commit={} reuse_inputs={} overflow_net_inputs={}",
                stats.total_overflow, stats.max_overflow, trigger, max_overflow,
                rounds, max_candidates, batch_size, edge_quota, base_box,
                fixed_base_box, box_inc, snapshot_commit,
                snapshot_commit_max_overflow, snapshot_rollback, rollback_no_progress,
                snapshot_global_gate, snapshot_burst_total, snapshot_burst_max,
                improvement_commit, reuse_inputs, overflow_net_inputs);
    }

    std::unordered_map<int, std::vector<Two_pin_element_2d*>> twopins_by_net;
    if (overflow_net_inputs) {
        twopins_by_net.reserve(twopin_list.size());
        for (Two_pin_element_2d* two_pin : twopin_list) {
            twopins_by_net[two_pin->net_id].push_back(two_pin);
        }
    }

    auto append_overflow_input = [&](Two_pin_element_2d* two_pin,
            std::vector<StrictRepairInput>& inputs) {
        const int score = path_overflow_score(*two_pin, congestion);
        if (score > 0) {
            inputs.push_back(StrictRepairInput { two_pin, score });
        }
    };

    auto collect_full_inputs = [&]() {
        std::vector<StrictRepairInput> inputs;
        inputs.reserve(twopin_list.size());
        for (Two_pin_element_2d* two_pin : twopin_list) {
            append_overflow_input(two_pin, inputs);
        }
        return inputs;
    };

    std::vector<StrictRepairInput> reusable_inputs;
    for (int round = 1; round <= rounds && stats.total_overflow > 0; ++round) {
        const OverflowStats round_start_stats = stats;
        std::vector<StrictRepairInput> inputs;
        if (overflow_net_inputs) {
            std::vector<int> overflow_net_ids;
            collect_overflow_net_ids(congestion, overflow_net_ids);
            inputs.reserve(std::min(twopin_list.size(), overflow_net_ids.size() * 4));
            for (int net_id : overflow_net_ids) {
                const auto net_twopins = twopins_by_net.find(net_id);
                if (net_twopins == twopins_by_net.end()) {
                    continue;
                }
                for (Two_pin_element_2d* two_pin : net_twopins->second) {
                    append_overflow_input(two_pin, inputs);
                }
            }
            if (inputs.empty()) {
                inputs = collect_full_inputs();
            }
        } else if (reuse_inputs && !reusable_inputs.empty()) {
            inputs.reserve(reusable_inputs.size());
            for (const StrictRepairInput& previous_input : reusable_inputs) {
                append_overflow_input(previous_input.two_pin, inputs);
            }
        } else {
            inputs = collect_full_inputs();
        }
        if (inputs.empty()) {
            break;
        }
        std::sort(inputs.begin(), inputs.end(),
                [](const StrictRepairInput& a, const StrictRepairInput& b) {
                    if (a.overflow_score != b.overflow_score) {
                        return a.overflow_score > b.overflow_score;
                    }
                    return Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
                });
        if (max_candidates < static_cast<int>(inputs.size())) {
            inputs.resize(max_candidates);
        }
        if (reuse_inputs) {
            reusable_inputs = inputs;
        }

        std::vector<Two_pin_element_2d*> selected;
        selected.reserve(std::min(batch_size, static_cast<int>(inputs.size())));
        std::unordered_set<int> selected_net_ids;
        selected_net_ids.reserve(std::min(batch_size, static_cast<int>(inputs.size())));
        std::unordered_map<std::uint64_t, int> selected_overflow_edges;
        selected_overflow_edges.reserve(std::min(batch_size * 4, static_cast<int>(inputs.size()) * 2));
        std::vector<OverflowEdgeRef> overflow_edges;
        int conflict_skipped = 0;
        for (const StrictRepairInput& input : inputs) {
            if (static_cast<int>(selected.size()) >= batch_size) {
                break;
            }
            bool conflict = selected_net_ids.find(input.two_pin->net_id) != selected_net_ids.end();
            collect_overflow_route_edges(*input.two_pin, congestion, overflow_edges);
            if (!conflict) {
                for (const OverflowEdgeRef& edge : overflow_edges) {
                    const auto edge_count = selected_overflow_edges.find(edge.key);
                    const int used_count = edge_count == selected_overflow_edges.end() ? 0 : edge_count->second;
                    if (used_count >= edge_quota) {
                        conflict = true;
                        break;
                    }
                }
            }
            if (conflict) {
                ++conflict_skipped;
                continue;
            }
            selected_net_ids.insert(input.two_pin->net_id);
            for (const OverflowEdgeRef& edge : overflow_edges) {
                ++selected_overflow_edges[edge.key];
            }
            selected.push_back(input.two_pin);
        }
        if (selected.empty()) {
            break;
        }

        std::vector<StrictRepairState> states(selected.size());
        for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
            Two_pin_element_2d& two_pin = *selected[i];
            states[i].original_path = two_pin.path;
            states[i].original_pin1 = two_pin.pin1;
            states[i].original_pin2 = two_pin.pin2;
        }
        for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
            congestion.update_congestion_map_remove_two_pin_net(states[i].original_path,
                    selected[i]->net_id);
        }

        std::vector<RerouteProposal> proposals(selected.size());
        const int repair_box = base_box + (round - 1) * box_inc;
        const auto proposal_start = ProfileClock::now();
#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(dynamic, 1)
#endif
        for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
            proposals[i].two_pin = selected[i];
            proposals[i].proposed = find_strict_legal_path_with_box(*selected[i],
                    congestion, construct_2d_tree, repair_box, proposals[i].path);
        }
        const double proposal_ms_value = profile_ms(proposal_start, ProfileClock::now());

        const auto commit_start = ProfileClock::now();
        int proposed = 0;
        int committed = 0;
        int rejected = 0;
        bool rolled_back = false;
        bool global_gated = false;
        bool snapshot_burst = false;
        int global_burst_committed = 0;
        const bool use_snapshot_commit = snapshot_commit &&
                round_start_stats.total_overflow <= snapshot_commit_max_overflow;
        auto restore_selected_originals = [&]() {
            for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
                Two_pin_element_2d& two_pin = *selected[i];
                congestion.update_congestion_map_remove_two_pin_net(two_pin.path,
                        two_pin.net_id);
            }
            for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
                Two_pin_element_2d& two_pin = *selected[i];
                two_pin.path = states[i].original_path;
                two_pin.pin1 = states[i].original_pin1;
                two_pin.pin2 = states[i].original_pin2;
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
            }
        };
        if (use_snapshot_commit) {
            for (RerouteProposal& proposal : proposals) {
                if (!proposal.proposed || proposal.path.size() < 2) {
                    continue;
                }
                ++proposed;
                Two_pin_element_2d& two_pin = *proposal.two_pin;
                if (congestion.check_path_no_overflow(proposal.path, two_pin.net_id, true)) {
                    two_pin.path = proposal.path;
                    two_pin.pin1 = two_pin.path.front();
                    two_pin.pin2 = two_pin.path.back();
                    if (version == 2) {
                        two_pin.done = construct_2d_tree.done_iter;
                    }
                    construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
                    congestion.update_congestion_map_insert_two_pin_net(two_pin);
                    proposal.committed = true;
                    ++committed;
                } else {
                    proposal.rejected = true;
                    ++rejected;
                }
            }
            for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
                if (proposals[i].committed) {
                    continue;
                }
                Two_pin_element_2d& two_pin = *selected[i];
                two_pin.path = states[i].original_path;
                two_pin.pin1 = states[i].original_pin1;
                two_pin.pin2 = states[i].original_pin2;
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
            }
        } else {
            for (int i = 0; i < static_cast<int>(selected.size()); ++i) {
                Two_pin_element_2d& two_pin = *selected[i];
                two_pin.path = states[i].original_path;
                two_pin.pin1 = states[i].original_pin1;
                two_pin.pin2 = states[i].original_pin2;
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
            }

            for (RerouteProposal& proposal : proposals) {
                if (!proposal.proposed || proposal.path.size() < 2) {
                    continue;
                }
                ++proposed;
                Two_pin_element_2d& two_pin = *proposal.two_pin;
                if (congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false)) {
                    continue;
                }

                const int original_overflow_score = improvement_commit
                        ? path_overflow_score(two_pin, congestion)
                        : 0;
                const std::vector<Coordinate_2d> original_path(two_pin.path);
                const Coordinate_2d original_pin1 = two_pin.pin1;
                const Coordinate_2d original_pin2 = two_pin.pin2;
                congestion.update_congestion_map_remove_two_pin_net(original_path, two_pin.net_id);

                const bool accept_proposal = improvement_commit
                        ? (inserted_path_overflow_score(proposal.path, two_pin.net_id, congestion)
                                < original_overflow_score)
                        : congestion.check_path_no_overflow(proposal.path, two_pin.net_id, true);
                if (accept_proposal) {
                    two_pin.path = proposal.path;
                    two_pin.pin1 = two_pin.path.front();
                    two_pin.pin2 = two_pin.path.back();
                    if (version == 2) {
                        two_pin.done = construct_2d_tree.done_iter;
                    }
                    construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
                    congestion.update_congestion_map_insert_two_pin_net(two_pin);
                    proposal.committed = true;
                    ++committed;
                    continue;
                }

                two_pin.path = original_path;
                two_pin.pin1 = original_pin1;
                two_pin.pin2 = original_pin2;
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
                proposal.rejected = true;
                ++rejected;
            }
        }
        const double commit_ms_value = profile_ms(commit_start, ProfileClock::now());
        stats = current_overflow_stats(congestion);

        const bool snapshot_worsened = use_snapshot_commit &&
                (stats.total_overflow > round_start_stats.total_overflow ||
                (stats.total_overflow == round_start_stats.total_overflow &&
                        stats.max_overflow > round_start_stats.max_overflow));
        const bool snapshot_burst_allowed = snapshot_worsened &&
                snapshot_burst_total > 0 && round < rounds &&
                stats.total_overflow <= round_start_stats.total_overflow + snapshot_burst_total &&
                stats.max_overflow <= round_start_stats.max_overflow + snapshot_burst_max;
        if (snapshot_burst_allowed) {
            snapshot_burst = true;
        } else if (snapshot_worsened && snapshot_global_gate) {
            restore_selected_originals();
            stats = current_overflow_stats(congestion);
            committed = 0;
            rejected = 0;
            global_gated = true;
            std::vector<AffectedOverflowEdge> affected_edges;
            std::unordered_set<std::uint64_t> affected_seen;
            for (RerouteProposal& proposal : proposals) {
                proposal.committed = false;
                proposal.rejected = false;
                if (!proposal.proposed || proposal.path.size() < 2) {
                    continue;
                }
                Two_pin_element_2d& two_pin = *proposal.two_pin;
                if (congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false)) {
                    proposal.rejected = true;
                    ++rejected;
                    continue;
                }

                const OverflowStats before_stats = stats;
                const std::vector<Coordinate_2d> original_path(two_pin.path);
                const Coordinate_2d original_pin1 = two_pin.pin1;
                const Coordinate_2d original_pin2 = two_pin.pin2;

                affected_edges.clear();
                affected_seen.clear();
                const std::size_t affected_reserve =
                        original_path.size() + proposal.path.size();
                if (affected_edges.capacity() < affected_reserve) {
                    affected_edges.reserve(affected_reserve);
                }
                affected_seen.reserve(affected_reserve);
                collect_affected_overflow_edges(original_path, congestion,
                        affected_edges, affected_seen);
                collect_affected_overflow_edges(proposal.path, congestion,
                        affected_edges, affected_seen);
                const int before_affected_overflow =
                        affected_overflow_before_total(affected_edges);

                congestion.update_congestion_map_remove_two_pin_net(original_path,
                        two_pin.net_id);

                two_pin.path = proposal.path;
                two_pin.pin1 = two_pin.path.front();
                two_pin.pin2 = two_pin.path.back();
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
                const OverflowStats affected_after_stats =
                        affected_overflow_stats(congestion, affected_edges);
                OverflowStats after_stats = stats;
                after_stats.total_overflow +=
                        affected_after_stats.total_overflow - before_affected_overflow;
                after_stats.max_overflow =
                        std::max(after_stats.max_overflow,
                                affected_after_stats.max_overflow);

                const bool improves_global =
                        after_stats.total_overflow < before_stats.total_overflow ||
                        (after_stats.total_overflow == before_stats.total_overflow &&
                                after_stats.max_overflow < before_stats.max_overflow);
                const bool accept_bounded_global =
                        !improves_global && snapshot_burst_total > 0 && round < rounds &&
                        after_stats.total_overflow <=
                                round_start_stats.total_overflow + snapshot_burst_total &&
                        after_stats.max_overflow <=
                                round_start_stats.max_overflow + snapshot_burst_max;
                const bool accept_global = improves_global || accept_bounded_global;
                if (accept_global) {
                    if (version == 2) {
                        two_pin.done = construct_2d_tree.done_iter;
                    }
                    construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
                    proposal.committed = true;
                    stats = after_stats;
                    ++committed;
                    if (accept_bounded_global) {
                        ++global_burst_committed;
                    }
                    continue;
                }

                congestion.update_congestion_map_remove_two_pin_net(proposal.path,
                        two_pin.net_id);
                two_pin.path = original_path;
                two_pin.pin1 = original_pin1;
                two_pin.pin2 = original_pin2;
                congestion.update_congestion_map_insert_two_pin_net(two_pin);
                proposal.rejected = true;
                ++rejected;
            }
            stats = current_overflow_stats(congestion);
        } else if (snapshot_worsened && snapshot_rollback) {
            restore_selected_originals();
            stats = current_overflow_stats(congestion);
            committed = 0;
            rejected = proposed;
            rolled_back = true;
        }

        const bool round_improved =
                stats.total_overflow < round_start_stats.total_overflow ||
                (stats.total_overflow == round_start_stats.total_overflow &&
                        stats.max_overflow < round_start_stats.max_overflow);
        if (rollback_no_progress && !round_improved && committed > 0 && snapshot_rollback) {
            restore_selected_originals();
            stats = current_overflow_stats(congestion);
            committed = 0;
            rejected = proposed;
            rolled_back = true;
        }

        total_inputs += static_cast<int>(inputs.size());
        total_selected += static_cast<int>(selected.size());
        total_proposed += proposed;
        total_committed += committed;
        total_rejected += rejected;
        if (rolled_back) {
            ++total_rolled_back;
        }
        if (global_gated) {
            ++total_global_gated;
        }
        if (snapshot_burst) {
            ++total_snapshot_burst;
        }
        total_global_burst_committed += global_burst_committed;
        total_proposal_ms += proposal_ms_value;
        total_commit_ms += commit_ms_value;

        if (do_log) {
            log_sp->info("v8 strict legal repair round={} inputs={} selected={} conflict_skipped={} proposed={} committed={} rejected={} snapshot_round={} snapshot_burst={} global_gated={} global_burst_committed={} rolled_back={} total_overflow={} max_overflow={} box={} edge_quota={} proposal_ms={:.3f} commit_ms={:.3f}",
                    round, inputs.size(), selected.size(), conflict_skipped, proposed,
                    committed, rejected, use_snapshot_commit, snapshot_burst,
                    global_gated, global_burst_committed, rolled_back, stats.total_overflow,
                    stats.max_overflow, repair_box, edge_quota, proposal_ms_value,
                    commit_ms_value);
        }

        const bool progress =
                stats.total_overflow < round_start_stats.total_overflow ||
                (stats.total_overflow == round_start_stats.total_overflow &&
                        stats.max_overflow < round_start_stats.max_overflow);
        const bool no_progress =
                rollback_no_progress ? !progress : committed == 0;
        if (no_progress) {
            ++no_progress_rounds;
            if (no_progress_rounds >= max_no_progress) {
                break;
            }
        } else {
            no_progress_rounds = 0;
        }
    }

    if (do_log) {
        log_sp->info("v8 strict legal repair phase inputs={} selected={} proposed={} committed={} rejected={} global_gated={} global_burst_committed={} rolled_back={} snapshot_burst={} total_overflow={} max_overflow={} proposal_ms={:.3f} commit_ms={:.3f}",
                total_inputs, total_selected, total_proposed, total_committed,
                total_rejected, total_global_gated, total_global_burst_committed,
                total_rolled_back, total_snapshot_burst, stats.total_overflow,
                stats.max_overflow, total_proposal_ms, total_commit_ms);
    }
}

void NTHUR::RangeRouter::route_twopin_candidates(std::vector<Two_pin_element_2d*>& twopin_list, int version) {
    if (proposal_reroute_batches_enabled() && !twopin_list.empty()) {
        const bool do_profile = profile_enabled();
        const bool do_log = do_profile || proposal_reroute_log_enabled();
        struct ProposalInput {
            Two_pin_element_2d* two_pin;
            int overflow_score;
        };
        struct RippedPathState {
            std::vector<Coordinate_2d> original_path;
            Coordinate_2d original_pin1;
            Coordinate_2d original_pin2;
            int old_overflow_score = -1;
            bool removed = false;
        };
        int min_reroute_score = reroute_min_overflow_score();
        const int score_until_iter = reroute_score_until_iter();
        const int late_score_after_iter = reroute_late_score_after_iter();
        const int late_min_reroute_score = reroute_late_min_overflow_score();
        if (version == 2 && late_score_after_iter >= 0 && late_min_reroute_score > 0 &&
                congestion.cur_iter > late_score_after_iter) {
            min_reroute_score = late_min_reroute_score;
        }
        if ((version == 3 && reroute_score_p2_only_enabled()) ||
                (score_until_iter >= 0 && (version == 3 || congestion.cur_iter > score_until_iter))) {
            min_reroute_score = 1;
        }
        const bool allow_maze = proposal_reroute_maze_enabled();
        const bool conflict_aware = proposal_reroute_conflict_aware_enabled();
        const int max_candidates = construct_2d_tree.v8_proposal_max_candidates_override > 0 ?
                construct_2d_tree.v8_proposal_max_candidates_override : proposal_reroute_max_candidates();
        const int batch_size = construct_2d_tree.v8_proposal_batch_size_override > 0 ?
                construct_2d_tree.v8_proposal_batch_size_override : proposal_reroute_batch_size();
        const int max_rounds = proposal_reroute_max_rounds();
        const bool overflow_edge_conflict = conflict_aware && proposal_reroute_overflow_edge_conflict_enabled();
        const int overflow_edge_quota = proposal_reroute_overflow_edge_quota();
        const bool emergency_edge_oversubscribe =
                construct_2d_tree.v8_proposal_edge_oversubscribe_override;
        const bool improvement_commit = proposal_reroute_improvement_commit_enabled();
        const bool ripup_before_propose = proposal_reroute_ripup_before_propose_enabled();
        const bool safe_commit = ripup_before_propose && proposal_reroute_safe_commit_enabled();
        const bool adaptive_rounds = proposal_reroute_adaptive_rounds_enabled();
        const int low_overflow_limit = proposal_reroute_low_overflow_limit();
        const int low_max_rounds = proposal_reroute_low_max_rounds();
        const int global_commit_limit = proposal_reroute_global_commit_limit();
        const int global_commit_max_tests = proposal_reroute_global_commit_max_tests();
        const bool global_commit_post_only = proposal_reroute_global_commit_post_only_enabled();
        const bool transactional_waves = v8_transactional_proposal_waves_enabled();
        const int transactional_wave_size = v8_transactional_proposal_wave_size();
        const bool transactional_wave_global_gate =
                v8_transactional_proposal_global_gate_enabled();
        const bool transactional_wave_require_progress =
                v8_transactional_proposal_require_progress_enabled();

        int total_inputs = 0;
        int total_selected = 0;
        int total_conflict_skipped = 0;
        int total_proposal_success = 0;
        int total_proposal_commits = 0;
        int total_proposal_global_commits = 0;
        int total_proposal_global_tests = 0;
        int total_proposal_rejects = 0;
        int total_transactional_waves = 0;
        int total_transactional_wave_rollbacks = 0;
        double total_proposal_ms = 0.0;
        double total_commit_ms = 0.0;
        const bool reject_cooldown = v8_reject_cooldown_enabled();
        const bool low_overflow_edge_oversubscribe = v8_low_overflow_edge_oversubscribe_enabled();
        std::unordered_set<Two_pin_element_2d*> rejected_this_phase;

        OverflowStats phase_start_overflow;
        int effective_max_rounds = max_rounds;
        if ((adaptive_rounds && low_overflow_limit > 0) || global_commit_limit > 0) {
            phase_start_overflow = current_overflow_stats(congestion);
            if (phase_start_overflow.total_overflow > 0 &&
                    phase_start_overflow.total_overflow <= low_overflow_limit) {
                effective_max_rounds = std::min(max_rounds, low_max_rounds);
            }
        }

        for (int proposal_round = 1; proposal_round <= effective_max_rounds; ++proposal_round) {
            std::vector<ProposalInput> proposal_inputs;
            proposal_inputs.reserve(twopin_list.size());
            for (Two_pin_element_2d* two_pin : twopin_list) {
                if (reject_cooldown &&
                        rejected_this_phase.find(two_pin) != rejected_this_phase.end()) {
                    continue;
                }
                const int overflow_score = path_overflow_score(*two_pin, congestion);
                if (overflow_score >= min_reroute_score) {
                    proposal_inputs.push_back(ProposalInput { two_pin, overflow_score });
                }
            }
            if (proposal_inputs.empty()) {
                break;
            }
            std::sort(proposal_inputs.begin(), proposal_inputs.end(),
                    [](const ProposalInput& a, const ProposalInput& b) {
                        if (a.overflow_score != b.overflow_score) {
                            return a.overflow_score > b.overflow_score;
                        }
                        return Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
                    });

            if (max_candidates < static_cast<int>(proposal_inputs.size())) {
                proposal_inputs.resize(max_candidates);
            }

            std::vector<Two_pin_element_2d*> overflow_twopins;
            overflow_twopins.reserve(std::min(batch_size, static_cast<int>(proposal_inputs.size())));
            int conflict_skipped = 0;
            if (conflict_aware) {
                std::unordered_set<int> selected_net_ids;
                selected_net_ids.reserve(std::min(batch_size, static_cast<int>(proposal_inputs.size())));
                if (overflow_edge_conflict) {
                    const bool oversubscribe_low_edges =
                            low_overflow_edge_oversubscribe &&
                            phase_start_overflow.total_overflow > 0 &&
                            low_overflow_limit > 0 &&
                            phase_start_overflow.total_overflow <= low_overflow_limit;
                    const bool oversubscribe_edges =
                            oversubscribe_low_edges || emergency_edge_oversubscribe;
                    std::unordered_map<std::uint64_t, int> selected_overflow_edges;
                    selected_overflow_edges.reserve(std::min(batch_size * 4, static_cast<int>(proposal_inputs.size()) * 2));
                    std::vector<OverflowEdgeRef> overflow_edges;
                    for (const ProposalInput& input : proposal_inputs) {
                        if (static_cast<int>(overflow_twopins.size()) >= batch_size) {
                            break;
                        }
                        bool conflict = selected_net_ids.find(input.two_pin->net_id) != selected_net_ids.end();
                        collect_overflow_route_edges(*input.two_pin, congestion, overflow_edges);
                        if (!conflict) {
                            for (const OverflowEdgeRef& edge : overflow_edges) {
                                const auto edge_count = selected_overflow_edges.find(edge.key);
                                const int used_count = edge_count == selected_overflow_edges.end() ? 0 : edge_count->second;
                                const int edge_limit = oversubscribe_edges ?
                                        overflow_edge_quota : std::min(overflow_edge_quota, edge.overuse);
                                if (used_count >= edge_limit) {
                                    conflict = true;
                                    break;
                                }
                            }
                        }
                        if (conflict) {
                            ++conflict_skipped;
                            continue;
                        }
                        selected_net_ids.insert(input.two_pin->net_id);
                        for (const OverflowEdgeRef& edge : overflow_edges) {
                            ++selected_overflow_edges[edge.key];
                        }
                        overflow_twopins.push_back(input.two_pin);
                    }
                } else {
                    std::vector<Rectangle> selected_boxes;
                    selected_boxes.reserve(std::min(batch_size, static_cast<int>(proposal_inputs.size())));
                    for (const ProposalInput& input : proposal_inputs) {
                        if (static_cast<int>(overflow_twopins.size()) >= batch_size) {
                            break;
                        }
                        bool conflict = selected_net_ids.find(input.two_pin->net_id) != selected_net_ids.end();
                        const Rectangle box = reroute_conflict_box(*input.two_pin, construct_2d_tree, nullptr);
                        if (!conflict) {
                            for (const Rectangle& selected_box : selected_boxes) {
                                if (boxes_overlap(box, selected_box)) {
                                    conflict = true;
                                    break;
                                }
                            }
                        }
                        if (conflict) {
                            ++conflict_skipped;
                            continue;
                        }
                        selected_net_ids.insert(input.two_pin->net_id);
                        selected_boxes.push_back(box);
                        overflow_twopins.push_back(input.two_pin);
                    }
                }
            } else {
                const int selected_count = std::min(batch_size, static_cast<int>(proposal_inputs.size()));
                for (int i = 0; i < selected_count; ++i) {
                    overflow_twopins.push_back(proposal_inputs[i].two_pin);
                }
            }
            if (overflow_twopins.empty()) {
                break;
            }

            if (transactional_waves && ripup_before_propose) {
                int proposal_success = 0;
                int proposal_commits = 0;
                int proposal_global_commits = 0;
                int proposal_global_tests = 0;
                int proposal_rejects = 0;
                int transactional_wave_rollbacks = 0;
                int transactional_wave_count = 0;
                double proposal_ms_value = 0.0;
                double commit_ms_value = 0.0;
                const int wave_size =
                        std::max(1, std::min(transactional_wave_size,
                                static_cast<int>(overflow_twopins.size())));

                for (int wave_begin = 0;
                        wave_begin < static_cast<int>(overflow_twopins.size());
                        wave_begin += wave_size) {
                    const int wave_end = std::min(wave_begin + wave_size,
                            static_cast<int>(overflow_twopins.size()));
                    const int current_wave_size = wave_end - wave_begin;
                    ++transactional_wave_count;

                    const OverflowStats wave_start_stats =
                            transactional_wave_global_gate
                            ? current_overflow_stats(congestion)
                            : OverflowStats {};

                    std::vector<RippedPathState> wave_states(current_wave_size);
                    for (int i = 0; i < current_wave_size; ++i) {
                        Two_pin_element_2d& two_pin =
                                *overflow_twopins[wave_begin + i];
                        RippedPathState& state = wave_states[i];
                        state.original_path = two_pin.path;
                        state.original_pin1 = two_pin.pin1;
                        state.original_pin2 = two_pin.pin2;
                        state.old_overflow_score =
                                path_overflow_score(two_pin, congestion);
                    }
                    for (int i = 0; i < current_wave_size; ++i) {
                        Two_pin_element_2d& two_pin =
                                *overflow_twopins[wave_begin + i];
                        RippedPathState& state = wave_states[i];
                        congestion.update_congestion_map_remove_two_pin_net(
                                state.original_path, two_pin.net_id);
                        state.removed = true;
                    }

                    std::vector<RerouteProposal> proposals(current_wave_size);
                    const auto proposal_start = ProfileClock::now();
#ifdef NTHU_ROUTE_OPENMP
                    if (v8_proposal_parallel_enabled()) {
#pragma omp parallel
                        {
                            MonotonicRouting local_monotonic(congestion,
                                    monotonic_enable_flag);
                            Multisource_multisink_mazeroute local_maze(
                                    construct_2d_tree, congestion);
                            local_maze.set_rebuild_tree_from_twopins(true);
#pragma omp for schedule(dynamic, 1)
                            for (int i = 0; i < current_wave_size; ++i) {
                                Two_pin_element_2d* two_pin =
                                        overflow_twopins[wave_begin + i];
                                proposals[i].two_pin = two_pin;
                                proposals[i].proposed = propose_reroute_path(
                                        *two_pin, version, local_monotonic,
                                        allow_maze ? &local_maze : nullptr,
                                        allow_maze, proposals[i].path, true,
                                        wave_states[i].old_overflow_score);
                            }
                        }
                    } else
#endif
                    {
                        MonotonicRouting local_monotonic(congestion,
                                monotonic_enable_flag);
                        Multisource_multisink_mazeroute local_maze(
                                construct_2d_tree, congestion);
                        local_maze.set_rebuild_tree_from_twopins(true);
                        for (int i = 0; i < current_wave_size; ++i) {
                            Two_pin_element_2d* two_pin =
                                    overflow_twopins[wave_begin + i];
                            proposals[i].two_pin = two_pin;
                            proposals[i].proposed = propose_reroute_path(
                                    *two_pin, version, local_monotonic,
                                    allow_maze ? &local_maze : nullptr,
                                    allow_maze, proposals[i].path, true,
                                    wave_states[i].old_overflow_score);
                        }
                    }
                    proposal_ms_value += profile_ms(proposal_start,
                            ProfileClock::now());

                    auto restore_wave_originals = [&]() {
                        for (int i = 0; i < current_wave_size; ++i) {
                            Two_pin_element_2d& two_pin =
                                    *overflow_twopins[wave_begin + i];
                            if (!two_pin.path.empty()) {
                                congestion.update_congestion_map_remove_two_pin_net(
                                        two_pin.path, two_pin.net_id);
                            }
                        }
                        for (int i = 0; i < current_wave_size; ++i) {
                            Two_pin_element_2d& two_pin =
                                    *overflow_twopins[wave_begin + i];
                            const RippedPathState& state = wave_states[i];
                            two_pin.path = state.original_path;
                            two_pin.pin1 = state.original_pin1;
                            two_pin.pin2 = state.original_pin2;
                            congestion.update_congestion_map_insert_two_pin_net(
                                    two_pin);
                            wave_states[i].removed = false;
                        }
                    };

                    const auto commit_start = ProfileClock::now();
                    int wave_proposed = 0;
                    int wave_commits = 0;
                    int wave_rejects = 0;
                    for (int proposal_index = 0;
                            proposal_index < static_cast<int>(proposals.size());
                            ++proposal_index) {
                        RerouteProposal& proposal = proposals[proposal_index];
                        RippedPathState& state = wave_states[proposal_index];
                        Two_pin_element_2d& two_pin = *proposal.two_pin;
                        if (!proposal.proposed) {
                            if (reject_cooldown) {
                                rejected_this_phase.insert(proposal.two_pin);
                            }
                            if (state.removed) {
                                two_pin.path = state.original_path;
                                two_pin.pin1 = state.original_pin1;
                                two_pin.pin2 = state.original_pin2;
                                congestion.update_congestion_map_insert_two_pin_net(
                                        two_pin);
                                state.removed = false;
                            }
                            ++proposal_rejects;
                            ++wave_rejects;
                            continue;
                        }

                        ++proposal_success;
                        ++wave_proposed;
                        bool accepted_by_global_gate = false;
                        bool evaluated_global_gate = false;
                        const bool allow_global_gate = global_commit_limit > 0 &&
                                (!global_commit_post_only || version == 3) &&
                                (global_commit_max_tests <= 0 ||
                                        proposal_global_tests <
                                                global_commit_max_tests);
                        if (commit_reroute_proposal(two_pin, proposal.path,
                                    version, state.removed,
                                    state.removed ? state.old_overflow_score : -1,
                                    allow_global_gate
                                            ? phase_start_overflow.total_overflow
                                            : -1,
                                    &accepted_by_global_gate,
                                    &evaluated_global_gate)) {
                            proposal.committed = true;
                            ++proposal_commits;
                            ++wave_commits;
                            if (accepted_by_global_gate) {
                                ++proposal_global_commits;
                            }
                        } else {
                            proposal.rejected = true;
                            ++proposal_rejects;
                            ++wave_rejects;
                            if (reject_cooldown) {
                                rejected_this_phase.insert(proposal.two_pin);
                            }
                        }
                        state.removed = false;
                        if (evaluated_global_gate) {
                            ++proposal_global_tests;
                        }
                    }

                    if (transactional_wave_global_gate && wave_commits > 0) {
                        const OverflowStats wave_end_stats =
                                current_overflow_stats(congestion);
                        const bool wave_worsened =
                                wave_end_stats.total_overflow >
                                        wave_start_stats.total_overflow ||
                                (wave_end_stats.total_overflow ==
                                        wave_start_stats.total_overflow &&
                                wave_end_stats.max_overflow >
                                        wave_start_stats.max_overflow);
                        const bool wave_progress =
                                wave_end_stats.total_overflow <
                                        wave_start_stats.total_overflow ||
                                (wave_end_stats.total_overflow ==
                                        wave_start_stats.total_overflow &&
                                wave_end_stats.max_overflow <
                                        wave_start_stats.max_overflow);
                        if (wave_worsened ||
                                (transactional_wave_require_progress &&
                                        !wave_progress &&
                                        wave_start_stats.total_overflow > 0)) {
                            restore_wave_originals();
                            proposal_commits -= wave_commits;
                            proposal_rejects += wave_commits;
                            wave_rejects += wave_commits;
                            ++transactional_wave_rollbacks;
                            if (reject_cooldown) {
                                for (int i = 0; i < current_wave_size; ++i) {
                                    rejected_this_phase.insert(
                                            overflow_twopins[wave_begin + i]);
                                }
                            }
                        }
                    }
                    commit_ms_value += profile_ms(commit_start,
                            ProfileClock::now());
                }

                total_inputs += static_cast<int>(proposal_inputs.size());
                total_selected += static_cast<int>(overflow_twopins.size());
                total_conflict_skipped += conflict_skipped;
                total_proposal_success += proposal_success;
                total_proposal_commits += proposal_commits;
                total_proposal_global_commits += proposal_global_commits;
                total_proposal_global_tests += proposal_global_tests;
                total_proposal_rejects += proposal_rejects;
                total_transactional_waves += transactional_wave_count;
                total_transactional_wave_rollbacks += transactional_wave_rollbacks;
                total_proposal_ms += proposal_ms_value;
                total_commit_ms += commit_ms_value;

                if (do_log) {
                    log_sp->info("proposal reroute round={} hot_pool={} selected={} conflict_skipped={} proposed={} committed={} global_committed={} global_tests={} rejected={} skipped={} conflict_aware={} edge_conflict={} edge_quota={} edge_oversubscribe={} improvement_commit={} global_commit_limit={} global_test_limit={} ripup_snapshot={} safe_commit={} adaptive_rounds={} low_overflow={} allow_maze={} transactional_waves={} wave_size={} wave_rollbacks={} wave_global_gate={} wave_require_progress={} proposal_ms={:.3f} commit_ms={:.3f}",
                            proposal_round, proposal_inputs.size(),
                            overflow_twopins.size(), conflict_skipped,
                            proposal_success, proposal_commits,
                            proposal_global_commits, proposal_global_tests,
                            proposal_rejects,
                            static_cast<int>(overflow_twopins.size()) -
                                    proposal_success,
                            conflict_aware ? 1 : 0,
                            overflow_edge_conflict ? 1 : 0,
                            overflow_edge_conflict ? overflow_edge_quota : 0,
                            emergency_edge_oversubscribe ? 1 : 0,
                            improvement_commit ? 1 : 0, global_commit_limit,
                            global_commit_max_tests,
                            ripup_before_propose ? 1 : 0,
                            safe_commit ? 1 : 0,
                            adaptive_rounds ? 1 : 0,
                            phase_start_overflow.total_overflow,
                            allow_maze ? 1 : 0, transactional_wave_count,
                            wave_size, transactional_wave_rollbacks,
                            transactional_wave_global_gate ? 1 : 0,
                            transactional_wave_require_progress ? 1 : 0,
                            proposal_ms_value, commit_ms_value);
                }
                if (proposal_commits == 0) {
                    if (reject_cooldown &&
                            proposal_rejects +
                                    (static_cast<int>(overflow_twopins.size()) -
                                            proposal_success) > 0) {
                        continue;
                    }
                    break;
                }
                continue;
            }

            std::vector<RippedPathState> ripped_paths(overflow_twopins.size());
            if (ripup_before_propose) {
                for (int i = 0; i < static_cast<int>(overflow_twopins.size()); ++i) {
                    Two_pin_element_2d& two_pin = *overflow_twopins[i];
                    RippedPathState& state = ripped_paths[i];
                    state.original_path = two_pin.path;
                    state.original_pin1 = two_pin.pin1;
                    state.original_pin2 = two_pin.pin2;
                    state.old_overflow_score = path_overflow_score(two_pin, congestion);
                }
                for (int i = 0; i < static_cast<int>(overflow_twopins.size()); ++i) {
                    Two_pin_element_2d& two_pin = *overflow_twopins[i];
                    RippedPathState& state = ripped_paths[i];
                    congestion.update_congestion_map_remove_two_pin_net(state.original_path, two_pin.net_id);
                    state.removed = true;
                }
            }

            std::vector<RerouteProposal> proposals(overflow_twopins.size());
            const auto proposal_start = ProfileClock::now();
#ifdef NTHU_ROUTE_OPENMP
            if (v8_proposal_parallel_enabled()) {
#pragma omp parallel
                {
                    MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
                    Multisource_multisink_mazeroute local_maze(construct_2d_tree, congestion);
                    local_maze.set_rebuild_tree_from_twopins(true);
#pragma omp for schedule(dynamic, 1)
                    for (int i = 0; i < static_cast<int>(overflow_twopins.size()); ++i) {
                        proposals[i].two_pin = overflow_twopins[i];
                        proposals[i].proposed = propose_reroute_path(*overflow_twopins[i], version,
                                local_monotonic, allow_maze ? &local_maze : nullptr, allow_maze,
                                proposals[i].path, ripup_before_propose,
                                ripup_before_propose ? ripped_paths[i].old_overflow_score : -1);
                    }
                }
            } else
#endif
            {
                MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
                Multisource_multisink_mazeroute local_maze(construct_2d_tree, congestion);
                local_maze.set_rebuild_tree_from_twopins(true);
                for (int i = 0; i < static_cast<int>(overflow_twopins.size()); ++i) {
                    proposals[i].two_pin = overflow_twopins[i];
                    proposals[i].proposed = propose_reroute_path(*overflow_twopins[i], version,
                            local_monotonic, allow_maze ? &local_maze : nullptr, allow_maze,
                            proposals[i].path, ripup_before_propose,
                            ripup_before_propose ? ripped_paths[i].old_overflow_score : -1);
                }
            }

            const double proposal_ms_value = profile_ms(proposal_start, ProfileClock::now());
            if (safe_commit) {
                for (int i = 0; i < static_cast<int>(overflow_twopins.size()); ++i) {
                    RippedPathState& state = ripped_paths[i];
                    if (!state.removed) {
                        continue;
                    }
                    Two_pin_element_2d& two_pin = *overflow_twopins[i];
                    two_pin.path = state.original_path;
                    two_pin.pin1 = state.original_pin1;
                    two_pin.pin2 = state.original_pin2;
                    congestion.update_congestion_map_insert_two_pin_net(two_pin);
                    state.removed = false;
                }
            }
            const auto commit_start = ProfileClock::now();
            int proposal_success = 0;
            int proposal_commits = 0;
            int proposal_global_commits = 0;
            int proposal_global_tests = 0;
            int proposal_rejects = 0;
            for (int proposal_index = 0; proposal_index < static_cast<int>(proposals.size()); ++proposal_index) {
                RerouteProposal& proposal = proposals[proposal_index];
                if (!proposal.proposed) {
                    if (reject_cooldown) {
                        rejected_this_phase.insert(proposal.two_pin);
                    }
                    if (ripup_before_propose && ripped_paths[proposal_index].removed) {
                        congestion.update_congestion_map_insert_two_pin_net(*proposal.two_pin);
                    }
                    continue;
                }
                ++proposal_success;
                bool accepted_by_global_gate = false;
                bool evaluated_global_gate = false;
                const bool allow_global_gate = global_commit_limit > 0 &&
                        (!global_commit_post_only || version == 3) &&
                        (global_commit_max_tests <= 0 || proposal_global_tests < global_commit_max_tests);
                const bool old_path_still_removed =
                        ripup_before_propose && ripped_paths[proposal_index].removed;
                if (commit_reroute_proposal(*proposal.two_pin, proposal.path, version,
                            old_path_still_removed,
                            old_path_still_removed ? ripped_paths[proposal_index].old_overflow_score : -1,
                            allow_global_gate ? phase_start_overflow.total_overflow : -1,
                            &accepted_by_global_gate,
                            &evaluated_global_gate)) {
                    proposal.committed = true;
                    ++proposal_commits;
                    if (accepted_by_global_gate) {
                        ++proposal_global_commits;
                    }
                } else {
                    proposal.rejected = true;
                    ++proposal_rejects;
                    if (reject_cooldown) {
                        rejected_this_phase.insert(proposal.two_pin);
                    }
                }
                if (evaluated_global_gate) {
                    ++proposal_global_tests;
                }
            }
            const double commit_ms_value = profile_ms(commit_start, ProfileClock::now());

            total_inputs += static_cast<int>(proposal_inputs.size());
            total_selected += static_cast<int>(overflow_twopins.size());
            total_conflict_skipped += conflict_skipped;
            total_proposal_success += proposal_success;
            total_proposal_commits += proposal_commits;
            total_proposal_global_commits += proposal_global_commits;
            total_proposal_global_tests += proposal_global_tests;
            total_proposal_rejects += proposal_rejects;
            total_proposal_ms += proposal_ms_value;
            total_commit_ms += commit_ms_value;

            if (do_log) {
                log_sp->info("proposal reroute round={} hot_pool={} selected={} conflict_skipped={} proposed={} committed={} global_committed={} global_tests={} rejected={} skipped={} conflict_aware={} edge_conflict={} edge_quota={} edge_oversubscribe={} improvement_commit={} global_commit_limit={} global_test_limit={} ripup_snapshot={} safe_commit={} adaptive_rounds={} low_overflow={} allow_maze={} proposal_ms={:.3f} commit_ms={:.3f}",
                        proposal_round, proposal_inputs.size(), overflow_twopins.size(), conflict_skipped,
                        proposal_success, proposal_commits, proposal_global_commits, proposal_global_tests,
                        proposal_rejects,
                        static_cast<int>(overflow_twopins.size()) - proposal_success,
                        conflict_aware ? 1 : 0, overflow_edge_conflict ? 1 : 0,
                        overflow_edge_conflict ? overflow_edge_quota : 0,
                        emergency_edge_oversubscribe ? 1 : 0,
                        improvement_commit ? 1 : 0, global_commit_limit, global_commit_max_tests,
                        ripup_before_propose ? 1 : 0,
                        safe_commit ? 1 : 0,
                        adaptive_rounds ? 1 : 0, phase_start_overflow.total_overflow,
                        allow_maze ? 1 : 0,
                        proposal_ms_value, commit_ms_value);
            }
            if (proposal_commits == 0) {
                if (reject_cooldown && proposal_rejects + (static_cast<int>(overflow_twopins.size()) - proposal_success) > 0) {
                    continue;
                }
                break;
            }
        }

        if (do_profile) {
            range_profile.proposal_ms += total_proposal_ms;
            range_profile.proposal_commit_ms += total_commit_ms;
            range_profile.proposal_inputs += total_selected;
            range_profile.proposal_success += total_proposal_success;
            range_profile.proposal_commits += total_proposal_commits;
            range_profile.proposal_commit_rejects += total_proposal_rejects;
            range_profile.proposal_skipped += total_selected - total_proposal_success;
        }
        if (do_log) {
            log_sp->info("proposal reroute phase rounds={} base_rounds={} hot_pool_scanned={} selected={} conflict_skipped={} proposed={} committed={} global_committed={} global_tests={} rejected={} skipped={} conflict_aware={} edge_conflict={} edge_quota={} edge_oversubscribe={} improvement_commit={} global_commit_limit={} global_test_limit={} ripup_snapshot={} safe_commit={} adaptive_rounds={} low_overflow={} allow_maze={} transactional_waves={} wave_rollbacks={} proposal_ms={:.3f} commit_ms={:.3f}",
                    effective_max_rounds, max_rounds, total_inputs, total_selected, total_conflict_skipped,
                    total_proposal_success, total_proposal_commits, total_proposal_global_commits,
                    total_proposal_global_tests, total_proposal_rejects,
                    total_selected - total_proposal_success, conflict_aware ? 1 : 0,
                    overflow_edge_conflict ? 1 : 0, overflow_edge_conflict ? overflow_edge_quota : 0,
                    emergency_edge_oversubscribe ? 1 : 0,
                    improvement_commit ? 1 : 0, global_commit_limit, global_commit_max_tests,
                    ripup_before_propose ? 1 : 0,
                    safe_commit ? 1 : 0,
                    adaptive_rounds ? 1 : 0, phase_start_overflow.total_overflow,
                    allow_maze ? 1 : 0, total_transactional_waves,
                    total_transactional_wave_rollbacks, total_proposal_ms,
                    total_commit_ms);
        }
        if (v8_low_tail_global_repair_enabled() &&
                (!v8_low_tail_post_only_enabled() || version == 3)) {
            const int tail_limit = v8_low_tail_global_repair_limit();
            OverflowStats tail_stats = current_overflow_stats(congestion);
            if (tail_limit > 0 && tail_stats.total_overflow > 0 &&
                    tail_stats.total_overflow <= tail_limit) {
                const int tail_rounds = v8_low_tail_global_repair_rounds();
                const int tail_max_candidates = v8_low_tail_global_repair_max_candidates();
                const int tail_box_inc = v8_low_tail_box_inc();
                int tail_total_inputs = 0;
                int tail_total_proposed = 0;
                int tail_total_committed = 0;
                int tail_total_rejected = 0;
                double tail_total_proposal_ms = 0.0;
                double tail_total_commit_ms = 0.0;

                for (int tail_round = 1; tail_round <= tail_rounds && tail_stats.total_overflow > 0; ++tail_round) {
                    std::vector<ProposalInput> tail_inputs;
                    tail_inputs.reserve(twopin_list.size());
                    for (Two_pin_element_2d* two_pin : twopin_list) {
                        const int overflow_score = path_overflow_score(*two_pin, congestion);
                        if (overflow_score > 0) {
                            tail_inputs.push_back(ProposalInput { two_pin, overflow_score });
                        }
                    }
                    if (tail_inputs.empty()) {
                        break;
                    }
                    std::sort(tail_inputs.begin(), tail_inputs.end(),
                            [](const ProposalInput& a, const ProposalInput& b) {
                                if (a.overflow_score != b.overflow_score) {
                                    return a.overflow_score > b.overflow_score;
                                }
                                return Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
                            });
                    if (tail_max_candidates < static_cast<int>(tail_inputs.size())) {
                        tail_inputs.resize(tail_max_candidates);
                    }

                    std::vector<RerouteProposal> tail_proposals(tail_inputs.size());
                    const auto tail_proposal_start = ProfileClock::now();
                    const int original_boxsize_inc = construct_2d_tree.BOXSIZE_INC;
                    if (tail_box_inc > original_boxsize_inc) {
                        construct_2d_tree.BOXSIZE_INC = tail_box_inc;
                    }
#ifdef NTHU_ROUTE_OPENMP
                    if (v8_proposal_parallel_enabled()) {
#pragma omp parallel
                        {
                            MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
                            Multisource_multisink_mazeroute local_maze(construct_2d_tree, congestion);
                            local_maze.set_rebuild_tree_from_twopins(true);
#pragma omp for schedule(dynamic, 1)
                            for (int i = 0; i < static_cast<int>(tail_inputs.size()); ++i) {
                                tail_proposals[i].two_pin = tail_inputs[i].two_pin;
                                tail_proposals[i].proposed = propose_reroute_path(*tail_inputs[i].two_pin, version,
                                        local_monotonic, allow_maze ? &local_maze : nullptr, allow_maze,
                                        tail_proposals[i].path, false, tail_inputs[i].overflow_score);
                            }
                        }
                    } else
#endif
                    {
                        MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
                        Multisource_multisink_mazeroute local_maze(construct_2d_tree, congestion);
                        local_maze.set_rebuild_tree_from_twopins(true);
                        for (int i = 0; i < static_cast<int>(tail_inputs.size()); ++i) {
                            tail_proposals[i].two_pin = tail_inputs[i].two_pin;
                            tail_proposals[i].proposed = propose_reroute_path(*tail_inputs[i].two_pin, version,
                                    local_monotonic, allow_maze ? &local_maze : nullptr, allow_maze,
                                    tail_proposals[i].path, false, tail_inputs[i].overflow_score);
                        }
                    }
                    construct_2d_tree.BOXSIZE_INC = original_boxsize_inc;
                    const double tail_proposal_ms_value = profile_ms(tail_proposal_start, ProfileClock::now());

                    const auto tail_commit_start = ProfileClock::now();
                    int tail_proposed = 0;
                    int tail_committed = 0;
                    int tail_rejected = 0;
                    for (RerouteProposal& proposal : tail_proposals) {
                        if (!proposal.proposed || proposal.path.size() < 2) {
                            continue;
                        }
                        ++tail_proposed;
                        Two_pin_element_2d& two_pin = *proposal.two_pin;
                        if (congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false)) {
                            continue;
                        }

                        const std::vector<Coordinate_2d> original_path(two_pin.path);
                        const Coordinate_2d original_pin1 = two_pin.pin1;
                        const Coordinate_2d original_pin2 = two_pin.pin2;
                        const OverflowStats old_stats = current_overflow_stats(congestion);

                        congestion.update_congestion_map_remove_two_pin_net(original_path, two_pin.net_id);
                        two_pin.path = proposal.path;
                        two_pin.pin1 = two_pin.path.front();
                        two_pin.pin2 = two_pin.path.back();
                        congestion.update_congestion_map_insert_two_pin_net(two_pin);
                        const OverflowStats new_stats = current_overflow_stats(congestion);

                        const bool accept = new_stats.total_overflow < old_stats.total_overflow &&
                                new_stats.max_overflow <= old_stats.max_overflow;
                        if (accept) {
                            if (version == 2) {
                                two_pin.done = construct_2d_tree.done_iter;
                            }
                            construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
                            tail_stats = new_stats;
                            ++tail_committed;
                            if (tail_stats.total_overflow == 0) {
                                break;
                            }
                            continue;
                        }

                        congestion.update_congestion_map_remove_two_pin_net(proposal.path, two_pin.net_id);
                        two_pin.path = original_path;
                        two_pin.pin1 = original_pin1;
                        two_pin.pin2 = original_pin2;
                        congestion.update_congestion_map_insert_two_pin_net(two_pin);
                        tail_stats = old_stats;
                        ++tail_rejected;
                    }
                    const double tail_commit_ms_value = profile_ms(tail_commit_start, ProfileClock::now());

                    tail_total_inputs += static_cast<int>(tail_inputs.size());
                    tail_total_proposed += tail_proposed;
                    tail_total_committed += tail_committed;
                    tail_total_rejected += tail_rejected;
                    tail_total_proposal_ms += tail_proposal_ms_value;
                    tail_total_commit_ms += tail_commit_ms_value;

                    if (do_log) {
                        log_sp->info("v8 low-tail global repair round={} inputs={} proposed={} committed={} rejected={} total_overflow={} max_overflow={} limit={} box_inc={} proposal_ms={:.3f} commit_ms={:.3f}",
                                tail_round, tail_inputs.size(), tail_proposed, tail_committed,
                                tail_rejected, tail_stats.total_overflow, tail_stats.max_overflow,
                                tail_limit, tail_box_inc, tail_proposal_ms_value, tail_commit_ms_value);
                    }
                    if (tail_committed == 0) {
                        break;
                    }
                }
                if (do_log) {
                    log_sp->info("v8 low-tail global repair phase inputs={} proposed={} committed={} rejected={} total_overflow={} max_overflow={} limit={} box_inc={} proposal_ms={:.3f} commit_ms={:.3f}",
                            tail_total_inputs, tail_total_proposed, tail_total_committed,
                            tail_total_rejected, tail_stats.total_overflow, tail_stats.max_overflow,
                            tail_limit, tail_box_inc, tail_total_proposal_ms, tail_total_commit_ms);
                }

                if (v8_low_tail_self_ripup_enabled() && tail_stats.total_overflow > 0) {
                    const int self_ripup_box_inc = v8_low_tail_self_ripup_box_inc();
                    const int self_ripup_max_tests = v8_low_tail_self_ripup_max_tests();
                    const bool strict_capacity_tail = v8_low_tail_strict_capacity_enabled();
                    int self_total_inputs = 0;
                    int self_total_proposed = 0;
                    int self_total_committed = 0;
                    int self_total_rejected = 0;
                    double self_total_ms = 0.0;

                    for (int self_round = 1; self_round <= tail_rounds && tail_stats.total_overflow > 0; ++self_round) {
                        std::vector<ProposalInput> self_inputs;
                        self_inputs.reserve(twopin_list.size());
                        for (Two_pin_element_2d* two_pin : twopin_list) {
                            const int overflow_score = path_overflow_score(*two_pin, congestion);
                            if (overflow_score > 0) {
                                self_inputs.push_back(ProposalInput { two_pin, overflow_score });
                            }
                        }
                        if (self_inputs.empty()) {
                            break;
                        }
                        std::sort(self_inputs.begin(), self_inputs.end(),
                                [](const ProposalInput& a, const ProposalInput& b) {
                                    if (a.overflow_score != b.overflow_score) {
                                        return a.overflow_score > b.overflow_score;
                                    }
                                    return Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
                                });
                        if (self_ripup_max_tests < static_cast<int>(self_inputs.size())) {
                            self_inputs.resize(self_ripup_max_tests);
                        }

                        const auto self_start = ProfileClock::now();
                        int self_proposed = 0;
                        int self_committed = 0;
                        int self_rejected = 0;
                        for (const ProposalInput& input : self_inputs) {
                            Two_pin_element_2d& two_pin = *input.two_pin;
                            if (congestion.check_path_no_overflow(two_pin.path, two_pin.net_id, false)) {
                                continue;
                            }

                            const std::vector<Coordinate_2d> original_path(two_pin.path);
                            const Coordinate_2d original_pin1 = two_pin.pin1;
                            const Coordinate_2d original_pin2 = two_pin.pin2;
                            const OverflowStats old_stats = current_overflow_stats(congestion);

                            congestion.update_congestion_map_remove_two_pin_net(original_path, two_pin.net_id);
                            MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
                            Multisource_multisink_mazeroute local_maze(construct_2d_tree, congestion);
                            local_maze.set_rebuild_tree_from_twopins(true);
                            std::vector<Coordinate_2d> proposed_path;

                            const int original_boxsize_inc = construct_2d_tree.BOXSIZE_INC;
                            if (self_ripup_box_inc > original_boxsize_inc) {
                                construct_2d_tree.BOXSIZE_INC = self_ripup_box_inc;
                            }
                            const bool proposed = propose_reroute_path(two_pin, version,
                                    local_monotonic, allow_maze ? &local_maze : nullptr, allow_maze,
                                    proposed_path, true, input.overflow_score);
                            construct_2d_tree.BOXSIZE_INC = original_boxsize_inc;

                            if (proposed && proposed_path.size() >= 2) {
                                ++self_proposed;
                                OverflowStats new_stats = old_stats;
                                bool inserted_proposal = false;
                                bool accept = false;
                                if (strict_capacity_tail) {
                                    accept = congestion.check_path_no_overflow(
                                            proposed_path, two_pin.net_id, true);
                                } else {
                                    two_pin.path = proposed_path;
                                    two_pin.pin1 = two_pin.path.front();
                                    two_pin.pin2 = two_pin.path.back();
                                    congestion.update_congestion_map_insert_two_pin_net(two_pin);
                                    inserted_proposal = true;
                                    new_stats = current_overflow_stats(congestion);
                                    accept = new_stats.total_overflow < old_stats.total_overflow &&
                                            new_stats.max_overflow <= old_stats.max_overflow;
                                }
                                if (accept) {
                                    if (strict_capacity_tail) {
                                        two_pin.path = proposed_path;
                                        two_pin.pin1 = two_pin.path.front();
                                        two_pin.pin2 = two_pin.path.back();
                                        congestion.update_congestion_map_insert_two_pin_net(two_pin);
                                        new_stats = current_overflow_stats(congestion);
                                    }
                                    if (version == 2) {
                                        two_pin.done = construct_2d_tree.done_iter;
                                    }
                                    construct_2d_tree.NetDirtyBit[two_pin.net_id] = true;
                                    tail_stats = new_stats;
                                    ++self_committed;
                                    if (tail_stats.total_overflow == 0) {
                                        break;
                                    }
                                    continue;
                                }

                                if (inserted_proposal) {
                                    congestion.update_congestion_map_remove_two_pin_net(proposed_path, two_pin.net_id);
                                }
                                ++self_rejected;
                            }

                            two_pin.path = original_path;
                            two_pin.pin1 = original_pin1;
                            two_pin.pin2 = original_pin2;
                            congestion.update_congestion_map_insert_two_pin_net(two_pin);
                            tail_stats = old_stats;
                        }
                        const double self_ms = profile_ms(self_start, ProfileClock::now());
                        self_total_inputs += static_cast<int>(self_inputs.size());
                        self_total_proposed += self_proposed;
                        self_total_committed += self_committed;
                        self_total_rejected += self_rejected;
                        self_total_ms += self_ms;
                        if (do_log) {
                            log_sp->info("v8 low-tail self-ripup round={} inputs={} proposed={} committed={} rejected={} total_overflow={} max_overflow={} box_inc={} strict_capacity={} elapsed_ms={:.3f}",
                                    self_round, self_inputs.size(), self_proposed, self_committed,
                                    self_rejected, tail_stats.total_overflow, tail_stats.max_overflow,
                                    self_ripup_box_inc, strict_capacity_tail ? 1 : 0, self_ms);
                        }
                        if (self_committed == 0) {
                            break;
                        }
                    }
                    if (do_log) {
                        log_sp->info("v8 low-tail self-ripup phase inputs={} proposed={} committed={} rejected={} total_overflow={} max_overflow={} box_inc={} strict_capacity={} elapsed_ms={:.3f}",
                                self_total_inputs, self_total_proposed, self_total_committed,
                                self_total_rejected, tail_stats.total_overflow, tail_stats.max_overflow,
                                self_ripup_box_inc, strict_capacity_tail ? 1 : 0, self_total_ms);
                    }
                }
            }
        }
        run_v8_strict_legal_repair(twopin_list, version);
        return;
    }
#ifdef NTHU_ROUTE_OPENMP
    if (parallel_reroute_batches_enabled() && twopin_list.size() > 1) {
        const bool do_profile = profile_enabled();
        const auto reroute_start = ProfileClock::now();
        std::vector<Two_pin_element_2d*> overflow_twopins;
        overflow_twopins.reserve(twopin_list.size());
        for (Two_pin_element_2d* two_pin : twopin_list) {
            if (!congestion.check_path_no_overflow(two_pin->path, two_pin->net_id, false)) {
                overflow_twopins.push_back(two_pin);
            }
        }
        if (overflow_twopins.empty()) {
            if (do_profile) {
                range_profile.reroute_ms += profile_ms(reroute_start, ProfileClock::now());
            }
            return;
        }
        const int max_parallel_candidates = parallel_reroute_max_candidates();
        const int parallel_count = std::min(static_cast<int>(overflow_twopins.size()), max_parallel_candidates);
        std::vector<Two_pin_element_2d*> serial_tail;
        if (parallel_count < static_cast<int>(overflow_twopins.size())) {
            serial_tail.assign(overflow_twopins.begin() + parallel_count, overflow_twopins.end());
        }

        std::unordered_map<int, Rectangle> net_path_boxes;
        net_path_boxes.reserve(construct_2d_tree.two_pin_list.size());
        for (const Two_pin_element_2d& net_two_pin : construct_2d_tree.two_pin_list) {
            auto inserted = net_path_boxes.emplace(net_two_pin.net_id,
                    Rectangle { net_two_pin.pin1, net_two_pin.pin2 });
            include_point_in_box(inserted.first->second, net_two_pin.pin1);
            include_point_in_box(inserted.first->second, net_two_pin.pin2);
            include_path_in_box(inserted.first->second, net_two_pin.path);
        }

        std::vector<RerouteCandidateBox> remaining;
        remaining.reserve(parallel_count);
        for (int i = 0; i < parallel_count; ++i) {
            Two_pin_element_2d* two_pin = overflow_twopins[i];
            auto net_box = net_path_boxes.find(two_pin->net_id);
            remaining.push_back(RerouteCandidateBox {
                    two_pin,
                    reroute_conflict_box(*two_pin, construct_2d_tree,
                            net_box != net_path_boxes.end() ? &net_box->second : nullptr) });
        }

        const int max_threads = std::max(1, omp_get_max_threads());
        const int configured_limit = parallel_reroute_batch_limit();
        const int batch_limit = configured_limit > 0 ? std::min(configured_limit, max_threads) : max_threads;

        int batches = 0;
        int parallel_batches = 0;
        int routed_inputs = 0;
        int serialized_inputs = 0;
        int max_batch_size = 0;
        std::vector<Two_pin_element_2d*> serial_fallback;
        serial_fallback.reserve(overflow_twopins.size());

        std::vector<RerouteCandidateBox> batch;
        std::vector<RerouteCandidateBox> next_remaining;
        batch.reserve(batch_limit);
        next_remaining.reserve(remaining.size());
        bool done = false;
        int current_batch_size = 0;

        const int workers = std::min(batch_limit, static_cast<int>(remaining.size()));
#pragma omp parallel num_threads(workers)
        {
            MonotonicRouting local_monotonic(congestion, monotonic_enable_flag);
            while (true) {
#pragma omp single
                {
                    batch.clear();
                    next_remaining.clear();
                    std::unordered_set<int> batch_net_ids;
                    done = remaining.empty();
                    if (!done) {
                        for (const RerouteCandidateBox& candidate : remaining) {
                            bool conflict = batch_net_ids.find(candidate.two_pin->net_id) != batch_net_ids.end();
                            if (!conflict) {
                                for (const RerouteCandidateBox& selected : batch) {
                                    if (boxes_overlap(candidate.box, selected.box)) {
                                        conflict = true;
                                        break;
                                    }
                                }
                            }
                            if (!conflict && static_cast<int>(batch.size()) < batch_limit) {
                                batch.push_back(candidate);
                                batch_net_ids.insert(candidate.two_pin->net_id);
                            } else {
                                next_remaining.push_back(candidate);
                            }
                        }

                        if (batch.empty()) {
                            batch.push_back(next_remaining.back());
                            next_remaining.pop_back();
                        }

                        ++batches;
                        current_batch_size = static_cast<int>(batch.size());
                        routed_inputs += current_batch_size;
                        max_batch_size = std::max(max_batch_size, current_batch_size);
                        if (current_batch_size == 1) {
                            ++serialized_inputs;
                        } else {
                            ++parallel_batches;
                        }
                        remaining.swap(next_remaining);
                    }
                }
                if (done) {
                    break;
                }

                if (current_batch_size == 1) {
#pragma omp single
                    {
                        range_router(*batch.front().two_pin, version);
                    }
                } else {
#pragma omp for schedule(dynamic, 1)
                    for (int i = 0; i < current_batch_size; ++i) {
                        if (!range_router(*batch[i].two_pin, version, &local_monotonic, nullptr, false)) {
#pragma omp critical(nthu_serial_fallback)
                            {
                                serial_fallback.push_back(batch[i].two_pin);
                            }
                        }
                    }
                }
#pragma omp barrier
            }
        }

        if (!serial_fallback.empty()) {
            for (Two_pin_element_2d* two_pin : serial_fallback) {
                range_router(*two_pin, version);
            }
        }
        if (!serial_tail.empty()) {
            for (Two_pin_element_2d* two_pin : serial_tail) {
                range_router(*two_pin, version);
            }
        }

        if (do_profile) {
            range_profile.reroute_ms += profile_ms(reroute_start, ProfileClock::now());
            range_profile.parallel_batches += batches;
            range_profile.parallel_batches_with_work += parallel_batches;
            range_profile.parallel_inputs += routed_inputs;
            range_profile.parallel_serialized_inputs += serialized_inputs;
            range_profile.parallel_max_batch = std::max(range_profile.parallel_max_batch, max_batch_size);
        }
        if (do_profile || parallel_reroute_log_enabled()) {
            log_sp->info("parallel reroute batches candidates={} overflow_candidates={} parallel_candidates={} serial_tail={} batches={} parallel_batches={} serialized_inputs={} serial_fallback={} max_batch={} batch_limit={}",
                    twopin_list.size(), overflow_twopins.size(), parallel_count, serial_tail.size(),
                    batches, parallel_batches, serialized_inputs, serial_fallback.size(),
                    max_batch_size, batch_limit);
        }
        return;
    }
#endif

    const bool do_profile = profile_enabled();
    for (Two_pin_element_2d* two_pin : twopin_list) {
        auto reroute_start = ProfileClock::now();
        range_router(*two_pin, version);
        if (do_profile) {
            range_profile.reroute_ms += profile_ms(reroute_start, ProfileClock::now());
        }
    }
}

void NTHUR::RangeRouter::prepare_cuda_dogleg_choices(const std::vector<Two_pin_element_2d*>& twopin_list) {
    cuda_dogleg_choices.clear();
    if (!cuda_dogleg_preselect_enabled() || !dogleg_fastpath_enabled() || twopin_list.empty() ||
            !cuda_dogleg_available()) {
        return;
    }
    const bool do_profile = profile_enabled();
    const auto profile_start = ProfileClock::now();

    const int width = congestion.congestionMap2d.getXSize();
    const int height = congestion.congestionMap2d.getYSize();
    std::vector<CudaDoglegInput> inputs;
    std::vector<Two_pin_element_2d*> selected_twopins;
    inputs.reserve(twopin_list.size());
    selected_twopins.reserve(twopin_list.size());
    for (const Two_pin_element_2d* two_pin : twopin_list) {
        int overflow_score = 0;
        for (int path_index = static_cast<int>(two_pin->path.size()) - 2; path_index >= 0; --path_index) {
            const Edge_2d& edge = congestion.congestionMap2d.edge(
                    two_pin->path[path_index], two_pin->path[path_index + 1]);
            overflow_score += std::max(0, edge.overUsage());
        }
        if (overflow_score < dogleg_min_overflow_score()) {
            continue;
        }
        inputs.push_back(CudaDoglegInput {
                two_pin->pin1.x,
                two_pin->pin1.y,
                two_pin->pin2.x,
                two_pin->pin2.y });
        selected_twopins.push_back(const_cast<Two_pin_element_2d*>(two_pin));
    }
    if (inputs.empty()) {
        if (do_profile) {
            range_profile.cuda_prepare_ms += profile_ms(profile_start, ProfileClock::now());
        }
        return;
    }
    if (static_cast<int>(inputs.size()) < cuda_dogleg_min_batch()) {
        if (do_profile) {
            ++range_profile.cuda_skipped_small_batches;
            range_profile.cuda_inputs += static_cast<int>(inputs.size());
            range_profile.cuda_prepare_ms += profile_ms(profile_start, ProfileClock::now());
        }
        return;
    }

    std::vector<double> east_cost(width * height, 1.0e100);
    std::vector<double> south_cost(width * height, 1.0e100);
    std::vector<int> east_room;
    std::vector<int> south_room;
    const bool legal_filter = cuda_dogleg_legal_filter_enabled();
    if (legal_filter) {
        east_room.assign(width * height, 0);
        south_room.assign(width * height, 0);
    }
    for (int x = 0; x < width; ++x) {
        for (int y = 0; y < height; ++y) {
            const Coordinate_2d c { x, y };
            const Edge_2d& east = congestion.congestionMap2d.east(c);
            const Edge_2d& south = congestion.congestionMap2d.south(c);
            const int index = y * width + x;
            east_cost[index] = east.cost;
            south_cost[index] = south.cost;
            if (legal_filter) {
                east_room[index] = east.cur_cap + 1.0 <= east.max_cap ? 1 : 0;
                south_room[index] = south.cur_cap + 1.0 <= south.max_cap ? 1 : 0;
            }
        }
    }

    std::vector<CudaDoglegChoice> choices;
    try {
        if (do_profile) {
            ++range_profile.cuda_batches;
            range_profile.cuda_inputs += static_cast<int>(inputs.size());
        }
        if (!cuda_choose_doglegs(width, height, east_cost, south_cost, inputs,
                    dogleg_sample_step(), dogleg_sample_radius(), choices,
                    legal_filter ? &east_room : nullptr,
                    legal_filter ? &south_room : nullptr)) {
            if (do_profile) {
                range_profile.cuda_prepare_ms += profile_ms(profile_start, ProfileClock::now());
            }
            return;
        }
    } catch (const std::exception& e) {
        log_sp->warn("CUDA dogleg preselection disabled after failure: {}", e.what());
        cuda_dogleg_choices.clear();
        if (do_profile) {
            range_profile.cuda_prepare_ms += profile_ms(profile_start, ProfileClock::now());
        }
        return;
    }

    for (std::size_t i = 0; i < selected_twopins.size() && i < choices.size(); ++i) {
        cuda_dogleg_choices.emplace(selected_twopins[i], choices[i]);
        if (do_profile && choices[i].valid != 0) {
            ++range_profile.cuda_valid_choices;
        }
    }
    if (do_profile) {
        range_profile.cuda_prepare_ms += profile_ms(profile_start, ProfileClock::now());
    }
}

void NTHUR::RangeRouter::query_range_2pin(const Rectangle& r, //
        std::vector<Two_pin_element_2d*>& twopin_list, boost::multi_array<Point_fc, 2>& gridCell) {

    static int done_counter = 0;	//only initialize once

    for (int x = r.upLeft.x; x <= r.downRight.x; ++x) {
        for (int y = r.upLeft.y; y <= r.downRight.y; ++y) {
            Point_fc& cell = (gridCell[x][y]);

            for (Two_pin_element_2d* twopin : cell.points) {   //for each pin or steiner point
                if (twopin->done != construct_2d_tree.done_iter) {
                    Coordinate_2d& p1 = twopin->pin1;
                    Coordinate_2d& p2 = twopin->pin2;
                    if (colorMap[p1.x][p1.y].routeState != done_counter && //
                            colorMap[p2.x][p2.y].routeState != done_counter) {
                        if (r.contains(p1) || r.contains(p2)) {
                            twopin->done = construct_2d_tree.done_iter;
                            twopin_list.push_back(twopin);
                        }
                    }
                }
            }
            colorMap[cell.x][cell.y].routeState = done_counter;
        }
    }

    ++done_counter;
}

void NTHUR::RangeRouter::specify_all_range(boost::multi_array<Point_fc, 2>& gridCell) {
    std::vector<Two_pin_element_2d *> twopin_list;
    std::vector<int> twopin_range_index_list;
    const bool do_profile = profile_enabled();
    if (do_profile) {
        range_profile.reset();
    }

    for (u_int32_t i = 0; i < colorMap.num_elements(); ++i) {
        colorMap.data()[i].set(-1, -1);
    }

    total_twopin = 0;

    const bool use_direct_overflow_candidates =
            direct_overflow_candidates_enabled() || construct_2d_tree.force_direct_overflow_candidates;
    if (use_direct_overflow_candidates) {
        struct Candidate {
            Two_pin_element_2d* two_pin;
            int overflow_score;
        };

        auto profile_start = ProfileClock::now();
        std::vector<Candidate> candidates;
        const int length = construct_2d_tree.two_pin_list.size();
        for (int i = 0; i < length; ++i) {
            Two_pin_element_2d& two_pin = construct_2d_tree.two_pin_list[i];
            if (two_pin.done == construct_2d_tree.done_iter) {
                continue;
            }
            int overflow_score = 0;
            for (int path_index = static_cast<int>(two_pin.path.size()) - 2; path_index >= 0; --path_index) {
                const Edge_2d& edge = congestion.congestionMap2d.edge(two_pin.path[path_index], two_pin.path[path_index + 1]);
                overflow_score += std::max(0, edge.overUsage());
            }
            if (overflow_score > 0) {
                two_pin.done = construct_2d_tree.done_iter;
                candidates.push_back(Candidate { &two_pin, overflow_score });
            }
        }
        if (do_profile) {
            auto after_scan = ProfileClock::now();
            range_profile.direct_candidate_scan_ms += profile_ms(profile_start, after_scan);
            profile_start = after_scan;
        }

        sort(candidates.begin(), candidates.end(), [&](const Candidate& a, const Candidate& b) {
            if (a.overflow_score != b.overflow_score) {
                return a.overflow_score > b.overflow_score;
            }
            return Two_pin_element_2d::comp_stn_2pin(*a.two_pin, *b.two_pin);
        });
        if (do_profile) {
            auto after_sort = ProfileClock::now();
            range_profile.candidate_sort_ms += profile_ms(profile_start, after_sort);
        }

        const int limit = direct_overflow_candidate_limit();
        const int route_count = std::min(static_cast<int>(candidates.size()), limit);
        twopin_list.reserve(route_count);
        for (int i = 0; i < route_count; ++i) {
            twopin_list.push_back(candidates[i].two_pin);
        }

        log_sp->info("direct overflow candidate mode: candidates={} routed={} limit={}", candidates.size(), twopin_list.size(), limit);
        if (do_profile) {
            range_profile.candidates += candidates.size();
        }
        prepare_cuda_dogleg_choices(twopin_list);
        route_twopin_candidates(twopin_list, 2);

        construct_2d_tree.mazeroute_in_range.clear_net_tree();
        if (do_profile) {
            log_sp->info("profile range direct candidates={} route_calls={} actual_reroutes={} l_shape_success={} cuda_batches={} cuda_skipped_small_batches={} cuda_inputs={} cuda_valid_choices={} cuda_maze_attempts={} cuda_maze_success={} cuda_maze_area_skips={} cuda_maze_score_skips={} cuda_maze_call_limit_skips={} parallel_batches={} parallel_work_batches={} parallel_inputs={} parallel_serialized_inputs={} parallel_max_batch={} scan_ms={:.3f} sort_ms={:.3f} cuda_prepare_ms={:.3f} cuda_maze_ms={:.3f} reroute_ms={:.3f} check_old_ms={:.3f} remove_ms={:.3f} l_shape_ms={:.3f} monotonic_ms={:.3f} check_new_ms={:.3f} maze_ms={:.3f} insert_ms={:.3f}",
                    range_profile.candidates, range_profile.route_calls, range_profile.actual_reroutes,
                    range_profile.l_shape_success, range_profile.cuda_batches,
                    range_profile.cuda_skipped_small_batches, range_profile.cuda_inputs,
                    range_profile.cuda_valid_choices,
                    range_profile.cuda_maze_attempts, range_profile.cuda_maze_success,
                    range_profile.cuda_maze_area_skips, range_profile.cuda_maze_score_skips,
                    range_profile.cuda_maze_call_limit_skips,
                    range_profile.parallel_batches, range_profile.parallel_batches_with_work,
                    range_profile.parallel_inputs, range_profile.parallel_serialized_inputs,
                    range_profile.parallel_max_batch,
                    range_profile.direct_candidate_scan_ms, range_profile.candidate_sort_ms,
                    range_profile.cuda_prepare_ms, range_profile.cuda_maze_ms,
                    range_profile.reroute_ms, range_profile.check_old_path_ms, range_profile.remove_ms,
                    range_profile.l_shape_ms, range_profile.monotonic_ms, range_profile.check_new_path_ms,
                    range_profile.maze_ms, range_profile.insert_ms);
        }
        return;
    }

    for (int i = interval_list.size() - 1; i >= 0; --i) {
        Interval_element& ele = interval_list[i];
        range_vector.clear();
        auto profile_start = ProfileClock::now();
        sort(ele.grid_edge_vector.begin(), ele.grid_edge_vector.end(), [&](const Grid_edge_element& a, const Grid_edge_element& b) {
            return comp_grid_edge( a, b);
        });
        if (do_profile) {
            auto after_sort = ProfileClock::now();
            range_profile.interval_sort_ms += profile_ms(profile_start, after_sort);
            profile_start = after_sort;
        }

        for (Grid_edge_element& gridEdge : ele.grid_edge_vector) {
            Coordinate_2d& c = gridEdge.grid;
            Coordinate_2d& nei = gridEdge.c2;

            if ((colorMap[c.x][c.y].expand != i) || (colorMap[nei.x][nei.y].expand != i)) {
                colorMap[c.x][c.y].expand = i;
                colorMap[nei.x][nei.y].expand = i;

                expand_range(c, nei, i);
            }
        }
        if (do_profile) {
            auto after_expand = ProfileClock::now();
            range_profile.expand_ms += profile_ms(profile_start, after_expand);
            range_profile.ranges += range_vector.size();
            profile_start = after_expand;
        }

        twopin_list.clear();
        twopin_range_index_list.clear();
        for (Rectangle r : range_vector) {
            query_range_2pin(r, twopin_list, gridCell);
        }
        if (do_profile) {
            auto after_query = ProfileClock::now();
            range_profile.query_ms += profile_ms(profile_start, after_query);
            range_profile.candidates += twopin_list.size();
            profile_start = after_query;
        }

        if (range_sort_by_overflow_score_enabled()) {
            sort_twopins_by_overflow_score(twopin_list, congestion);
        } else {
            sort(twopin_list.begin(), twopin_list.end(), [&](const Two_pin_element_2d *a, const Two_pin_element_2d *b) {
                return Two_pin_element_2d::comp_stn_2pin(*a,*b);});
        }
        if (do_profile) {
            auto after_candidate_sort = ProfileClock::now();
            range_profile.candidate_sort_ms += profile_ms(profile_start, after_candidate_sort);
        }

        prepare_cuda_dogleg_choices(twopin_list);
        route_twopin_candidates(twopin_list, 2);
    }

    if (!skip_remainder_candidates_enabled() || construct_2d_tree.force_route_remainder) {
        twopin_list.clear();
        int length = construct_2d_tree.two_pin_list.size();
        for (int i = 0; i < length; ++i) {
            if (construct_2d_tree.two_pin_list[i].done != construct_2d_tree.done_iter) {
                twopin_list.push_back(&construct_2d_tree.two_pin_list[i]);
            }
        }

        if (range_sort_by_overflow_score_enabled()) {
            sort_twopins_by_overflow_score(twopin_list, congestion);
        } else {
            sort(twopin_list.begin(), twopin_list.end(), [&](const Two_pin_element_2d *a, const Two_pin_element_2d *b) {
                return Two_pin_element_2d::comp_stn_2pin(*a,*b);});
        }
        if (do_profile) {
            range_profile.candidates += twopin_list.size();
        }
        prepare_cuda_dogleg_choices(twopin_list);
        const int min_remainder_box = remainder_min_box_size();
        std::vector<Two_pin_element_2d*> remainder_twopins;
        for (int i = 0; i < (int) twopin_list.size(); ++i) {
            if (twopin_list[i]->boxSize() < min_remainder_box) {
                break;
            }
            remainder_twopins.push_back(twopin_list[i]);
        }
        route_twopin_candidates(remainder_twopins, 2);
    }

    construct_2d_tree.mazeroute_in_range.clear_net_tree();
    if (do_profile) {
        log_sp->info("profile range normal ranges={} candidates={} route_calls={} actual_reroutes={} l_shape_success={} cuda_batches={} cuda_skipped_small_batches={} cuda_inputs={} cuda_valid_choices={} cuda_maze_attempts={} cuda_maze_success={} cuda_maze_area_skips={} cuda_maze_score_skips={} cuda_maze_call_limit_skips={} parallel_batches={} parallel_work_batches={} parallel_inputs={} parallel_serialized_inputs={} parallel_max_batch={} interval_sort_ms={:.3f} expand_ms={:.3f} query_ms={:.3f} candidate_sort_ms={:.3f} cuda_prepare_ms={:.3f} cuda_maze_ms={:.3f} reroute_ms={:.3f} check_old_ms={:.3f} remove_ms={:.3f} l_shape_ms={:.3f} monotonic_ms={:.3f} check_new_ms={:.3f} maze_ms={:.3f} insert_ms={:.3f}",
                range_profile.ranges, range_profile.candidates, range_profile.route_calls, range_profile.actual_reroutes,
                range_profile.l_shape_success, range_profile.cuda_batches,
                range_profile.cuda_skipped_small_batches, range_profile.cuda_inputs,
                range_profile.cuda_valid_choices,
                range_profile.cuda_maze_attempts, range_profile.cuda_maze_success,
                range_profile.cuda_maze_area_skips, range_profile.cuda_maze_score_skips,
                range_profile.cuda_maze_call_limit_skips,
                range_profile.parallel_batches, range_profile.parallel_batches_with_work,
                range_profile.parallel_inputs, range_profile.parallel_serialized_inputs,
                range_profile.parallel_max_batch,
                range_profile.interval_sort_ms, range_profile.expand_ms, range_profile.query_ms,
                range_profile.candidate_sort_ms, range_profile.cuda_prepare_ms,
                range_profile.cuda_maze_ms, range_profile.reroute_ms,
                range_profile.check_old_path_ms, range_profile.remove_ms,
                range_profile.l_shape_ms, range_profile.monotonic_ms, range_profile.check_new_path_ms,
                range_profile.maze_ms, range_profile.insert_ms);
    }
}

NTHUR::RangeRouter::RangeRouter(Construct_2d_tree& construct2dTree, Congestion& congestion, bool monotonic_enable) :
        total_twopin(0),	//

        construct_2d_tree { construct2dTree }, //
        congestion { congestion }, //
        colorMap { boost::extents[congestion.congestionMap2d.getXSize()][congestion.congestionMap2d.getYSize()] },
        monotonicRouter { congestion, monotonic_enable },
        monotonic_enable_flag { monotonic_enable } {
    log_sp = spdlog::get("NTHUR");

}

