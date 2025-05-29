"""
stack_analyzer.py

An advanced static stack analyzer for embedded software using GCC's .su and
.cgraph files.

Key Features:
- Parses stack size per function from .su files across multiple directories.
- Builds a static call graph from .cgraph files from multiple directories.
- Auto-detects Interrupt Service Routines (ISRs) from the ELF vector table.
- Supports annotations for hard-to-analyze calls (e.g., callbacks) via --add-calls.
- Analyzes worst-case stack usage and call paths for different scenarios.
- Reports potentially uncalled functions or dead code (in debug mode).
"""

import os
import re
import argparse
from collections import defaultdict
from elftools.elf.elffile import ELFFile
from elftools.elf.sections import SymbolTableSection

# --- Constants ---
CGRAPH_SYMBOL_DEF_RE = re.compile(r"^([\w\d_.-]+)/(\d+)\s+\(([\w\d_.-]+)\)")
CGRAPH_CALLS_LINE_RE = re.compile(r"^\s*Calls:\s*(.*)")
VECTOR_TABLE_SKIP_BYTES = 4  # Skip Main Stack Pointer (MSP)
VECTOR_ADDR_SIZE_BYTES = 4
# ANSI escape codes for colored terminal output
COLOR_BRIGHT_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_RESET = "\033[0m"

# --- Global Variables ---
# A list to collect warnings to be displayed at the end of the analysis.
g_deferred_warnings = []


# --- Helper Functions ---
def debug_print(message, is_debug_mode):
    """Conditionally prints a debug message."""
    if is_debug_mode:
        print(message)


def _validate_file_path(filepath):
    """Checks if a file exists, exiting if it doesn't."""
    if filepath and not os.path.exists(filepath):
        print(f"Error: File not found: '{filepath}'")
        exit(1)


# --- Core Parsing and Graph Building Functions ---
def parse_su_files(su_dirs, is_debug_mode):
    """
    Recursively parses .su files from a list of directories.

    Args:
        su_dirs (list): A list of directories containing .su files.
        is_debug_mode (bool): Flag to enable debug output.

    Returns:
        dict: A dictionary of {function_name: stack_size}.
    """
    stack_usage = {}
    total_files_processed = 0

    for su_dir in su_dirs:
        if not os.path.isdir(su_dir):
            print(f"{COLOR_BRIGHT_YELLOW}[Warning] Directory for --su-dir not found, skipping: {su_dir}{COLOR_RESET}")
            continue

        debug_print(f"  DBG: Walking SU directory: {su_dir}", is_debug_mode)
        
        for dirpath, _, filenames in os.walk(su_dir):
            for filename in filenames:
                if filename.endswith(".su"):
                    total_files_processed += 1
                    filepath = os.path.join(dirpath, filename)
                    debug_print(f"    -> Parsing .su file ({total_files_processed}): {filepath}", is_debug_mode)
                    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                        for line in f:
                            try:
                                parts = line.strip().split()
                                if len(parts) >= 2:
                                    func_name = parts[0].split(':')[3]
                                    stack_size = int(parts[1])
                                    if func_name not in stack_usage or stack_size > stack_usage[func_name]:
                                        stack_usage[func_name] = stack_size
                            except (IndexError, ValueError):
                                print(f"  [Warning] Skipping malformed line in '{filepath}': '{line.strip()}'")

    debug_print(f"  DBG: Processed a total of {total_files_processed} .su files.", is_debug_mode)
    return stack_usage


def load_annotation_file(filepath):
    """
    Loads a call relationship annotation file (e.g., --ignore-calls, --add-calls).
    """
    annotation_set = set()
    if not filepath:
        return annotation_set

    _validate_file_path(filepath)
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = [part.strip() for part in line.split(',')]
            if len(parts) == 2 and all(parts):
                annotation_set.add(tuple(parts))
            else:
                print(f"  [Warning] Skipping malformed line {i} in '{filepath}': '{line}'")
                print(f"            Expected format: caller_function,callee_function")
    return annotation_set


