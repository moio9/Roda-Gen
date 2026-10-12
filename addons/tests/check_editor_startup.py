#!/usr/bin/env python3
"""Exercise real editor startup without using the checkout's scene/import cache.

Run with --godot /path/to/godot. --plugin-source can replace just the plugin
in the temporary project, for example to verify that an older revision fails.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


PROJECT = '''config_version=5

[application]
config/name="Roda Editor Startup Regression"

[rendering]
renderer/rendering_method="gl_compatibility"

[editor_plugins]
enabled=PackedStringArray("res://addons/roda-gen/plugin.cfg", "res://addons/observer/plugin.cfg")
'''

SCENE = '''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://addons/roda-gen/scripts/spline_road/spline_prop_array.gd" id="1_props"]

[sub_resource type="Curve3D" id="Curve_path"]
_data = {
"points": PackedVector3Array(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -20),
"tilts": PackedFloat32Array(0, 0)
}
point_count = 2

[sub_resource type="BoxMesh" id="Mesh_prop"]
size = Vector3(0.2, 1, 2)

[node name="StartupFixture" type="Node3D"]

[node name="Path" type="Path3D" parent="."]
curve = SubResource("Curve_path")

[node name="SplinePropArray3D" type="Node3D" parent="."]
script = ExtResource("1_props")
source_paths = Array[NodePath]([NodePath("../Path")])
item_mesh = SubResource("Mesh_prop")
fit_segments_to_path = true
placement_mode = 1
spacing = 2.0
avoid_intersections = false
'''

OBSERVER = '''@tool
extends EditorPlugin

var _ready_at := 0
var _signature := ""

func _process(_delta: float) -> void:
\tif "--roda-prop-span-tests" in OS.get_cmdline_user_args():
\t\tset_process(false)
\t\treturn
\tif EditorInterface.get_resource_filesystem().is_scanning():
\t\treturn
\tvar scene := EditorInterface.get_edited_scene_root()
\tif scene == null or not scene.is_node_ready():
\t\treturn
\tvar props := scene.get_node_or_null("SplinePropArray3D")
\tif props == null or not props.has_node("PropSpan/EndHandle") or not props.has_node("GeneratedSplineProps"):
\t\treturn
\tvar span := props.get_node("PropSpan")
\tif not is_equal_approx(span.start_offset, 0.0) or not is_equal_approx(span.end_offset, 20.0):
\t\t_fail("Authored range changed during ordinary editor startup")
\t\treturn
\tif props.get_node("GeneratedSplineProps").get_child_count() != 10:
\t\t_fail("Expected all ten props to remain generated")
\t\treturn
\tvar current_signature: String = props._build_signature()
\tif _ready_at == 0:
\t\t_ready_at = Time.get_ticks_msec()
\t\t_signature = current_signature
\t\tprint("EDITOR STARTUP READY")
\telif current_signature != _signature:
\t\t_fail("Prop inputs changed after startup completed")
\t\treturn
\tif Time.get_ticks_msec() - _ready_at >= 3000:
\t\tprint("EDITOR STARTUP PASS stable_ms=%d" % (Time.get_ticks_msec() - _ready_at))
\t\tset_process(false)
\t\tget_tree().quit(0)

func _fail(message: String) -> void:
\tpush_error("EDITOR STARTUP FAIL: " + message)
\tset_process(false)
\tget_tree().quit(1)
'''


def make_project(directory: Path, addon: Path, plugin_source: Path | None) -> Path:
    project = directory / "project"
    copied_addon = project / "addons" / "roda-gen"
    copied_addon.mkdir(parents=True)
    for folder in ("scripts", "editor", "tests"):
        shutil.copytree(addon / folder, copied_addon / folder,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copy2(addon / "plugin.cfg", copied_addon / "plugin.cfg")
    if plugin_source:
        shutil.copy2(plugin_source, copied_addon / "editor" / "roda_editor_plugin.gd")
    observer = project / "addons" / "observer"
    observer.mkdir()
    (observer / "plugin.cfg").write_text(
        '[plugin]\nname="Startup Observer"\ndescription="Regression observer"\n'
        'author="Roda-Gen"\nversion="1"\nscript="observer.gd"\n')
    (observer / "observer.gd").write_text(OBSERVER)
    (project / "project.godot").write_text(PROJECT)
    (project / "fixture.tscn").write_text(SCENE)
    return project


def run_case(godot: str, addon: Path, plugin_source: Path | None,
             name: str, flags: list[str]) -> bool:
    # Retain failures for inspection. Successful runs leave no generated files.
    directory = Path(tempfile.mkdtemp(prefix=f"roda-editor-startup-{name}-"))
    project = make_project(directory, addon, plugin_source)
    env = os.environ.copy()
    for variable in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        location = directory / variable.lower()
        location.mkdir()
        env[variable] = str(location)
    command = [godot, "--headless", "--editor", "--audio-driver", "Dummy",
               "--path", str(project), "res://fixture.tscn"]
    if flags:
        command += ["--", *flags]
    log_path = directory / "editor.log"
    timed_out = False
    with log_path.open("w") as log:
        try:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=90, check=False)
            returncode = result.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            returncode = -1
    output = log_path.read_text(errors="replace")
    explicit = "--roda-prop-span-tests" in flags
    expected = "PROP SPAN EDITOR PASS" if explicit else "EDITOR STARTUP PASS"
    errors = []
    if timed_out:
        errors.append("editor did not finish within 90 seconds")
    elif returncode != 0:
        errors.append(f"editor exited with status {returncode}")
    if expected not in output:
        errors.append(f"missing {expected!r}")
    if not explicit and "PROP SPAN EDITOR" in output:
        errors.append("prop tests ran without their explicit command-line flag")
    if "SCRIPT ERROR:" in output:
        errors.append("script error in editor log")
    if (project / "fixture.tscn").read_text() != SCENE:
        errors.append("editor changed the scene file")
    if errors:
        print(f"FAIL {name}: {'; '.join(errors)}", file=sys.stderr)
        print(f"Full log and isolated project: {directory}", file=sys.stderr)
        print("\n".join(output.splitlines()[-70:]), file=sys.stderr)
        return False
    print(f"PASS {name}: {expected}")
    shutil.rmtree(directory)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot editor executable")
    parser.add_argument("--plugin-source", type=Path,
                        help="Optional plugin revision to copy into the isolated project")
    args = parser.parse_args()
    godot = shutil.which(args.godot)
    if godot is None:
        parser.error(f"Godot executable not found: {args.godot}")
    if args.plugin_source and not args.plugin_source.is_file():
        parser.error(f"Plugin source not found: {args.plugin_source}")
    addon = Path(__file__).resolve().parents[1]
    for name, flags in (("ordinary", []),
                        ("unrelated-flag", ["--roda-unrelated-startup-option"]),
                        ("explicit-prop-test", ["--roda-prop-span-tests"])):
        if not run_case(godot, addon, args.plugin_source, name, flags):
            return 1
    print("EDITOR STARTUP REGRESSION PASS cases=3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
