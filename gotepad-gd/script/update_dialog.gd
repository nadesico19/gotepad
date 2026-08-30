class_name UpdateDialog
extends Control

signal check_started
signal check_finished

const kReleasesApiUrl: String = \
	"https://api.github.com/repos/nadesico19/gotepad/releases?per_page=100"
const kTagsApiUrl: String = \
	"https://api.github.com/repos/nadesico19/gotepad/tags?per_page=100"
const kCommitsApiUrl: String = \
	"https://api.github.com/repos/nadesico19/gotepad/commits"
const kGithubReleasesUrl: String = \
	"https://github.com/nadesico19/gotepad/releases"
const kCloudDriveUrl: String = \
	"https://pan.baidu.com/s/1kOJOMUFJSAAJP31IaDNR1Q?pwd=kyd8"
const kKnownPlatforms: Array[String] = [
	"windows", "android", "linux", "macos", "ios",
]
const kStrictTagVersion: Array[int] = [0, 1, 11]
const kMaxHistoryVersions: int = 5

enum RequestStage {
	NONE,
	RELEASES,
	TAGS,
	COMMITS,
}

@onready var current_version_label_: Label = \
	$Center/Panel/Margin/Content/Header/CurrentVersion
@onready var latest_version_label_: Label = \
	$Center/Panel/Margin/Content/Header/LatestVersion
@onready var download_source_: OptionButton = \
	$Center/Panel/Margin/Content/Header/DownloadSource
@onready var update_button_: Button = \
	$Center/Panel/Margin/Content/Header/Update
@onready var close_button_: Button = \
	$Center/Panel/Margin/Content/Header/Close
@onready var release_notes_: TextEdit = \
	$Center/Panel/Margin/Content/ReleaseNotes
@onready var http_request_: HTTPRequest = $HTTPRequest

var request_pending_: bool = false
var current_version_: String = "0.0.0"
var current_tag_: String = "0.0.0"
var latest_version_: String = "-"
var request_stage_: RequestStage = RequestStage.NONE
var current_parsed_: Dictionary = {}
var platform_name_: String = ""
var latest_candidate_: Dictionary = {}
var release_by_version_: Dictionary = {}
var history_candidates_: Array = []


func _ready() -> void:
	visible = false
	close_button_.pressed.connect(close)
	update_button_.pressed.connect(open_selected_download_)
	http_request_.request_completed.connect(on_request_completed_)
	refresh_localized_texts()


func check_for_updates() -> void:
	if request_pending_:
		return
	current_version_ = str(ProjectSettings.get_setting(
		"application/config/version", "0.0.0"
	))
	current_tag_ = current_version_
	request_pending_ = true
	request_stage_ = RequestStage.RELEASES
	current_parsed_.clear()
	platform_name_ = current_platform_()
	latest_candidate_.clear()
	release_by_version_.clear()
	history_candidates_.clear()
	check_started.emit()
	request_api_(kReleasesApiUrl)


func close() -> void:
	visible = false


func refresh_localized_texts() -> void:
	current_version_label_.text = tr("当前版本：%s") % current_version_
	latest_version_label_.text = tr("最新版本：%s") % latest_version_
	update_button_.text = tr("更新")
	close_button_.tooltip_text = tr("关闭")
	var selected: int = download_source_.selected
	download_source_.clear()
	download_source_.add_item("GitHub")
	download_source_.add_item(tr("网盘"))
	download_source_.select(clampi(selected, 0, 1))


