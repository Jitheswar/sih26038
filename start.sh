#!/usr/bin/env bash
#
# SIH26038 - Explainable AI for DR Screening
# Demo launcher.
#
#   ./start.sh            launch the screening GUI (default - use this for judges)
#   ./start.sh demo       headless single-image run, prints the full decision trace
#   ./start.sh numbers    print the frozen operating point and the headline results
#   ./start.sh tests      run the full test suite (212 tests)
#   ./start.sh check      preflight only: verify MATLAB, model, calibration, data
#
# The Arch/Wayland environment variables below are documented in
# design doc section 14.2. Without them MATLAB either segfaults on the
# bundled libstdc++ or renders a blank grey window under Wayland.

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# ---------------------------------------------------------------- appearance
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s  ok  %s %s\n' "$GREEN" "$RESET" "$*"; }
bad()  { printf '%s fail %s %s\n' "$RED" "$RESET" "$*"; }
warn() { printf '%s warn %s %s\n' "$YELLOW" "$RESET" "$*"; }
head2(){ printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }

# ------------------------------------------------------------------ env (14.2)
SIH_PRELOAD="/usr/lib/libstdc++.so.6:/usr/lib/libfreetype.so.6"
if [[ -n "${LD_PRELOAD:-}" ]]; then
    export LD_PRELOAD="${LD_PRELOAD}:${SIH_PRELOAD}"
else
    export LD_PRELOAD="$SIH_PRELOAD"
fi
export _JAVA_AWT_WM_NONREPARENTING=1

MATLAB_BIN="${MATLAB_BIN:-$(command -v matlab || true)}"

# --------------------------------------------------------- process control
# MATLAB installs its own SIGINT handler. Under "-nodesktop -r" a Ctrl+C is
# taken to mean "interrupt the current MATLAB statement", so it breaks out of
# uiwait, drops to the >> prompt, and leaves both the MATLAB process and the
# app window alive while this script is still blocked waiting on it. The
# terminal never comes back and the demo cannot be stopped.
#
# Running MATLAB as a background job and terminating it from a trap is what
# makes Ctrl+C actually stop the demo. Descendants are signalled too: MATLAB
# spawns helper and renderer processes that outlive a bare kill of the parent.
MATLAB_PID=""

kill_tree() {
    local pid=$1 signal=$2 child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child" "$signal"
    done
    kill -"$signal" "$pid" 2>/dev/null || true
}

stop_matlab() {
    [[ -z "$MATLAB_PID" ]] && return 0
    kill -0 "$MATLAB_PID" 2>/dev/null || { MATLAB_PID=""; return 0; }
    kill_tree "$MATLAB_PID" TERM
    local waited=0
    while kill -0 "$MATLAB_PID" 2>/dev/null && (( waited < 40 )); do
        sleep 0.25
        waited=$(( waited + 1 ))
    done
    if kill -0 "$MATLAB_PID" 2>/dev/null; then
        kill_tree "$MATLAB_PID" KILL
    fi
    MATLAB_PID=""
}

on_interrupt() {
    printf '\n'
    warn "interrupted - stopping MATLAB"
    stop_matlab
    exit 130
}

trap on_interrupt INT TERM HUP
trap stop_matlab EXIT

run_matlab() {
    # A background job in a non-interactive shell has no separate process
    # group, so it stays in the terminal's foreground group and may read the
    # tty without being stopped by SIGTTIN. The GUI needs that: MATLAB must
    # stay in its interactive configuration or every blocking dialog,
    # uigetfile included, refuses to open.
    if [[ -r /dev/tty ]]; then
        "$MATLAB_BIN" "$@" < /dev/tty &
    else
        "$MATLAB_BIN" "$@" < /dev/null &
    fi
    MATLAB_PID=$!
    local status=0
    wait "$MATLAB_PID" || status=$?
    MATLAB_PID=""
    return $status
}

