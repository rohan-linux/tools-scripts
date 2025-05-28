"""
stack_analyzer.py

An advanced static stack analyzer for embedded software using GCC's .su and
.cgraph files.

Key Features:
- Parses stack size per function from .su files.
- Builds a static call graph from .cgraph files using a single-pass method.
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
def parse_su_files(su_dir, is_debug_mode):
    """
    Recursively parses .su files to extract stack usage per function.

    Args:
        su_dir (str): Directory containing .su files.
        is_debug_mode (bool): Flag to enable debug output.

    Returns:
        dict: A dictionary of {function_name: stack_size}.
              Returns None if the directory is not found.
    """
    stack_usage = {}
    if not os.path.isdir(su_dir):
        print(f"Error: Directory not found - {su_dir}")
        return None

    debug_print(f"  DBG: Starting to walk SU directory: {su_dir}", is_debug_mode)
    file_count = 0
    for dirpath, _, filenames in os.walk(su_dir):
        for filename in filenames:
            if filename.endswith(".su"):
                file_count += 1
                filepath = os.path.join(dirpath, filename)
                debug_print(f"    -> Parsing .su file ({file_count}): {filepath}", is_debug_mode)
                with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                    for line in f:
                        try:
                            parts = line.strip().split()
                            if len(parts) >= 2:
                                func_name = parts[0].split(':')[3]
                                stack_size = int(parts[1])
                                stack_usage[func_name] = stack_size
                        except (IndexError, ValueError):
                            print(f"  [Warning] Skipping malformed line in '{filepath}': '{line.strip()}'")

    debug_print(f"  DBG: Processed a total of {file_count} .su files.", is_debug_mode)
    debug_print(f"  DBG: Finished parsing SU files.", is_debug_mode)
    return stack_usage


def load_annotation_file(filepath):
    """
    Loads a call relationship annotation file (e.g., --ignore-calls, --add-calls).

    Args:
        filepath (str): Path to the annotation file.

    Returns:
        set: A set of (caller, callee) tuples.
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


def build_base_call_graph_from_cgraph(cgraph_dir, ignore_set, is_debug_mode):
    """
    Builds the base call graph from cgraph files in a single pass.

    Args:
        cgraph_dir (str): Directory containing .cgraph files.
        ignore_set (set): A set of (caller, callee) pairs to ignore.
        is_debug_mode (bool): Flag to enable debug output.

    Returns:
        tuple: (call_graph, unresolved_report, cgraph_files_found)
    """
    if not cgraph_dir or not os.path.isdir(cgraph_dir):
        print(f"Error: cgraph directory not found or not specified: {cgraph_dir}")
        return None, None, False

    symbol_map = {}
    temp_call_relations = defaultdict(list)
    current_caller_name_in_file = None
    cgraph_files_found = False
    file_count = 0

    debug_print(f"  DBG: Starting single-pass cgraph processing in: {cgraph_dir}", is_debug_mode)

    for dirpath, _, filenames in os.walk(cgraph_dir):
        for filename in filenames:
            if ".cgraph" not in filename and ".ipa" not in filename:
                continue

            cgraph_files_found = True
            file_count += 1
            filepath = os.path.join(dirpath, filename)
            
            debug_print(f"    -> Processing cgraph file ({file_count}): {filepath}", is_debug_mode)

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

    if not cgraph_files_found:
        msg = (f"{COLOR_BRIGHT_YELLOW}[Warning] No .cgraph or .ipa files found in '{cgraph_dir}'.\n"
               f"   To generate them, the project must be built with the '-fdump-ipa-cgraph' compiler option.{COLOR_RESET}")
        g_deferred_warnings.append(msg)
    
    debug_print(f"  DBG: Processed a total of {file_count} cgraph/ipa files.", is_debug_mode)
    debug_print(f"  DBG: Symbol map built with {len(symbol_map)} entries.", is_debug_mode)
    debug_print(f"  DBG: Found call relations for {len(temp_call_relations)} functions.", is_debug_mode)

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
    return call_graph, unresolved_report, cgraph_files_found


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
    """Finds the worst-case stack path from a start function using DFS."""
    memo = {}
    scenario_additions = scenario_additions or {}

    def get_callees(func):
        base_callees = call_graph.get(func, [])
        added_callees = scenario_additions.get(func, [])
        return list(dict.fromkeys(base_callees + added_callees))

    def dfs(func, visited_path):
        if func in visited_path:
            recursion_path = visited_path[visited_path.index(func):] + [func]
            return (float('inf'), recursion_path)
        if func in memo:
            return memo[func]

        path_with_current = visited_path + [func]
        max_stack_from_callees, worst_callee_path = 0, []

        for callee in get_callees(func):
            stack, path_suffix = dfs(callee, path_with_current)
            if stack > max_stack_from_callees:
                max_stack_from_callees = stack
                worst_callee_path = path_suffix

        current_stack = stack_usage.get(func, stack_usage.get(func.split('.')[0], 0))
        total_stack = current_stack + max_stack_from_callees
        final_path = [func] + worst_callee_path

        if total_stack != float('inf'):
            memo[func] = (total_stack, final_path)
        return total_stack, final_path

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
    parser.add_argument('--su-dir', required=True, help="Directory containing .su files.")
    parser.add_argument('--cgraph-dir', required=True, help="Directory containing .cgraph files.")
    parser.add_argument('--start-func', default='main', help="Comma-separated list of entry points (e.g., main,task1).")
    parser.add_argument('--vector-table', help="Symbol name of the vector table (e.g., g_pfnVectors).")
    parser.add_argument('--ignore-calls', help="File with 'caller,callee' pairs to ignore.")
    parser.add_argument('--add-calls', nargs='+', help="One or more annotation files for callback scenarios.")
    parser.add_argument('--debug', action='store_true', help="Enable detailed debug printing.")
    args = parser.parse_args()

    debug_print("DEBUG MODE ENABLED", args.debug)

    # 1. Parse Stack Usage (.su) files
    print("1. Parsing .su files (recursively)...")
    stack_usage = parse_su_files(args.su_dir, args.debug)

    if not stack_usage:
        print(f"{COLOR_RED}[Error] No stack usage (.su) files found in '{args.su_dir}'.")
        print(f"   Please ensure the project is built with the '-fstack-usage' compiler option.{COLOR_RESET}")
        exit(1)
    print(f"   Found stack usage for {len(stack_usage)} functions.")

    # 2. Build Call Graph (.cgraph) files
    print("\n2. Building base call graph from cgraph files...")
    ignore_set = load_annotation_file(args.ignore_calls)
    base_call_graph, _, cgraph_found = build_base_call_graph_from_cgraph(args.cgraph_dir, ignore_set, args.debug)

    if not cgraph_found:
        msg = (f"{COLOR_BRIGHT_YELLOW}[Warning] No .cgraph or .ipa files found in '{args.cgraph_dir}'.\n"
               f"   To generate them, the project must be built with the '-fdump-ipa-cgraph' compiler option.{COLOR_RESET}")
        g_deferred_warnings.append(msg)

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
    
    # "Uncalled Functions" analysis only runs in debug mode.
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