func on_request_completed_(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not request_pending_:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		finish_with_error_(tr(
			"无法连接 GitHub 更新服务（网络结果 %d，HTTP %d）。"
		) % [result, response_code])
		return
	var parsed_json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed_json is not Array:
		finish_with_error_(tr("GitHub 更新服务返回了无法解析的数据。"))
		return
	match request_stage_:
		RequestStage.RELEASES:
			apply_release_list_(parsed_json as Array)
		RequestStage.TAGS:
			apply_tag_list_(parsed_json as Array)
		RequestStage.COMMITS:
			apply_commit_list_(parsed_json as Array)
		_:
			finish_with_error_(tr("GitHub 更新服务返回了无法解析的数据。"))


func apply_release_list_(releases: Array) -> void:
	var current: Dictionary = parse_tag_(current_tag_, true)
	if not current.valid:
		current = parse_tag_(current_version_, true)
	if not current.valid:
		finish_with_error_(tr("当前版本号“%s”无法解析。") % current_version_)
		return
	current_parsed_ = current
	var platform: String = platform_name_
	var per_version: Dictionary = {}
	var current_release: Dictionary = {}
	for release_variant: Variant in releases:
		if release_variant is not Dictionary:
			continue
		var release: Dictionary = release_variant
		if bool(release.get("draft", false)):
			continue
		var parsed: Dictionary = parse_tag_(str(release.get("tag_name", "")))
		if not parsed.valid or not release_applies_(release, parsed, current, platform):
			continue
		var candidate := {"release": release, "parsed": parsed}
		var release_key: String = version_text_(parsed.parts)
		if not release_by_version_.has(release_key) \
				or prefer_release_(candidate, release_by_version_[release_key], platform):
			release_by_version_[release_key] = candidate
		if release_matches_current_(parsed, current):
			if current_release.is_empty() \
					or prefer_release_(candidate, current_release, platform):
				current_release = candidate
			continue
		if not release_is_newer_(parsed, current):
			continue
		var version_key: String = version_text_(parsed.parts)
		if not per_version.has(version_key) \
				or prefer_release_(candidate, per_version[version_key], platform):
			per_version[version_key] = candidate
	var applicable: Array = per_version.values()
	if applicable.is_empty():
		latest_version_ = current_version_
		release_notes_.text = tr("当前已是最新版本。")
		if not current_release.is_empty():
			release_notes_.text += "\n\n%s" % build_release_notes_([
				current_release,
			])
		refresh_localized_texts()
		finish_success_()
		return
	applicable.sort_custom(Callable(self, "release_before_"))
	var latest: Dictionary = applicable.back()
	latest_candidate_ = latest
	latest_version_ = str(latest.release.get(
		"tag_name", version_text_(latest.parsed.parts)
	))
	request_stage_ = RequestStage.TAGS
	request_api_(kTagsApiUrl)


func apply_tag_list_(tags: Array) -> void:
	var per_version: Dictionary = {}
	for tag_variant: Variant in tags:
		if tag_variant is not Dictionary:
			continue
		var tag: Dictionary = tag_variant
		var tag_name: String = str(tag.get("name", ""))
		var parsed: Dictionary = parse_tag_(tag_name)
		if not parsed.valid or not tag_applies_(parsed):
			continue
		if compare_versions_(parsed.parts, current_parsed_.parts) < 0 \
				or compare_versions_(parsed.parts, latest_candidate_.parsed.parts) > 0:
			continue
		var version_key: String = version_text_(parsed.parts)
		var candidate := {
			"release": release_by_version_.get(version_key, {}),
			"parsed": parsed,
			"sha": tag_commit_sha_(tag),
			"tag_name": tag_name,
		}
		if not per_version.has(version_key) \
				or prefer_history_tag_(candidate, per_version[version_key]):
			per_version[version_key] = candidate
	var latest_key: String = version_text_(latest_candidate_.parsed.parts)
	if not per_version.has(latest_key):
		per_version[latest_key] = {
			"release": latest_candidate_,
			"parsed": latest_candidate_.parsed,
			"sha": "",
			"tag_name": str(latest_candidate_.release.get("tag_name", latest_key)),
		}
	var candidates: Array = per_version.values()
	candidates.sort_custom(Callable(self, "release_before_"))
	history_candidates_.clear()
	var first_index: int = maxi(0, candidates.size() - kMaxHistoryVersions)
	for index: int in range(first_index, candidates.size()):
		history_candidates_.append(candidates[index])
	history_candidates_.reverse()
	if not history_needs_commit_messages_():
		finish_history_({})
		return
	request_stage_ = RequestStage.COMMITS
	var latest_tag: String = str(latest_candidate_.release.get("tag_name", ""))
	request_api_("%s?sha=%s&per_page=100" % [
		kCommitsApiUrl, latest_tag.uri_encode(),
	])


func apply_commit_list_(commits: Array) -> void:
	var messages_by_sha: Dictionary = {}
	for commit_variant: Variant in commits:
		if commit_variant is not Dictionary:
			continue
		var commit: Dictionary = commit_variant
		var sha: String = str(commit.get("sha", ""))
		var commit_data: Variant = commit.get("commit", {})
		if sha.is_empty() or commit_data is not Dictionary:
			continue
		messages_by_sha[sha] = str((commit_data as Dictionary).get("message", ""))
	finish_history_(messages_by_sha)


func finish_history_(messages_by_sha: Dictionary) -> void:
	var releases: Array = []
	for candidate: Dictionary in history_candidates_:
		var release_candidate: Dictionary = candidate.release
		var release: Dictionary = release_candidate.get("release", {}).duplicate()
		var notes: String = str(release.get("body", "")).strip_edges()
		var uses_tag_notes: bool = false
		if notes.is_empty():
			notes = str(messages_by_sha.get(candidate.sha, "")).strip_edges()
			uses_tag_notes = not notes.is_empty()
		if release.is_empty():
			release = {
				"tag_name": candidate.tag_name,
				"name": "",
			}
		release["body"] = notes
		releases.append({
			"release": release,
			"parsed": candidate.parsed,
			"hide_header": uses_tag_notes,
		})
	release_notes_.text = build_release_notes_(releases)
	finish_success_()


func request_api_(url: String) -> void:
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2026-03-10",
		"User-Agent: Gotepad-Update-Checker",
	])
	var error: Error = http_request_.request(url, headers)
	if error != OK:
		finish_with_error_(tr("无法启动更新检测（错误 %d）。") % error)