def build_base_call_graph_from_cgraph(cgraph_dirs, ignore_set, is_debug_mode):
    """
    Builds the base call graph from a list of cgraph directories.
    """
    symbol_map = {}
    temp_call_relations = defaultdict(list)
    any_cgraph_files_found = False
    total_files_processed = 0

    for cgraph_dir in cgraph_dirs:
        if not os.path.isdir(cgraph_dir):
            print(f"{COLOR_BRIGHT_YELLOW}[Warning] Directory for --cgraph-dir not found, skipping: {cgraph_dir}{COLOR_RESET}")
            continue

        debug_print(f"  DBG: Walking cgraph directory: {cgraph_dir}", is_debug_mode)
        current_caller_name_in_file = None
        
        for dirpath, _, filenames in os.walk(cgraph_dir):
            for filename in filenames:
                if ".cgraph" not in filename and ".ipa" not in filename:
                    continue

                any_cgraph_files_found = True
                total_files_processed += 1
                filepath = os.path.join(dirpath, filename)
                
                debug_print(f"    -> Processing cgraph file ({total_files_processed}): {filepath}", is_debug_mode)

                with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                    for line in f:
                        symbol_match = CGRAPH_SYMBOL_DEF_RE.match(line)
                        if symbol_match:
                            name_with_id, num_id, actual_name = symbol_match.groups()
                            symbol_map[f"{name_with_id}/{num_id}"] = actual_name
                            current_caller_name_in_file = actual_name
                            continue
                        if current_caller_name_in_file:
                            calls_match = CGRAPH_CALLS_LINE_RE.match(line)
                            if calls_match:
                                temp_call_relations[current_caller_name_in_file].extend(calls_match.group(1).split())
                                current_caller_name_in_file = None

    if not any_cgraph_files_found:
        dirs_str = ', '.join(cgraph_dirs)
        msg = (f"{COLOR_BRIGHT_YELLOW}[Warning] No .cgraph or .ipa files found in specified directories: {dirs_str}\n"
               f"   To generate them, the project must be built with the '-fdump-ipa-cgraph' compiler option.{COLOR_RESET}")
        g_deferred_warnings.append(msg)
    
    debug_print(f"  DBG: Processed a total of {total_files_processed} cgraph/ipa files.", is_debug_mode)
    debug_print(f"  DBG: Symbol map built with {len(symbol_map)} entries.", is_debug_mode)

    call_graph = defaultdict(list)
    unresolved_report = []
    for caller_name, callee_symbols in temp_call_relations.items():
        caller_normalized = caller_name.split('.')[0]
        for callee_symbol in callee_symbols:
            actual_callee_name = symbol_map.get(callee_symbol)
            if actual_callee_name:
                callee_normalized = actual_callee_name.split('.')[0]
                if (caller_normalized, callee_normalized) not in ignore_set:
                    if callee_normalized not in call_graph[caller_normalized]:
                        call_graph[caller_normalized].append(callee_normalized)
            else:
                unresolved_report.append((caller_normalized, callee_symbol))

    debug_print("  DBG: Finished cgraph processing.", is_debug_mode)
    return call_graph, unresolved_report, any_cgraph_files_found


def get_isr_entry_points(elf_file, vector_table_name, is_debug_mode):
    """Extracts ISR entry points from the ELF file's vector table."""
    entry_points = set()
    try:
        with open(elf_file, 'rb') as f:
            elffile = ELFFile(f)
            symtab = elffile.get_section_by_name('.symtab')
            if not isinstance(symtab, SymbolTableSection):
                debug_print("  DBG: No symbol table in ELF for ISRs.", is_debug_mode)
                return []

            vector_symbols = [s for s in symtab.iter_symbols() if s.name == vector_table_name]
            if not vector_symbols:
                debug_print(f"  DBG: Vector table symbol '{vector_table_name}' not in ELF.", is_debug_mode)
                return []

            vector_section = elffile.get_section(vector_symbols[0]['st_shndx'])
            vector_data = vector_section.data()
            table_offset = vector_symbols[0]['st_value'] - vector_section['sh_addr']

            for i in range(VECTOR_TABLE_SKIP_BYTES, len(vector_data) - table_offset, VECTOR_ADDR_SIZE_BYTES):
                addr_bytes = vector_data[table_offset + i : table_offset + i + VECTOR_ADDR_SIZE_BYTES]
                addr = int.from_bytes(addr_bytes, 'little')
                if addr in (0, 0xFFFFFFFF):
                    continue
                
                target_addr = addr & 0xFFFFFFFE
                for sym in symtab.iter_symbols():
                    if (sym.entry['st_info']['type'] == 'STT_FUNC' and
                            sym['st_value'] == target_addr):
                        entry_points.add(sym.name.split('.')[0])
                        break
    except Exception as e:
        print(f"  Error reading ISRs from ELF file: {e}")
    return sorted(list(entry_points))


