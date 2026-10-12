#!/usr/bin/env python3
"""Run viewport shape editing checks in an isolated Godot editor project."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from check_editor_startup import make_project

OBSERVER = '''@tool
extends EditorPlugin
var started := false
func _process(_delta: float) -> void:
	if started or EditorInterface.get_resource_filesystem().is_scanning():
		return
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null or not scene.has_node("Route/__WidthHandles/Handle_001"):
		return
	var plugin := _find_plugin(get_tree().root)
	if plugin == null:
		return
	started = true
	_run.call_deferred(plugin)
func _run(plugin: EditorPlugin) -> void:
	await preload("res://addons/roda-gen/tests/check_road_shape_editor.gd").new().run(plugin)
func _find_plugin(node: Node) -> EditorPlugin:
	if node is EditorPlugin and node.get_script() == load("res://addons/roda-gen/editor/roda_editor_plugin.gd"):
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--graphical', action='store_true', help='Use Forward+ and capture the editor viewport')
    parser.add_argument('--sections', action='store_true', help='Exercise click-to-edit road sections instead of point handles')
    parser.add_argument('--curve-checks', action='store_true', help='Exercise curve-width diagnostics and editor overlays')
    args = parser.parse_args()
    addon = Path(__file__).resolve().parents[1]
    directory = Path(tempfile.mkdtemp(prefix='roda-shape-editor-'))
    project = make_project(directory, addon, None)
    shutil.copytree(addon / 'presets', project / 'addons/roda-gen/presets')
    scene = (addon / 'scenes/road_editing_demo.tscn').read_text().replace(
        '../scripts/', 'res://addons/roda-gen/scripts/').replace(
        'lane_profile_enabled = true', 'lane_profile_enabled = false')
    (project / 'fixture.tscn').write_text(scene)
    observer = OBSERVER.replace('check_road_shape_editor.gd', 'check_road_sections_editor.gd') if args.sections else OBSERVER
    if args.curve_checks:
        observer = OBSERVER.replace('check_road_shape_editor.gd', 'check_road_curve_width_editor.gd')
    (project / 'addons/observer/observer.gd').write_text(observer)
    env = os.environ.copy()
    for variable in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
        location = directory / variable.lower()
        location.mkdir()
        env[variable] = str(location)
    log_path = directory / 'editor.log'
    with log_path.open('w') as log:
        try:
            display = ['--rendering-method', 'forward_plus', '--resolution', '1280x900'] if args.graphical else ['--headless']
            result = subprocess.run([args.godot, *display, '--editor', '--audio-driver', 'Dummy',
                                     '--path', str(project), 'res://fixture.tscn'], env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=90, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = -1
    output = log_path.read_text(errors='replace')
    marker = 'ROAD SECTIONS EDITOR' if args.sections else 'ROAD SHAPE EDITOR'
    if args.curve_checks:
        marker = 'ROAD CURVE WIDTH EDITOR'
    if code != 0 or marker + ' PASS' not in output or 'SCRIPT ERROR:' in output:
        print(output[-12000:])
        print(f'FAIL: retained project/log at {directory}')
        return 1
    if (project / 'fixture.tscn').read_text() != scene:
        print(f'FAIL: fixture scene was saved at {directory}')
        return 1
    print('\n'.join(line for line in output.splitlines() if marker in line))
    shutil.rmtree(directory)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