# ------------------------------------------------------------------ preflight
preflight() {
    local failed=0

    head2 "Environment"
    if [[ -z "$MATLAB_BIN" ]]; then
        bad "matlab not found on PATH (set MATLAB_BIN=/path/to/matlab)"
        failed=1
    else
        ok "matlab: $MATLAB_BIN"
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        ok "Wayland detected - non-reparenting workaround active (14.2)"
    fi

    head2 "Frozen operating point (config/default.json)"
    if [[ ! -f config/default.json ]]; then
        bad "config/default.json is missing"
        return 1
    fi

    # Read the frozen paths straight from config so the demo can never run a
    # different model than the reported numbers describe.
    local model calib
    model=$(python3 -c "import json;print(json.load(open('config/default.json'))['operating_point']['model'])" 2>/dev/null)
    calib=$(python3 -c "import json;print(json.load(open('config/default.json'))['operating_point']['calibration'])" 2>/dev/null)

    if [[ -z "$model" ]]; then
        bad "could not read operating_point.model from config/default.json"
        failed=1
    elif [[ -f "$model" ]]; then
        ok "model checkpoint: $model"
    else
        bad "model checkpoint missing: $model"
        failed=1
    fi

    if [[ -z "$calib" ]]; then
        bad "could not read operating_point.calibration"
        failed=1
    elif [[ -f "$calib" || -f "$calib/temperature_fit.mat" ]]; then
        ok "calibration: $calib"
    else
        bad "calibration missing: $calib"
        failed=1
    fi

    # Which evidence channel the demo will actually run. The learned channel
    # is trained and is the better localiser by a wide margin, but 11.6 A9
    # measured it escalating 512 of 550 frames, so the deployed configuration
    # keeps the classical channel. A presenter asked "which one is live?"
    # should not have to guess, and a judge who asks is asking a good question.
    local learned lesion_ckpt heads
    learned=$(python3 -c "import json;print(json.load(open('config/default.json'))['pipeline'].get('learned_lesion_evidence', False))" 2>/dev/null)
    if [[ "$learned" == "True" ]]; then
        lesion_ckpt=$(python3 -c "import json;print(json.load(open('config/default.json'))['lesion_segmentation']['checkpoint'])" 2>/dev/null)
        heads=$(python3 -c "import json;d=json.load(open('config/default.json'))['lesion_segmentation'];print('+'.join(d.get('evidence_heads') or d['lesion_types']))" 2>/dev/null)
        if [[ -n "$lesion_ckpt" && -f "$lesion_ckpt" ]]; then
            ok "lesion evidence: learned segmentation, heads $heads"
            ok "lesion checkpoint: $lesion_ckpt"
        else
            bad "learned_lesion_evidence is on but its checkpoint is missing: $lesion_ckpt"
            failed=1
        fi
    else
        ok "lesion evidence: classical candidate detector (learned channel off, 11.6 A9)"
    fi

    head2 "Demo data"
    local n
    n=$(ls data/raw/aptos2019/train_images/*.png 2>/dev/null | wc -l)
    if [[ "$n" -gt 0 ]]; then
        ok "APTOS images available: $n"
    else
        bad "no APTOS images under data/raw/aptos2019/train_images/"
        failed=1
    fi

    # The sealed set must never be touched by a demo. Report only that it is
    # present and sealed; never read into it (design doc 10.4).
    if [[ -d data/sealed ]]; then
        ok "data/sealed/ present and NOT accessed by any demo path (10.4)"
    fi

    return $failed
}

# ------------------------------------------------------------------- actions
launch_gui() {
    preflight || { bad "preflight failed - fix the above before demoing"; exit 1; }
    head2 "Launching the screening GUI"
    say "${DIM}Close the app window, or press Ctrl+C here, to return to this shell.${RESET}"
    say ""
    # The -r argument must be a single line. A multi-line string is silently
    # dropped ("No MATLAB command specified for -r"), MATLAB then sits at the
    # prompt and exits when stdin closes, so no window ever appears.
    #
    # This must NOT be -batch. -batch sets batchStartupOptionUsed, which puts
    # MATLAB in a non-interactive configuration where every blocking dialog is
    # refused, so "Select fundus image" dies with "Creating dialog boxes that
    # block execution is not supported". The GUI needs the interactive
    # configuration; Ctrl+C is handled by the trap above, not by the mode.
    run_matlab -nodesktop -nosplash -r "addpath(genpath('src')); addpath('app'); a = ScreeningApp; uiwait(a.UIFigure); exit(0);"
}

run_demo() {
    preflight || { bad "preflight failed"; exit 1; }
    head2 "Single-image screening demo"
    say "${DIM}Runs quality gate, grading, Grad-CAM, lesion evidence, decision policy,${RESET}"
    say "${DIM}then exports the annotated report.${RESET}"
    say ""
    run_matlab -batch "addpath(genpath('src')); addpath('eval'); appSmoke()"
}

show_numbers() {
    head2 "SIH26038 - headline results"
    python3 - <<'PY'
import json
c = json.load(open('config/default.json'))
op = c.get('operating_point', {})
lesion = c.get('lesion_segmentation', {})
if c.get('pipeline', {}).get('learned_lesion_evidence'):
    heads = lesion.get('evidence_heads') or lesion.get('lesion_types', [])
    live = 'learned segmentation, heads ' + '+'.join(heads)
else:
    live = 'classical candidate detector'
print(f"""
  Frozen operating point            {op.get('referable_threshold')}  (frozen {op.get('frozen_on')})
  Temperature (calibration)         {op.get('temperature')}
  Checkpoint                        {op.get('model')}

  REFERABLE DR (ICDR >= 2), validation split, n = 550
    Sensitivity                     {op.get('validation_sensitivity')}     target > 0.90
    Specificity                     {op.get('validation_specificity')}     target > 0.85

  Both targets are met at the frozen threshold on internal validation.
  The sealed external set (Messidor-2) has NOT been opened.

  LESION EVIDENCE CHANNEL
    Live in this demo                {live}
    Learned channel, all four heads  sensitivity 1.0000 / specificity 0.0000  (A6)
    Learned channel, exudates only   sensitivity 0.8072 / specificity 0.8257  (A8)

  The learned channel is the better localiser (4.87x pointing game vs 1.32x
  for Grad-CAM) and was still unusable as ICDR evidence until its thresholds
  were re-selected on the calibration split. Restricting it to its one
  trustworthy head fixed the channel and barely moved the pipeline, so the
  classical channel stays deployed. Both numbers are reported.
""")
PY
    say "${DIM}Full metric set, confidence intervals and the ablation table are in${RESET}"
    say "${DIM}docs/SIH26038_design.html sections 11.2, 11.3 and 11.6.${RESET}"
}

run_tests() {
    head2 "Full test suite"
    say "${DIM}This takes about 8 minutes.${RESET}"
    say ""
    run_matlab -batch "assertSuccess(runtests('tests','IncludeSubfolders',true))"
}

usage() {
    cat <<EOF
${BOLD}SIH26038 - Explainable AI for DR Screening${RESET}

  ${BOLD}./start.sh${RESET}            launch the screening GUI  ${DIM}(use this for judges)${RESET}
  ${BOLD}./start.sh demo${RESET}       headless single-image run with full decision trace
  ${BOLD}./start.sh numbers${RESET}    print the frozen operating point and headline results
  ${BOLD}./start.sh tests${RESET}      run the full test suite
  ${BOLD}./start.sh check${RESET}      preflight only

EOF
}

case "${1:-gui}" in
    gui|"")       launch_gui ;;
    demo)         run_demo ;;
    numbers|nums) show_numbers ;;
    tests|test)   run_tests ;;
    check)        preflight && ok "all preflight checks passed" ;;
    -h|--help|help) usage ;;
    *)            bad "unknown option: $1"; usage; exit 1 ;;
esac