# --- Analysis and Reporting Functions ---
def find_worst_case_stack_path(start_function, call_graph, stack_usage, scenario_additions=None):
    """
    DFS(깊이 우선 탐색)를 사용하여 특정 시작 함수로부터 최악의 스택 사용 경로를 찾습니다.
    이 함수는 메모이제이션(Memoization) 기법을 사용하여 중복 계산을 피해 성능을 최적화합니다.

    Args:
        start_function (str): 분석을 시작할 함수 이름.
        call_graph (dict): 기본 호출 그래프.
        stack_usage (dict): 함수별 스택 사용량 정보.
        scenario_additions (dict, optional): 시나리오별로 추가된 {caller: [callee]} 호출.

    Returns:
        tuple: (total_stack, path)
               - total_stack (float): 최악 경로의 총 스택 사용량. 재귀 시 'inf'.
               - path (list): 최악 스택 사용량에 해당하는 호출 경로.
    """
    # 메모이제이션을 위한 딕셔너리(캐시)입니다.
    # 한번 계산된 함수의 결과 (최악 스택, 경로)를 저장하여 중복 계산을 방지합니다.
    memo = {}
    scenario_additions = scenario_additions or {}

    def get_callees(func):
        """기본 그래프와 시나리오 추가 호출을 합쳐서 자식 노드(피호출자)를 반환합니다."""
        base_callees = call_graph.get(func, [])
        added_callees = scenario_additions.get(func, [])
        return list(dict.fromkeys(base_callees + added_callees))  # 중복 제거

    def dfs(func, visited_path):
        """재귀적 깊이 우선 탐색 함수."""
        # --- [메모이제이션 - 1단계: 결과 확인 및 재사용] ---
        # 이전에 'func'에 대한 최악 경로를 이미 계산했다면, 저장된 결과를 즉시 반환합니다.
        # 이를 통해 동일한 함수에 대한 반복적인 경로 탐색을 방지하여 성능을 크게 향상시킵니다.
        if func in memo:
            return memo[func]

        # 순환 경로 감지 (현재 탐색 중인 경로에 func이 이미 포함된 경우)
        if func in visited_path:
            recursion_path = visited_path[visited_path.index(func):] + [func]
            return (float('inf'), recursion_path)

        # --- [경로 탐색 및 계산] ---
        # (이 부분은 func에 대한 결과가 캐시에 없을 때만 실행됩니다)
        path_with_current = visited_path + [func]
        max_stack_from_callees, worst_callee_path = 0, []

        for callee in get_callees(func):
            # 하위 함수(callee)에 대한 최악 경로를 재귀적으로 탐색합니다.
            stack, path_suffix = dfs(callee, path_with_current)
            # 가장 스택을 많이 사용하는 하위 경로를 선택합니다.
            if stack > max_stack_from_callees:
                max_stack_from_callees = stack
                worst_callee_path = path_suffix

        # 현재 함수의 스택 크기와 하위 경로의 최대 스택 크기를 더합니다.
        current_stack = stack_usage.get(func, stack_usage.get(func.split('.')[0], 0))
        total_stack = current_stack + max_stack_from_callees
        final_path = [func] + worst_callee_path

        # --- [메모이제이션 - 2단계: 결과 저장] ---
        # 'func'에 대한 경로 계산이 끝난 후, 그 결과를 'memo' 딕셔너리에 저장합니다.
        # 키(key)는 함수 이름, 값(value)은 (총 스택, 경로 리스트) 튜플입니다.
        # 순환 경로('inf')가 아닌 유효한 결과만 저장하여, 다음 번 동일한 'func' 호출 시 재사용할 수 있도록 합니다.
        if total_stack != float('inf'):
            memo[func] = (total_stack, final_path)
            
        return total_stack, final_path

    # 분석 시작 함수부터 DFS 탐색을 시작합니다.
    return dfs(start_function, [])


