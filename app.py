"""CLI: natural-language access to the GB Carbon Intensity API via Bedrock (Claude)."""

from __future__ import annotations

import argparse
import sys

from dotenv import load_dotenv

from carbon_intensity.agent import run_agent


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    p = argparse.ArgumentParser(
        description=(
            "Ask questions about GB electricity carbon intensity; "
            "Claude plans API calls and answers in natural language."
        )
    )
    p.add_argument(
        "message",
        nargs="*",
        help="Question (optional; omit to use interactive mode)",
    )
    p.add_argument(
        "-m",
        "--model",
        default=None,
        help="Override BEDROCK_MODEL_ID (default: set in code/env)",
    )
    args = p.parse_args(argv)

    if args.message:
        text = " ".join(args.message).strip()
        if not text:
            p.print_help()
            return 2
        try:
            print(run_agent(text, model=args.model))
        except OSError as e:
            print(e, file=sys.stderr)
            return 1
        return 0

    print("Carbon intensity agent (Bedrock Claude). Commands: quit, exit, Ctrl+D")
    while True:
        try:
            line = input("> ").strip()
        except EOFError, KeyboardInterrupt:
            print()
            return 0
        if not line:
            continue
        if line.lower() in ("quit", "exit", "q"):
            return 0
        try:
            print(run_agent(line, model=args.model))
            print()
        except OSError as e:
            print(e, file=sys.stderr)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
