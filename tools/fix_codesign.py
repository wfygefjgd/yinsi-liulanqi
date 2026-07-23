from pathlib import Path

p = Path("ios/Runner.xcodeproj/project.pbxproj")
lines = p.read_text(encoding="utf-8").splitlines(True)
out = []
for line in lines:
    if (
        "PRODUCT_BUNDLE_IDENTIFIER = com.tongyong.browser;" in line
        and "RunnerTests" not in line
    ):
        prev = "".join(out[-10:])
        if "CODE_SIGNING_ALLOWED" not in prev:
            indent = line[: len(line) - len(line.lstrip())]
            out.append(f'{indent}CODE_SIGN_IDENTITY = "";\n')
            out.append(f"{indent}CODE_SIGNING_ALLOWED = NO;\n")
            out.append(f"{indent}CODE_SIGNING_REQUIRED = NO;\n")
            out.append(f'{indent}DEVELOPMENT_TEAM = "";\n')
    out.append(line)
p.write_text("".join(out), encoding="utf-8")
print("CODE_SIGNING_ALLOWED count:", "".join(out).count("CODE_SIGNING_ALLOWED"))
