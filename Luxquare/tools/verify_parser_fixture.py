"""Ensure the Swift protocol test actually exercises the shipping parser text."""
from pathlib import Path

source = Path("Sources/Luxquare/DialogueStore.swift").read_text(encoding="utf-8")
fixture = Path("Tests/DialogueSSEParserChecks.swift").read_text(encoding="utf-8")
shipping = source.split("struct DialogueSSEParser {", 1)[1].split("@MainActor", 1)[0].strip()
tested = fixture.split("struct DialogueSSEParser {", 1)[1].split("var passed=0", 1)[0].strip()
if shipping != tested:
    raise SystemExit("The protocol fixture differs from the shipping parser")
print("Protocol fixture exactly matches the shipping parser")
