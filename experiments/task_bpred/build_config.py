#!/usr/bin/env python3
"""Validated task-count parameters shared by builds and experiment runners."""
import argparse
import json


def task_config(tasks: int) -> dict[str, int]:
    """Keep 256 counters, pad task banks, and reserve 4 KiB stack per task."""
    if not isinstance(tasks, int) or isinstance(tasks, bool) or not 1 <= tasks <= 256:
        raise ValueError("tasks must be an integer from 1 through 256")
    banks = 1 << (tasks - 1).bit_length()
    required_ram = max(65536, 4096 * tasks + 32768)
    ram_bytes = 1 << (required_ram - 1).bit_length()
    return {"tasks": tasks, "ram_bytes": ram_bytes, "banks": banks,
            "entries_per_task": 256 // banks}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tasks", type=int, default=2)
    parser.add_argument("--field", choices=("tasks", "ram_bytes", "banks", "entries_per_task"))
    args = parser.parse_args()
    try:
        config = task_config(args.tasks)
    except ValueError as error:
        parser.error(str(error))
    print(config[args.field] if args.field else json.dumps(config, sort_keys=True))


if __name__ == "__main__":
    main()
