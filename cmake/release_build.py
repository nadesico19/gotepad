"""Private build-script helpers; application versions come from Godot files."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile


ROOT = Path(sys.argv[1]).resolve()
PROJECT = ROOT / "gotepad-gd"
CERTIFICATE = "128F7F8D6CAE7B5EDBF05EBD6A9E7AD50914001BC2B04ED75A0121A81A007F31"


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def section(text, name):
    match = re.search(r"^\[" + re.escape(name) + r"\]\s*\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    require(match is not None, "Missing configuration section: " + name)
    return match


def value(text, name, key):
    body = section(text, name).group(1)
    match = re.search(r"^" + re.escape(key) + r"\s*=\s*(.*?)\s*$", body, re.M)
    require(match is not None, "Missing configuration key: " + key)
    raw = match.group(1)
    return json.loads(raw) if raw.startswith('"') else raw


def update(text, name, values):
    match = section(text, name)
    body = match.group(1)
    for key, setting in values.items():
        line = key + "=" + setting
        pattern = r"^" + re.escape(key) + r"\s*=.*$"
        if re.search(pattern, body, re.M):
            body = re.sub(pattern, lambda _: line, body, flags=re.M)
        else:
            body += line + "\n"
    return text[:match.start(1)] + body + text[match.end(1):]


def config(platform):
    presets = (PROJECT / "export_presets.cfg").read_text(encoding="utf-8")
    platform_name = {"macos": "macOS", "ios": "iOS", "android": "Android"}[platform]
    matches = [name for name in re.findall(r"^\[(preset\.\d+)\]", presets, re.M)
               if value(presets, name, "platform") == platform_name]
    require(len(matches) == 1, "Expected one export preset for " + platform_name)
    return presets, matches[0]


def software_version():
    version = value((PROJECT / "project.godot").read_text(encoding="utf-8"), "application", "config/version")
    require(re.fullmatch(r"(?:test/)?\d+\.\d+\.\d+", version), "Invalid project.godot version: " + version)
    return version


def android_secrets():
    path = ROOT / "docs/local_build_secrets.md"
    require(path.is_file(), "Missing local Android signing information: " + str(path))
    fields = re.findall(r"^\s*-\s*[^:：\n]+[:：]\s*(.*)$", path.read_text(encoding="utf-8"), re.M)
    fields = [field.strip().strip('`').strip('"') for field in fields]
    require(len(fields) >= 5, "Local Android signing information is incomplete.")
    keystore = (ROOT / fields[0].replace("\\", "/")).resolve()
    require(keystore == ROOT / "gotepad-model-test.keystore" and keystore.is_file(),
            "Android releases require the fixed project keystore gotepad-model-test.keystore.")
    require(fields[2] == "gotepad-model-test", "Unexpected Android keystore alias.")
    require(fields[4].replace(":", "").upper() == CERTIFICATE, "Unexpected Android certificate in local signing information.")
    password = os.environ.get("GOTEPAD_ANDROID_KEYSTORE_PASSWORD") or fields[3]
    require(password and "\n" not in password and "\r" not in password, "Invalid Android signing password.")
    return str(keystore), fields[2], password


def validate(platform):
    presets, name = config(platform)
    version = software_version()
    print("Software version: " + version)
    if platform != "android":
        return
    options = name + ".options"
    package_version = value(presets, options, "version/name")
    code = value(presets, options, "version/code")
    package = value(presets, options, "package/unique_name")
    require(re.fullmatch(r"\d+\.\d+\.\d+", package_version), "Invalid Android package version.")
    require(re.fullmatch(r"[1-9]\d*", code), "Android version/code must be a positive integer.")
    require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", package), "Invalid Android package name.")
    if version.startswith("test/"):
        require(tuple(map(int, version[5:].split("."))) > tuple(map(int, package_version.split("."))),
                "Test software must be newer than the Android package version, as in build_android_release.ps1.")
        print("Warning: test-channel software; do not publish this APK as a formal release.")
    else:
        require(version == package_version, "project.godot and Android package versions do not match.")
    print("Android package version: {} ({})".format(package_version, code))
    android_secrets()


def stage(platform, target, host_arch, template=""):
    presets, name = config(platform)
    options = name + ".options"
    version = software_version().split("/")[-1]
    ignored = {".godot", "android", "bin", ".tmp", ".DS_Store"}
    shutil.copytree(PROJECT, target, ignore=lambda directory, names: [n for n in names if n in ignored])
    binary_dir = target / "bin"
    binary_dir.mkdir()
    host = "libgo_gdext.macos.template_debug.{}.dylib".format(host_arch)
    release = "libgo_gdext.{}.template_release.arm64.{}".format(platform, "so" if platform == "android" else "dylib")
    for library in (host, release):
        shutil.copy2(PROJECT / "bin" / library, binary_dir / library)
    release_name = {"macos": "macOS Release", "ios": "iOS Release", "android": "Android Release"}[platform]
    presets = update(presets, name, {"name": json.dumps(release_name)})
    settings = {}
    if platform in ("macos", "ios"):
        settings = {"application/short_version": json.dumps(version), "application/version": json.dumps(version)}
    if platform == "macos":
        settings.update({"custom_template/debug": '""', "custom_template/release": json.dumps(template),
                         "binary_format/architecture": '"arm64"'})
    elif platform == "ios":
        settings.update({"application/export_project_only": "true"})
    else:
        keystore, alias, password = android_secrets()
        settings.update({"keystore/release": json.dumps(keystore), "keystore/release_user": json.dumps(alias),
                         "keystore/release_password": json.dumps(password),
                         "gradle_build/use_gradle_build": "true", "gradle_build/export_format": "0",
                         "gradle_build/compress_native_libraries": "false"})
        for abi in ("armeabi-v7a", "arm64-v8a", "x86", "x86_64"):
            settings["architectures/" + abi] = "true" if abi == "arm64-v8a" else "false"
    preset_path = target / "export_presets.cfg"
    preset_path.write_text(update(presets, options, settings), encoding="utf-8")
    preset_path.chmod(0o600)


def configure_android_sdk():
    settings = Path.home() / "Library/Application Support/Godot/editor_settings-4.7.tres"
    require(settings.is_file(), "Godot editor settings are missing; import the staged project first.")
    original = settings.read_text(encoding="utf-8")
    require('type="EditorSettings"' in original, "Unexpected Godot editor settings resource.")
    updated = update(original, "resource", {
        "export/android/java_sdk_path": json.dumps(os.environ["JAVA_HOME"]),
        "export/android/android_sdk_path": json.dumps(os.environ["ANDROID_HOME"]),
    })
    if updated != original:
        backup = ROOT / ".tmp/android/editor-settings-before-release.tres"
        if not backup.exists():
            shutil.copy2(settings, backup)
        settings.write_text(updated, encoding="utf-8")
    print("Godot Android SDK paths configured.")


def android_template(target, build_directory, template_root=None):
    template_root = template_root or PROJECT / "android"
    source = template_root / "build"
    require((source / "build.gradle").is_file(), "Install the Godot Android build template first.")

    def ignore(directory, names):
        skipped = {".gradle", ".godot", ".cxx", "local.properties", ".DS_Store"}
        # Copy template AARs, but never stale native libraries, assets, or build products.
        return [n for n in names if n in skipped or n.endswith(".so")
                or (n == "build" and Path(directory) == source)
                or (n == "assets" and Path(directory).name == "main")
                or n in {"KataGoNpuBridge.java", "KataGoNpuService.java", "gdextensionlibs.json"}]

    destination = target / "android/build"
    shutil.copytree(source, destination, ignore=ignore)
    wrapper = destination / "gradlew"
    require(wrapper.is_file(), "Android template is missing the Gradle wrapper.")
    wrapper.chmod(wrapper.stat().st_mode | 0o111)
    shutil.copy2(template_root / ".build_version", target / "android/.build_version")
    (target / "android/.gdignore").touch()
    java_dir = destination / "src/main/java/com/godot/game"
    java_dir.mkdir(parents=True, exist_ok=True)
    canonical = PROJECT / "platform/android"
    for filename in ("GodotApp.java", "KataGoOpenCLBridge.java", "KataGoOpenCLProtocol.java", "KataGoOpenCLService.java"):
        shutil.copy2(canonical / filename, java_dir / filename)
    manifest = (canonical / "AndroidManifest.xml").read_text(encoding="utf-8")
    presets, name = config("android")
    # Do not inherit the version literals in the Java host manifest.
    for attribute, key in (("versionCode", "version/code"), ("versionName", "version/name")):
        manifest = re.sub(r'android:' + attribute + r'="[^"]*"',
                          'android:' + attribute + '="' + value(presets, name + ".options", key) + '"', manifest)
    (destination / "src/main/AndroidManifest.xml").write_text(manifest, encoding="utf-8")
    xml_dir = destination / "src/main/res/xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(canonical / "godot_provider_paths.xml", xml_dir)
    libraries = destination / "libs/release/arm64-v8a"
    libraries.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build_directory / "android-opencl-output/libkatago_opencl_android.so", libraries)


def verify_apk(apk, build_directory):
    sdk_tools = Path(os.environ["ANDROID_BUILD_TOOLS"])
    java = Path(os.environ["JAVA_HOME"]) / "bin/java"
    result = subprocess.check_output([str(java), "-jar", str(sdk_tools / "lib/apksigner.jar"),
                                      "verify", "--verbose", "--print-certs", str(apk)], text=True)
    print(result)
    fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", result)
    require(len(fingerprints) == 1 and fingerprints[0].replace(":", "").upper() == CERTIFICATE,
            "APK certificate does not match the fixed project signing key.")
    badging = subprocess.check_output([str(sdk_tools / "aapt2"), "dump", "badging", str(apk)], text=True)
    presets, name = config("android")
    metadata = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    expected = tuple(value(presets, name + ".options", key) for key in ("package/unique_name", "version/code", "version/name"))
    require(metadata and metadata.groups() == expected, "APK package name or version differs from the export preset.")
    require(not re.search(r"^application-debuggable\s*$", badging, re.M), "Release APK is debuggable.")
    require(re.search(r"^native-code:\s+'arm64-v8a'\s*$", badging, re.M), "APK must contain only arm64-v8a.")
    manifest = subprocess.check_output([str(sdk_tools / "aapt2"), "dump", "xmltree", str(apk), "--file", "AndroidManifest.xml"], text=True)
    require("android.intent.action.VIEW" in manifest, "APK is missing the SGF VIEW intent filter.")
    require(not re.search(r"android:debuggable.*(?:0xffffffff|true)", manifest), "Release manifest is debuggable.")
    libraries = {"libgo_gdext.android.template_release.arm64.so": PROJECT / "bin/libgo_gdext.android.template_release.arm64.so",
                 "libkatago_opencl_android.so": build_directory / "android-opencl-output/libkatago_opencl_android.so"}
    with zipfile.ZipFile(apk) as archive:
        for filename, source in libraries.items():
            require(hashlib.sha256(archive.read("lib/arm64-v8a/" + filename)).digest() == hashlib.sha256(source.read_bytes()).digest(),
                    "APK native library does not match the Release output: " + filename)
        require(not any(re.search(r"/(?:libOpenCL|libQnn[^/]*|libonnxruntime[^/]*|libkatago_onnx_qnn_android)\.so$", n)
                        for n in archive.namelist()), "APK contains a link-only OpenCL stub or stale QNN libraries.")


def main():
    command, *args = sys.argv[2:]
    if command == "validate":
        validate(args[0])
    elif command == "value":
        presets, name = config(args[0])
        print(value(presets, name + ".options", args[1]))
    elif command == "stage":
        stage(args[0], Path(args[1]), args[2], args[3] if len(args) > 3 else "")
    elif command == "android-template":
        android_template(Path(args[0]), Path(args[1]), Path(args[2]) if len(args) > 2 else None)
    elif command == "configure-android-sdk":
        configure_android_sdk()
    elif command == "verify-apk":
        verify_apk(Path(args[0]), Path(args[1]))
    elif command == "latest":
        directory = Path(args[0])
        require(directory.is_dir(), "Tool directory is missing: " + str(directory))
        directories = [p for p in directory.iterdir() if p.is_dir() and re.fullmatch(r"\d+(?:\.\d+)*", p.name)]
        require(directories, "No installed tool versions under " + args[0])
        print(max(directories, key=lambda p: tuple(map(int, p.name.split(".")))))
    else:
        raise SystemExit("Unknown release helper command: " + command)


if __name__ == "__main__":
    main()
