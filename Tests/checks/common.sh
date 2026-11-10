# Sourced by every Tests/checks/<name>/run.sh once it has set `here` (its own folder).
#
# Sets `root` (the repository: every path in a check's compile line starts there), `name` (the
# check's folder name) and `out` (.build/checks/<name>: its binary, data and logs; .build is
# git-ignored), makes `out`, and changes to `root`. Gives `run_mutants`.
# 编译检查前把两个目录的英文合并进可执行文件旁，供 Bundle.main 加载复数规则。
set -euo pipefail
root="$(cd "$here/../../.." && pwd)"
name="$(basename "$here")"
out="$root/.build/checks/$name"
mkdir -p "$out"
cd "$root"

compile_check_localizations() {
    local catalog="$out/Localizable.xcstrings"
    python3 - "$root" "$catalog" <<'PYTHON'
import json
from pathlib import Path
import sys

root, output = map(Path, sys.argv[1:])
merged = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
for relative in ("iOSClient/Localizable.xcstrings", "Packaging/Localizable.xcstrings"):
    catalog = json.loads((root / relative).read_text())
    for key, entry in catalog["strings"].items():
        if entry.get("extractionState") == "stale":
            continue
        target = merged["strings"].setdefault(key, {})
        english = entry.get("localizations", {}).get("en")
        if english is not None:
            existing = target.setdefault("localizations", {}).get("en")
            if existing is not None and existing != english:
                raise ValueError(f"两个目录的英文定义不一致：{key}")
            target["localizations"]["en"] = english
output.write_text(json.dumps(merged, ensure_ascii=False))
PYTHON
    # 清掉上次的编译结果，避免目录错误时误加载旧的复数变体。
    rm -rf "$out/en.lproj"
    xcrun xcstringstool compile "$catalog" --output-directory "$out" --language en
    if [ ! -d "$out/en.lproj" ]; then
        echo "${name}：英文目录未生成；请把英文复数变体标为 translated。" >&2
        return 1
    fi
}

compile_check_localizations

# run_mutants COMMAND [ARG...]: runs a check's mutants script. Each mutant changes the checked source
# in one place, compiles it with the check and must make the check fail. The script's last word is
# a count, "12 of 12 mutants caught" or "mutants caught: 12 of 12", and some scripts exit 0 whatever
# it says, so the count decides: every mutant caught and a zero exit, or this returns 1.
run_mutants() {
    local log="$out/mutants.log" status summary=""
    set +e
    PYTHONUNBUFFERED=1 "$@" 2>&1 | tee "$log"   # unbuffered: each mutant's line as it is judged
    status=${PIPESTATUS[0]}
    set -e
    summary="$(grep -E '[0-9]+ of [0-9]+ mutants caught|mutants caught: [0-9]+ of [0-9]+' "$log" | tail -n 1 || true)"
    if [[ "$summary" =~ ([0-9]+)\ of\ ([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] && [ "$status" -eq 0 ]; then
        echo "$name: every mutant caught (${BASH_REMATCH[1]} of ${BASH_REMATCH[2]})"
        return 0
    fi
    echo "$name: mutants FAILED (exit status $status; ${summary:-no count printed}); the log is $log" >&2
    return 1
}