def _run_uncalled_functions_analysis(stack_usage, base_call_graph, all_scenarios_add_sets, entry_points):
    """Analyzes and reports potentially uncalled functions."""
    print("\n--- Analysis of Potentially Uncalled Functions (Possible Callbacks or Dead Code) ---")
    all_defined_funcs = {name.split('.')[0] for name in stack_usage.keys()}
    all_statically_called_funcs = {callee for callees in base_call_graph.values() for callee in callees}
    all_manually_added_callees = {
        callee.split('.')[0]
        for add_set in all_scenarios_add_sets.values()
        for _, callee in add_set
    }
    normalized_entry_points = {ep.split('.')[0] for ep in entry_points}
    uncalled_funcs = all_defined_funcs - all_statically_called_funcs - all_manually_added_callees - normalized_entry_points

    if uncalled_funcs:
        print(f"  Found {len(uncalled_funcs)} function(s) with stack info that are NOT statically called,")
        print(f"  NOT specified as entry points, AND NOT found as a callee in any --add-calls scenario.")
        print(f"  These might be unhandled callbacks needing --add-calls, or could be dead code:")
        original_name_map = {name.split('.')[0]: name for name in stack_usage.keys()}
        report_list = [
            f"    - {original_name_map.get(norm_name, norm_name)} "
            f"(Stack: {stack_usage.get(original_name_map.get(norm_name, norm_name), 0)} bytes)"
            for norm_name in sorted(list(uncalled_funcs))
        ]
        for item in report_list:
            print(item)
    else:
        print("  All functions with stack info appear to be called, are entry points, or are added in scenarios.")
    print("-" * 70)


def _run_scenario_analysis(entry_points, base_call_graph, stack_usage, all_scenarios_add_sets, is_debug_mode):
    """Runs stack analysis for all scenarios and finds the absolute worst case."""
    overall_worst_stack, overall_worst_path, winning_scenario_name = 0, [], "None (Base)"
    scenarios_to_run = list(all_scenarios_add_sets.keys()) if all_scenarios_add_sets else [None]

    for scenario_file in scenarios_to_run:
        scenario_name = os.path.basename(scenario_file) if scenario_file else 'Base (no callbacks added)'
        print(f"\n--- Analyzing Scenario: {scenario_name} ---")

        add_set = all_scenarios_add_sets.get(scenario_file, set())
        scenario_additions = defaultdict(list)
        if add_set:
            debug_print(f"  DBG: Applying {len(add_set)} manual calls from '{scenario_name}'...", is_debug_mode)
            for caller, callee in add_set:
                scenario_additions[caller].append(callee)

        scenario_worst_stack, scenario_worst_path = 0, []
        for start_func in entry_points:
            total_stack, path = find_worst_case_stack_path(start_func, base_call_graph, stack_usage, scenario_additions)
            if total_stack > scenario_worst_stack:
                scenario_worst_stack, scenario_worst_path = total_stack, path

        if scenario_worst_stack == float('inf'):
            print(f"  Result: Indirect recursion detected.")
            print(f"    Recursive Path: {' -> '.join(scenario_worst_path)}")
        else:
            print(f"  Scenario Worst-case: {int(scenario_worst_stack)} bytes")

        if scenario_worst_stack > overall_worst_stack:
            overall_worst_stack, overall_worst_path = scenario_worst_stack, scenario_worst_path
            winning_scenario_name = scenario_name

    return overall_worst_stack, overall_worst_path, winning_scenario_name


def _print_deferred_warnings(warnings):
    """Prints all warnings that were collected during the analysis."""
    if warnings:
        header = "=" * 70
        print(f"\n\n{header}")
        print("--- Analysis Warnings ---".center(70))
        print(f"{header}\n")
        for warning in warnings:
            print(warning)