func tag_applies_(parsed: Dictionary) -> bool:
	if not parsed.platform.is_empty() and parsed.platform != platform_name_:
		return false
	return bool(current_parsed_.test) or not bool(parsed.test)


func tag_commit_sha_(tag: Dictionary) -> String:
	var commit: Variant = tag.get("commit", {})
	if commit is not Dictionary:
		return ""
	return str((commit as Dictionary).get("sha", ""))


func prefer_history_tag_(candidate: Dictionary, existing: Dictionary) -> bool:
	if bool(candidate.parsed.test) != bool(existing.parsed.test):
		return not bool(candidate.parsed.test)
	var candidate_specific: bool = candidate.parsed.platform == platform_name_
	var existing_specific: bool = existing.parsed.platform == platform_name_
	return candidate_specific and not existing_specific


func history_needs_commit_messages_() -> bool:
	for candidate: Dictionary in history_candidates_:
		var release_candidate: Dictionary = candidate.release
		var release: Dictionary = release_candidate.get("release", {})
		if str(release.get("body", "")).strip_edges().is_empty():
			return true
	return false


func finish_success_() -> void:
	request_pending_ = false
	request_stage_ = RequestStage.NONE
	refresh_localized_texts()
	check_finished.emit()
	show_dialog_()


func release_applies_(
	release: Dictionary,
	parsed: Dictionary,
	current: Dictionary,
	platform: String
) -> bool:
	if not parsed.platform.is_empty() and parsed.platform != platform:
		return false
	if not current.test and parsed.test:
		return false
	var prerelease: bool = bool(release.get("prerelease", false))
	if compare_versions_(parsed.parts, kStrictTagVersion) >= 0:
		if prerelease != bool(parsed.test):
			return false
	elif not current.test and prerelease:
		return false
	return true


func release_is_newer_(remote: Dictionary, current: Dictionary) -> bool:
	var comparison: int = compare_versions_(remote.parts, current.parts)
	if comparison != 0:
		return comparison > 0
	return bool(current.test) and not bool(remote.test)


