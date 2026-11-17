#!/usr/bin/env python3
"""Validated task-count parameters shared by builds and experiment runners."""
import argparse
import json


def task_config(tasks: int) -> dict[str, int]:
    """Keep 256 counters, pad context banks, and reserve 4 KiB stack per task.

    The scheduler runs under its own predictor context (ID = tasks), so the
    hardware provides tasks + 1 contexts.
    """
    if not isinstance(tasks, int) or isinstance(tasks, bool) or not 1 <= tasks <= 255:
        raise ValueError("tasks must be an integer from 1 through 255")
    contexts = tasks + 1
    banks = 1 << (contexts - 1).bit_length()
    required_ram = max(131072, 8192 * tasks + 65536)
    ram_bytes = 1 << (required_ram - 1).bit_length()
    return {"tasks": tasks, "contexts": contexts, "ram_bytes": ram_bytes, "banks": banks,
            "entries_per_task": 256 // banks}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tasks", type=int, default=2)
    parser.add_argument("--field", choices=("tasks", "contexts", "ram_bytes", "banks", "entries_per_task"))
    args = parser.parse_args()
    try:
        config = task_config(args.tasks)
    except ValueError as error:
        parser.error(str(error))
    print(config[args.field] if args.field else json.dumps(config, sort_keys=True))


if __name__ == "__main__":
    main()