def _print_final_results(worst_stack, worst_path, scenario_name, stack_usage):
    """Prints the final formatted analysis results."""
    header = "=" * 70
    print(f"\n\n{header}")
    print("--- Overall Analysis Final Result ---".center(70))
    print(f"{header}\n")

    if not worst_path:
        print("Error: Could not determine any valid call path.")
    else:
        print(f"Absolute worst-case found in scenario: '{scenario_name}'")
        if worst_stack == float('inf'):
            print("Error: Indirect recursion detected in the worst-case path!")
            print("\nRecursive call path found:")
            print(" -> ".join(worst_path))
        else:
            print(f"Worst-case stack usage: {int(worst_stack)} bytes")
            print("\nWorst-case call path (function, size, cumulative):")
            cumulative_size = 0
            indent = ""
            for func in worst_path:
                size = stack_usage.get(func, stack_usage.get(func.split('.')[0], 0))
                cumulative_size += size
                print(f"{indent}{func} (size: {size}, total: {cumulative_size})")
                indent += "  "
    print(f"\n{header}")


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description="Advanced static stack analyzer using GCC cgraph files.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('--elf-file', required=True, help="Path to the output ELF file.")
    parser.add_argument('--su-dir', nargs='+', help="One or more directories containing .su files.")
    parser.add_argument('--cgraph-dir', nargs='+', help="One or more directories containing .cgraph files.")
    parser.add_argument('--start-func', default='main', help="Comma-separated list of entry points (e.g., main,task1).")
    parser.add_argument('--vector-table', help="Symbol name of the vector table (e.g., g_pfnVectors).")
    parser.add_argument('--ignore-calls', help="File with 'caller,callee' pairs to ignore.")
    parser.add_argument('--add-calls', nargs='+', help="One or more annotation files for callback scenarios.")
    parser.add_argument('--debug', action='store_true', help="Enable detailed debug printing.")
    args = parser.parse_args()

    debug_print("DEBUG MODE ENABLED", args.debug)

    if not args.su_dir and not args.cgraph_dir:
        parser.error("At least one of --su-dir or --cgraph-dir must be specified.")

    su_dirs = args.su_dir if args.su_dir else args.cgraph_dir
    cgraph_dirs = args.cgraph_dir if args.cgraph_dir else args.su_dir

    if not args.su_dir:
        debug_print(f"  DBG: --su-dir not specified, defaulting to cgraph-dir: {su_dirs}", args.debug)
    if not args.cgraph_dir:
        debug_print(f"  DBG: --cgraph-dir not specified, defaulting to su-dir: {cgraph_dirs}", args.debug)

    # 1. Parse Stack Usage (.su) files
    print("1. Parsing .su files...")
    stack_usage = parse_su_files(su_dirs, args.debug)

    if not stack_usage:
        dirs_str = ', '.join(su_dirs)
        print(f"{COLOR_RED}[Error] No stack usage (.su) files found in specified directories: {dirs_str}")
        print(f"   Please ensure the project is built with the '-fstack-usage' compiler option.{COLOR_RESET}")
        exit(1)
    print(f"   Found stack usage for {len(stack_usage)} functions.")

    # 2. Build Call Graph (.cgraph) files
    print("\n2. Building base call graph...")
    ignore_set = load_annotation_file(args.ignore_calls)
    base_call_graph, _, _ = build_base_call_graph_from_cgraph(cgraph_dirs, ignore_set, args.debug)
    
    if base_call_graph is None:
        print("Fatal: Failed to build base call graph. Exiting.")
        exit(1)
    print(f"   Base call graph built with {len(base_call_graph)} calling functions.")

    # 3. Determine Entry Points
    print("\n3. Determining analysis entry points...")
    entry_points = set(filter(None, [name.strip() for name in args.start_func.split(',')]))
    if not entry_points:
        entry_points = {'main'}
        print("   --start-func was empty. Defaulting to: ['main']")
    else:
        print(f"   Specified entry points: {sorted(list(entry_points))}")

    if args.vector_table:
        isrs = get_isr_entry_points(args.elf_file, args.vector_table, args.debug)
        if isrs:
            newly_added = set(isrs) - entry_points
            if newly_added:
                print(f"   Adding {len(newly_added)} new ISR(s) from vector table: {sorted(list(newly_added))}")
                entry_points.update(newly_added)

    final_entry_points = sorted(list(entry_points))
    if not final_entry_points:
        print(f"\n{COLOR_RED}Error: No valid entry points found for analysis. Exiting.{COLOR_RESET}")
        exit(1)
    print(f"   Final entry points for analysis: {final_entry_points}")

    # 4. Run Analyses
    all_scenarios_add_sets = {f: load_annotation_file(f) for f in args.add_calls} if args.add_calls else {}
    
    if args.debug:
        _run_uncalled_functions_analysis(stack_usage, base_call_graph, all_scenarios_add_sets, final_entry_points)
    
    worst_stack, worst_path, scenario_name = _run_scenario_analysis(
        final_entry_points, base_call_graph, stack_usage, all_scenarios_add_sets, args.debug
    )

    # 5. Print Final Results and Deferred Warnings
    _print_final_results(worst_stack, worst_path, scenario_name, stack_usage)
    _print_deferred_warnings(g_deferred_warnings)


if __name__ == "__main__":
    main()