func release_matches_current_(remote: Dictionary, current: Dictionary) -> bool:
	return compare_versions_(remote.parts, current.parts) == 0 \
		and bool(remote.test) == bool(current.test)


func prefer_release_(candidate: Dictionary, existing: Dictionary, platform: String) -> bool:
	if bool(candidate.parsed.test) != bool(existing.parsed.test):
		return not bool(candidate.parsed.test)
	var candidate_specific: bool = candidate.parsed.platform == platform
	var existing_specific: bool = existing.parsed.platform == platform
	return candidate_specific and not existing_specific


func release_before_(left: Dictionary, right: Dictionary) -> bool:
	return compare_versions_(left.parsed.parts, right.parsed.parts) < 0


func build_release_notes_(releases: Array) -> String:
	var sections: PackedStringArray = []
	for item: Dictionary in releases:
		var release: Dictionary = item.release
		var notes: String = str(release.get("body", "")).replace("\r\n", "\n")
		notes = notes.strip_edges()
		if notes.is_empty():
			notes = tr("该版本未提供更新说明。")
		if bool(item.get("hide_header", false)):
			sections.append(notes)
			continue
		var tag: String = str(release.get("tag_name", ""))
		var title: String = str(release.get("name", "")).strip_edges()
		if title.is_empty() or title == tag:
			title = tr("版本 %s") % tag
		else:
			title = "%s (%s)" % [title, tag]
		sections.append("%s\n%s" % [title, notes])
	return "\n\n".join(sections)


func parse_tag_(tag: String, local_version: bool = false) -> Dictionary:
	var result := {
		"valid": false,
		"test": false,
		"platform": "",
		"parts": [0, 0, 0],
	}
	var segments: PackedStringArray = tag.strip_edges().split("/", false)
	if segments.is_empty():
		return result
	if segments[0].to_lower() == "test":
		result.test = true
		segments.remove_at(0)
	if segments.size() == 2 and kKnownPlatforms.has(segments[0].to_lower()):
		result.platform = segments[0].to_lower()
		segments.remove_at(0)
	if segments.size() != 1:
		return result
	var strict_regex := RegEx.new()
	strict_regex.compile("^(\\d+)\\.(\\d+)\\.(\\d+)$")
	var legacy_regex := RegEx.new()
	legacy_regex.compile("^(\\d+)\\.(\\d+)\\.(\\d+)(-.+)?$")
	var version_part: String = segments[0]
	var match: RegExMatch = legacy_regex.search(version_part)
	if match == null:
		return result
	var parts: Array[int] = [
		int(match.get_string(1)),
		int(match.get_string(2)),
		int(match.get_string(3)),
	]
	var strict: bool = strict_regex.search(version_part) != null
	if compare_versions_(parts, kStrictTagVersion) >= 0 and not strict:
		return result
	if not strict and (local_version or not result.test):
		result.test = true
	result.parts = parts
	result.valid = true
	return result


func compare_versions_(left: Array, right: Array) -> int:
	for index: int in 3:
		if int(left[index]) < int(right[index]):
			return -1
		if int(left[index]) > int(right[index]):
			return 1
	return 0


func version_text_(parts: Array) -> String:
	return "%d.%d.%d" % [parts[0], parts[1], parts[2]]


func current_platform_() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"Android":
			return "android"
		"macOS":
			return "macos"
		"iOS":
			return "ios"
		_:
			return "linux"


func finish_with_error_(message: String) -> void:
	request_pending_ = false
	latest_version_ = tr("无法获取")
	release_notes_.text = message
	refresh_localized_texts()
	check_finished.emit()
	show_dialog_()


func show_dialog_() -> void:
	visible = true
	move_to_front()
	close_button_.grab_focus()


func open_selected_download_() -> void:
	var url: String = kGithubReleasesUrl \
		if download_source_.selected == 0 else kCloudDriveUrl
	var error: Error = OS.shell_open(url)
	if error != OK:
		release_notes_.text += "\n\n%s" % (
			tr("无法打开更新页面（错误 %d）。") % error
		)
