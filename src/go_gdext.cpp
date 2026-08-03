// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// 这是供godot端调用的各种功能封装。

#include "go_notes.hpp"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <utility>
#include <vector>

namespace nd::go::gdext {
inline constexpr char kInvalidBoardSizeMessage[] = "ngrids must be in [1, 52]";

inline godot::Array
preset_stones_to_array_(const std::vector<GoCorePresetStone> &preset_stones) {
  godot::Array result{};
  for (const auto &stone : preset_stones) {
    godot::Dictionary data{};
    data["color"] = static_cast<int64_t>(stone.color);
    data["row"] = static_cast<int64_t>(stone.row);
    data["column"] = static_cast<int64_t>(stone.column);
    result.push_back(data);
  }
  return result;
}

class GoNotes final : public godot::RefCounted {
  GDCLASS(GoNotes, godot::RefCounted)

public:
  GoNotes();

  bool reset(int64_t ngrids);
  bool load_sgf_file(const godot::String &path);
  bool save_sgf_file(const godot::String &path);
  bool export_pptx_file(const godot::String &path,
                        const godot::String &template_path,
                        const godot::String &image_format);
  int64_t execute_command(const godot::String &command);
  int64_t append_note();
  int64_t remove_note(int64_t note_index);
  int64_t update_note_comment(int64_t note_index, const godot::String &comment);
  int64_t update_note_text(int64_t note_index, const godot::String &title,
                           const godot::String &comment);
  int64_t update_note_numbering(int64_t note_index, int64_t numbering);
  int64_t update_note_sequential_mark(int64_t note_index, int64_t row,
                                      int64_t column, bool delete_mark);
  int64_t update_note_symbol_mark(int64_t note_index, int64_t row,
                                  int64_t column, const godot::String &symbol);
  int64_t replace_note_sequential_marks(int64_t note_index,
                                        const godot::Array &marks);
  int64_t replace_note_symbol_marks(int64_t note_index,
                                    const godot::Array &marks);
  int64_t update_sgf_metadata(const godot::Dictionary &changes);
  int64_t reorder_branches(int64_t parent_uid,
                           const godot::PackedInt64Array &ordered_uids);
  int64_t undo();
  int64_t redo();
  [[nodiscard]] godot::PackedInt64Array get_straightforward_path() const;
  [[nodiscard]] int64_t get_board_size() const;
  [[nodiscard]] int64_t get_state(int64_t row, int64_t column) const;
  [[nodiscard]] godot::String get_message() const;
  [[nodiscard]] int64_t get_error_uid() const;
  [[nodiscard]] int64_t get_current_uid() const;
  [[nodiscard]] int64_t get_latest_move_color() const;
  [[nodiscard]] bool can_place_stone(int64_t color, int64_t row,
                                     int64_t column) const;
  [[nodiscard]] int64_t can_preset_stone() const;
  [[nodiscard]] godot::PackedInt32Array get_position_at(int64_t uid) const;
  [[nodiscard]] godot::PackedInt32Array get_move_numbers_at(int64_t uid) const;
  [[nodiscard]] godot::Dictionary
  get_position_snapshot_at(int64_t uid, int64_t move_count) const;
  [[nodiscard]] godot::Dictionary
  get_note_position_snapshot_at(int64_t uid, int64_t note_index) const;
  [[nodiscard]] godot::Dictionary get_node_at(int64_t uid) const;
  [[nodiscard]] godot::Array get_next_moves() const;
  [[nodiscard]] godot::Array get_notes_at(int64_t uid) const;
  [[nodiscard]] godot::String get_first_note_title_at(int64_t uid) const;
  [[nodiscard]] godot::Dictionary get_sgf_metadata() const;
  [[nodiscard]] bool can_undo() const;
  [[nodiscard]] bool can_redo() const;

protected:
  static void _bind_methods();

private:
  int64_t
  execute_note_command_(std::unique_ptr<nd::go::GoNotes::Command> command);

  std::unique_ptr<nd::go::GoNotes> go_notes_;
  godot::String wrapper_message_{};
};

inline GoNotes::GoNotes() : go_notes_(std::make_unique<nd::go::GoNotes>(19)) {}

inline void GoNotes::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("reset", "ngrids"),
                              &GoNotes::reset);
  godot::ClassDB::bind_method(godot::D_METHOD("load_sgf_file", "path"),
                              &GoNotes::load_sgf_file);
  godot::ClassDB::bind_method(godot::D_METHOD("save_sgf_file", "path"),
                              &GoNotes::save_sgf_file);
  godot::ClassDB::bind_method(godot::D_METHOD("export_pptx_file", "path",
                                              "template_path", "image_format"),
                              &GoNotes::export_pptx_file);
  godot::ClassDB::bind_method(godot::D_METHOD("execute_command", "command"),
                              &GoNotes::execute_command);
  godot::ClassDB::bind_method(godot::D_METHOD("append_note"),
                              &GoNotes::append_note);
  godot::ClassDB::bind_method(godot::D_METHOD("remove_note", "note_index"),
                              &GoNotes::remove_note);
  godot::ClassDB::bind_method(
      godot::D_METHOD("update_note_comment", "note_index", "comment"),
      &GoNotes::update_note_comment);
  godot::ClassDB::bind_method(
      godot::D_METHOD("update_note_text", "note_index", "title", "comment"),
      &GoNotes::update_note_text);
  godot::ClassDB::bind_method(
      godot::D_METHOD("update_note_numbering", "note_index", "numbering"),
      &GoNotes::update_note_numbering);
  godot::ClassDB::bind_method(godot::D_METHOD("update_note_sequential_mark",
                                              "note_index", "row", "column",
                                              "delete_mark"),
                              &GoNotes::update_note_sequential_mark);
  godot::ClassDB::bind_method(godot::D_METHOD("update_note_symbol_mark",
                                              "note_index", "row", "column",
                                              "symbol"),
                              &GoNotes::update_note_symbol_mark);
  godot::ClassDB::bind_method(
      godot::D_METHOD("replace_note_sequential_marks", "note_index", "marks"),
      &GoNotes::replace_note_sequential_marks);
  godot::ClassDB::bind_method(
      godot::D_METHOD("replace_note_symbol_marks", "note_index", "marks"),
      &GoNotes::replace_note_symbol_marks);
  godot::ClassDB::bind_method(godot::D_METHOD("update_sgf_metadata", "changes"),
                              &GoNotes::update_sgf_metadata);
  godot::ClassDB::bind_method(
      godot::D_METHOD("reorder_branches", "parent_uid", "ordered_uids"),
      &GoNotes::reorder_branches);
  godot::ClassDB::bind_method(godot::D_METHOD("undo"), &GoNotes::undo);
  godot::ClassDB::bind_method(godot::D_METHOD("redo"), &GoNotes::redo);
  godot::ClassDB::bind_method(godot::D_METHOD("get_straightforward_path"),
                              &GoNotes::get_straightforward_path);
  godot::ClassDB::bind_method(godot::D_METHOD("get_board_size"),
                              &GoNotes::get_board_size);
  godot::ClassDB::bind_method(godot::D_METHOD("get_state", "row", "column"),
                              &GoNotes::get_state);
  godot::ClassDB::bind_method(godot::D_METHOD("get_message"),
                              &GoNotes::get_message);
  godot::ClassDB::bind_method(godot::D_METHOD("get_error_uid"),
                              &GoNotes::get_error_uid);
  godot::ClassDB::bind_method(
      godot::D_METHOD("can_place_stone", "color", "row", "column"),
      &GoNotes::can_place_stone);
  godot::ClassDB::bind_method(godot::D_METHOD("can_preset_stone"),
                              &GoNotes::can_preset_stone);
  godot::ClassDB::bind_method(godot::D_METHOD("get_current_uid"),
                              &GoNotes::get_current_uid);
  godot::ClassDB::bind_method(godot::D_METHOD("get_latest_move_color"),
                              &GoNotes::get_latest_move_color);
  godot::ClassDB::bind_method(godot::D_METHOD("get_position_at", "uid"),
                              &GoNotes::get_position_at);
  godot::ClassDB::bind_method(godot::D_METHOD("get_move_numbers_at", "uid"),
                              &GoNotes::get_move_numbers_at);
  godot::ClassDB::bind_method(
      godot::D_METHOD("get_position_snapshot_at", "uid", "move_count"),
      &GoNotes::get_position_snapshot_at);
  godot::ClassDB::bind_method(
      godot::D_METHOD("get_note_position_snapshot_at", "uid", "note_index"),
      &GoNotes::get_note_position_snapshot_at);
  godot::ClassDB::bind_method(godot::D_METHOD("get_node_at", "uid"),
                              &GoNotes::get_node_at);
  godot::ClassDB::bind_method(godot::D_METHOD("get_next_moves"),
                              &GoNotes::get_next_moves);
  godot::ClassDB::bind_method(godot::D_METHOD("get_notes_at", "uid"),
                              &GoNotes::get_notes_at);
  godot::ClassDB::bind_method(godot::D_METHOD("get_first_note_title_at", "uid"),
                              &GoNotes::get_first_note_title_at);
  godot::ClassDB::bind_method(godot::D_METHOD("get_sgf_metadata"),
                              &GoNotes::get_sgf_metadata);
  godot::ClassDB::bind_method(godot::D_METHOD("can_undo"), &GoNotes::can_undo);
  godot::ClassDB::bind_method(godot::D_METHOD("can_redo"), &GoNotes::can_redo);
  ADD_SIGNAL(godot::MethodInfo("changed"));
}

inline bool GoNotes::reset(int64_t ngrids) {
  wrapper_message_ = godot::String{};
  if (ngrids < std::numeric_limits<int>::min() ||
      ngrids > std::numeric_limits<int>::max()) {
    wrapper_message_ = kInvalidBoardSizeMessage;
    return false;
  }

  try {
    auto replacement =
        std::make_unique<nd::go::GoNotes>(static_cast<int>(ngrids));
    go_notes_ = std::move(replacement);
    emit_signal("changed");
    return true;
  } catch (const std::invalid_argument &error) {
    wrapper_message_ = godot::String::utf8(error.what());
    return false;
  }
}

inline bool GoNotes::load_sgf_file(const godot::String &path) {
  wrapper_message_ = godot::String{};
  const godot::CharString utf8_path = path.utf8();
  const std::string path_text{utf8_path.get_data(),
                              static_cast<size_t>(utf8_path.length())};
  std::string error_message{};
  auto replacement = nd::go::GoNotes::from_sgf_file(path_text, error_message);
  if (!replacement) {
    wrapper_message_ = godot::String::utf8(error_message.c_str());
    return false;
  }

  go_notes_ = std::move(replacement);
  emit_signal("changed");
  return true;
}

inline bool GoNotes::save_sgf_file(const godot::String &path) {
  wrapper_message_ = godot::String{};
  const godot::CharString utf8_path = path.utf8();
  const std::string path_text{utf8_path.get_data(),
                              static_cast<size_t>(utf8_path.length())};
  std::string error_message{};
  if (!go_notes_->save_sgf_file(path_text, error_message)) {
    wrapper_message_ = godot::String::utf8(error_message.c_str());
    return false;
  }
  return true;
}

inline bool GoNotes::export_pptx_file(const godot::String &path,
                                      const godot::String &template_path,
                                      const godot::String &image_format) {
  wrapper_message_ = godot::String{};
  auto *project_settings = godot::ProjectSettings::get_singleton();
  const auto output = project_settings == nullptr
                          ? path
                          : project_settings->globalize_path(path);
  const godot::CharString output_utf8 = output.utf8();
  const std::string output_text{output_utf8.get_data(),
                                static_cast<size_t>(output_utf8.length())};
  const auto template_file =
      godot::FileAccess::open(template_path, godot::FileAccess::READ);
  if (template_file.is_null()) {
    wrapper_message_ = "[GNE0026] cannot read PPTX template";
    return false;
  }
  const auto template_buffer =
      template_file->get_buffer(template_file->get_length());
  if (template_buffer.is_empty()) {
    wrapper_message_ = "[GNE0027] invalid PPTX template";
    return false;
  }
  const std::vector<uint8_t> template_data{
      template_buffer.ptr(), template_buffer.ptr() + template_buffer.size()};
  const godot::String normalized_format = image_format.strip_edges().to_lower();
  nd::go::GoNotes::PptxImageFormat native_format{};
  if (normalized_format == "svg") {
    native_format = nd::go::GoNotes::PptxImageFormat::Svg;
  } else if (normalized_format == "png") {
    native_format = nd::go::GoNotes::PptxImageFormat::Png;
  } else {
    wrapper_message_ = "[GNE0033] unsupported PPTX image format";
    return false;
  }
  std::string error_message{};
  if (!go_notes_->export_pptx_file(output_text, template_data, error_message,
                                   native_format)) {
    wrapper_message_ = godot::String::utf8(error_message.c_str());
    return false;
  }
  return true;
}

inline int64_t GoNotes::execute_command(const godot::String &command) {
  wrapper_message_ = godot::String{};
  const godot::CharString utf8_command = command.utf8();
  const std::string_view command_text{
      utf8_command.get_data(), static_cast<size_t>(utf8_command.length())};
  const auto result = go_notes_->execute(command_text);
  if (result == 0)
    emit_signal("changed");
  return result;
}

inline int64_t GoNotes::execute_note_command_(
    std::unique_ptr<nd::go::GoNotes::Command> command) {
  wrapper_message_ = godot::String{};
  const auto result = go_notes_->execute(std::move(command));
  if (result == 0)
    emit_signal("changed");
  return result;
}

inline int64_t GoNotes::append_note() {
  return execute_note_command_(std::make_unique<nd::go::GoNotes::AppendNote>());
}

inline int64_t GoNotes::remove_note(int64_t note_index) {
  return execute_note_command_(std::make_unique<nd::go::GoNotes::RemoveNote>(
      static_cast<size_t>(note_index)));
}

inline int64_t GoNotes::update_note_comment(int64_t note_index,
                                            const godot::String &comment) {
  const godot::CharString utf8_comment = comment.utf8();
  std::string comment_text{utf8_comment.get_data(),
                           static_cast<size_t>(utf8_comment.length())};
  return execute_note_command_(std::make_unique<nd::go::GoNotes::UpdateComment>(
      static_cast<size_t>(note_index), std::move(comment_text)));
}

inline int64_t GoNotes::update_note_text(int64_t note_index,
                                         const godot::String &title,
                                         const godot::String &comment) {
  const godot::CharString utf8_title = title.utf8();
  std::string title_text{utf8_title.get_data(),
                         static_cast<size_t>(utf8_title.length())};
  const godot::CharString utf8_comment = comment.utf8();
  std::string comment_text{utf8_comment.get_data(),
                           static_cast<size_t>(utf8_comment.length())};
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::UpdateNoteText>(
          static_cast<size_t>(note_index), std::move(title_text),
          std::move(comment_text)));
}

inline int64_t GoNotes::update_note_numbering(int64_t note_index,
                                              int64_t numbering) {
  const auto native_numbering =
      numbering >= 0 && numbering < nd::go::kNoteNumberingOptionCount
          ? static_cast<uint8_t>(numbering)
          : std::numeric_limits<uint8_t>::max();
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::UpdateNoteNumbering>(
          static_cast<size_t>(note_index), native_numbering));
}

inline int64_t GoNotes::update_sgf_metadata(const godot::Dictionary &changes) {
  std::vector<std::pair<std::string, std::string>> native_changes{};
  const auto keys = changes.keys();
  native_changes.reserve(keys.size());
  for (int64_t index = 0; index < keys.size(); ++index) {
    const godot::String name = keys[index];
    const godot::String value = changes[name];
    const auto utf8_name = name.utf8();
    const auto utf8_value = value.utf8();
    native_changes.emplace_back(
        std::string{utf8_name.get_data(),
                    static_cast<size_t>(utf8_name.length())},
        std::string{utf8_value.get_data(),
                    static_cast<size_t>(utf8_value.length())});
  }
  if (native_changes.empty())
    return 0;
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::UpdateSgfMetadataCommand>(
          std::move(native_changes)));
}

inline int64_t GoNotes::update_note_sequential_mark(int64_t note_index,
                                                    int64_t row, int64_t column,
                                                    bool delete_mark) {
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::UpdateSequentialMarks>(
          static_cast<size_t>(note_index), static_cast<size_t>(row),
          static_cast<size_t>(column), delete_mark));
}

inline int64_t GoNotes::update_note_symbol_mark(int64_t note_index, int64_t row,
                                                int64_t column,
                                                const godot::String &symbol) {
  const godot::CharString utf8_symbol = symbol.utf8();
  std::string symbol_text{utf8_symbol.get_data(),
                          static_cast<size_t>(utf8_symbol.length())};
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::UpdateSymbolMarks>(
          static_cast<size_t>(note_index), static_cast<size_t>(row),
          static_cast<size_t>(column), std::move(symbol_text)));
}

inline int64_t
GoNotes::replace_note_sequential_marks(int64_t note_index,
                                       const godot::Array &marks) {
  std::vector<std::pair<uint16_t, uint16_t>> native_marks{};
  native_marks.reserve(static_cast<size_t>(marks.size()));
  for (const auto &value : marks) {
    const godot::Dictionary mark = value;
    native_marks.emplace_back(
        static_cast<uint16_t>(static_cast<int64_t>(mark.get("row", 0))),
        static_cast<uint16_t>(static_cast<int64_t>(mark.get("column", 0))));
  }
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::ReplaceSequentialMarks>(
          static_cast<size_t>(note_index), std::move(native_marks)));
}

inline int64_t GoNotes::replace_note_symbol_marks(int64_t note_index,
                                                  const godot::Array &marks) {
  std::vector<std::tuple<uint16_t, uint16_t, std::string>> native_marks{};
  native_marks.reserve(static_cast<size_t>(marks.size()));
  for (const auto &value : marks) {
    const godot::Dictionary mark = value;
    const godot::String symbol = mark.get("symbol", godot::String{});
    const godot::CharString utf8_symbol = symbol.utf8();
    native_marks.emplace_back(
        static_cast<uint16_t>(static_cast<int64_t>(mark.get("row", 0))),
        static_cast<uint16_t>(static_cast<int64_t>(mark.get("column", 0))),
        std::string{utf8_symbol.get_data(),
                    static_cast<size_t>(utf8_symbol.length())});
  }
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::ReplaceSymbolMarks>(
          static_cast<size_t>(note_index), std::move(native_marks)));
}

inline int64_t
GoNotes::reorder_branches(int64_t parent_uid,
                          const godot::PackedInt64Array &ordered_uids) {
  if (parent_uid < 0)
    return -1;
  std::vector<uint64_t> native_uids{};
  native_uids.reserve(static_cast<size_t>(ordered_uids.size()));
  for (const auto uid : ordered_uids) {
    if (uid >= 0)
      native_uids.push_back(static_cast<uint64_t>(uid));
  }
  return execute_note_command_(
      std::make_unique<nd::go::GoNotes::ReorderBranchesCommand>(
          static_cast<uint64_t>(parent_uid), std::move(native_uids)));
}

inline int64_t GoNotes::undo() {
  wrapper_message_ = godot::String{};
  const auto result = go_notes_->undo();
  if (result == 0)
    emit_signal("changed");
  return result;
}

inline int64_t GoNotes::redo() {
  wrapper_message_ = godot::String{};
  const auto result = go_notes_->redo();
  if (result == 0)
    emit_signal("changed");
  return result;
}

inline godot::PackedInt64Array GoNotes::get_straightforward_path() const {
  godot::PackedInt64Array path{};
  for (const auto uid : go_notes_->straightforward_path())
    path.push_back(static_cast<int64_t>(uid));
  return path;
}

inline int64_t GoNotes::get_board_size() const {
  return go_notes_->board_size();
}

inline int64_t GoNotes::get_state(int64_t row, int64_t column) const {
  if (row < 0 || column < 0)
    return -1;
  return go_notes_->state_at(static_cast<size_t>(row),
                             static_cast<size_t>(column));
}

inline bool GoNotes::can_place_stone(int64_t color, int64_t row,
                                     int64_t column) const {
  if ((color != 1 && color != 2) || row < 1 || column < 1)
    return false;
  if (row > static_cast<int64_t>(go_notes_->board_size()) ||
      column > static_cast<int64_t>(go_notes_->board_size()))
    return false;

  return go_notes_->can_place_stone(static_cast<int>(color),
                                    static_cast<size_t>(row),
                                    static_cast<size_t>(column));
}

inline int64_t GoNotes::can_preset_stone() const {
  return static_cast<int64_t>(go_notes_->can_preset_stone());
}

inline godot::String GoNotes::get_message() const {
  if (!wrapper_message_.is_empty())
    return wrapper_message_;
  return godot::String::utf8(go_notes_->message().c_str());
}

inline int64_t GoNotes::get_error_uid() const {
  return static_cast<int64_t>(go_notes_->error_uid());
}

inline int64_t GoNotes::get_current_uid() const {
  return static_cast<int64_t>(go_notes_->current_uid());
}

inline int64_t GoNotes::get_latest_move_color() const {
  return static_cast<int64_t>(go_notes_->latest_move_color());
}

inline godot::PackedInt32Array GoNotes::get_position_at(int64_t uid) const {
  godot::PackedInt32Array states{};
  if (uid < 0)
    return states;

  const auto position =
      go_notes_->position_states_at(static_cast<uint64_t>(uid));
  if (position.empty())
    return states;

  states.resize(static_cast<int64_t>(position.size()));
  for (size_t index = 0; index < position.size(); ++index)
    states.set(static_cast<int64_t>(index), position[index]);
  return states;
}

inline godot::PackedInt32Array GoNotes::get_move_numbers_at(int64_t uid) const {
  godot::PackedInt32Array move_numbers{};
  if (uid < 0)
    return move_numbers;

  const auto snapshot =
      go_notes_->position_snapshot_at(static_cast<uint64_t>(uid), 0);
  if (snapshot.move_numbers.empty())
    return move_numbers;

  move_numbers.resize(static_cast<int64_t>(snapshot.move_numbers.size()));
  for (size_t index = 0; index < snapshot.move_numbers.size(); ++index)
    move_numbers.set(static_cast<int64_t>(index), snapshot.move_numbers[index]);
  return move_numbers;
}

inline godot::Dictionary
GoNotes::get_position_snapshot_at(int64_t uid, int64_t move_count) const {
  godot::Dictionary result{};
  if (uid < 0 || move_count < 0)
    return result;

  const auto snapshot = go_notes_->position_snapshot_at(
      static_cast<uint64_t>(uid), static_cast<size_t>(move_count));
  if (snapshot.states.empty() ||
      snapshot.move_numbers.size() != snapshot.states.size())
    return result;

  godot::PackedInt32Array states{};
  godot::PackedInt32Array move_numbers{};
  states.resize(static_cast<int64_t>(snapshot.states.size()));
  move_numbers.resize(static_cast<int64_t>(snapshot.move_numbers.size()));
  for (size_t index = 0; index < snapshot.states.size(); ++index) {
    const auto godot_index = static_cast<int64_t>(index);
    states.set(godot_index, snapshot.states[index]);
    move_numbers.set(godot_index, snapshot.move_numbers[index]);
  }
  result["board_size"] = snapshot.board_size;
  result["states"] = states;
  result["move_numbers"] = move_numbers;
  return result;
}

inline godot::Dictionary
GoNotes::get_note_position_snapshot_at(int64_t uid, int64_t note_index) const {
  godot::Dictionary result{};
  if (uid < 0 || note_index < 0)
    return result;

  const auto snapshot = go_notes_->note_position_snapshot_at(
      static_cast<uint64_t>(uid), static_cast<size_t>(note_index));
  if (snapshot.states.empty() ||
      snapshot.move_numbers.size() != snapshot.states.size())
    return result;

  godot::PackedInt32Array states{};
  godot::PackedInt32Array move_numbers{};
  states.resize(static_cast<int64_t>(snapshot.states.size()));
  move_numbers.resize(static_cast<int64_t>(snapshot.move_numbers.size()));
  for (size_t index = 0; index < snapshot.states.size(); ++index) {
    const auto godot_index = static_cast<int64_t>(index);
    states.set(godot_index, snapshot.states[index]);
    move_numbers.set(godot_index, snapshot.move_numbers[index]);
  }
  result["board_size"] = snapshot.board_size;
  result["states"] = states;
  result["move_numbers"] = move_numbers;
  return result;
}

inline godot::Dictionary GoNotes::get_node_at(int64_t uid) const {
  godot::Dictionary node_data{};
  if (uid < 0)
    return node_data;

  const auto native_uid = static_cast<uint64_t>(uid);
  const auto node = go_notes_->node_at(native_uid);
  if (!node)
    return node_data;
  const auto notes = go_notes_->notes_at(native_uid);

  godot::Array children{};
  for (const auto &child : node->children) {
    godot::Dictionary child_data{};
    child_data["uid"] = static_cast<int64_t>(child.uid);
    child_data["color"] = static_cast<int64_t>(child.color);
    child_data["row"] = static_cast<int64_t>(child.row);
    child_data["column"] = static_cast<int64_t>(child.column);
    child_data["preset_stones"] = preset_stones_to_array_(child.preset_stones);
    children.push_back(child_data);
  }
  node_data["uid"] = static_cast<int64_t>(node->uid);
  node_data["color"] = static_cast<int64_t>(node->color);
  node_data["row"] = static_cast<int64_t>(node->row);
  node_data["column"] = static_cast<int64_t>(node->column);
  node_data["preset_stones"] = preset_stones_to_array_(node->preset_stones);
  node_data["children"] = children;
  node_data["has_notes"] = !notes.empty();
  if (!notes.empty()) {
    node_data["first_note_title"] =
        godot::String::utf8(notes.front().title.c_str());
    node_data["first_note_comment"] =
        godot::String::utf8(notes.front().comment.c_str());
  }
  return node_data;
}

inline godot::Array GoNotes::get_next_moves() const {
  godot::Array moves{};
  for (const auto &child : go_notes_->next_moves()) {
    godot::Dictionary move{};
    move["uid"] = static_cast<int64_t>(child.uid);
    move["color"] = static_cast<int64_t>(child.color);
    move["row"] = static_cast<int64_t>(child.row);
    move["column"] = static_cast<int64_t>(child.column);
    move["preset_stones"] = preset_stones_to_array_(child.preset_stones);
    moves.push_back(move);
  }
  return moves;
}
inline godot::Array GoNotes::get_notes_at(int64_t uid) const {
  godot::Array notes_data{};
  if (uid < 0)
    return notes_data;

  for (const auto &note : go_notes_->notes_at(static_cast<uint64_t>(uid))) {
    godot::Dictionary note_data{};
    note_data["numbering"] = static_cast<int64_t>(note.numbering);
    note_data["title"] = godot::String::utf8(note.title.c_str());
    note_data["comment"] = godot::String::utf8(note.comment.c_str());

    godot::Array sequential_marks{};
    for (const auto &[row, column] : note.sequential_marks) {
      godot::Dictionary mark{};
      mark["row"] = static_cast<int64_t>(row);
      mark["column"] = static_cast<int64_t>(column);
      sequential_marks.push_back(mark);
    }
    note_data["sequential_marks"] = sequential_marks;

    godot::Array symbol_marks{};
    for (const auto &[row, column, symbol] : note.symbol_marks) {
      godot::Dictionary mark{};
      mark["row"] = static_cast<int64_t>(row);
      mark["column"] = static_cast<int64_t>(column);
      mark["symbol"] = godot::String::utf8(symbol.c_str());
      symbol_marks.push_back(mark);
    }
    note_data["symbol_marks"] = symbol_marks;
    notes_data.push_back(note_data);
  }
  return notes_data;
}

inline godot::String GoNotes::get_first_note_title_at(int64_t uid) const {
  const auto title = go_notes_->first_note_title_at(static_cast<uint64_t>(uid));
  return godot::String::utf8(title.c_str());
}

inline godot::Dictionary GoNotes::get_sgf_metadata() const {
  const auto &metadata = go_notes_->sgf_metadata();
  godot::Dictionary result{};
  result["game_name"] = godot::String::utf8(metadata.game_name.c_str());
  result["event"] = godot::String::utf8(metadata.event.c_str());
  result["round"] = godot::String::utf8(metadata.round.c_str());
  result["date"] = godot::String::utf8(metadata.date.c_str());
  result["place"] = godot::String::utf8(metadata.place.c_str());
  result["result"] = godot::String::utf8(metadata.result.c_str());
  result["rules"] = godot::String::utf8(metadata.rules.c_str());
  result["komi"] = godot::String::utf8(metadata.komi.c_str());
  result["handicap"] = godot::String::utf8(metadata.handicap.c_str());
  result["time_limit"] = godot::String::utf8(metadata.time_limit.c_str());
  result["overtime"] = godot::String::utf8(metadata.overtime.c_str());
  result["black_name"] = godot::String::utf8(metadata.black_name.c_str());
  result["black_rank"] = godot::String::utf8(metadata.black_rank.c_str());
  result["black_team"] = godot::String::utf8(metadata.black_team.c_str());
  result["white_name"] = godot::String::utf8(metadata.white_name.c_str());
  result["white_rank"] = godot::String::utf8(metadata.white_rank.c_str());
  result["white_team"] = godot::String::utf8(metadata.white_team.c_str());
  result["annotator"] = godot::String::utf8(metadata.annotator.c_str());
  result["copyright"] = godot::String::utf8(metadata.copyright.c_str());
  result["source"] = godot::String::utf8(metadata.source.c_str());
  result["user"] = godot::String::utf8(metadata.user.c_str());
  result["game_comment"] = godot::String::utf8(metadata.game_comment.c_str());
  result["opening"] = godot::String::utf8(metadata.opening.c_str());
  result["variation_style"] =
      godot::String::utf8(metadata.variation_style.c_str());
  result["player_to_play"] =
      godot::String::utf8(metadata.player_to_play.c_str());

  godot::Dictionary extra_properties{};
  for (const auto &[name, values] : metadata.extra_root_properties) {
    godot::Array property_values{};
    for (const auto &value : values)
      property_values.push_back(godot::String::utf8(value.c_str()));
    extra_properties[godot::String::utf8(name.c_str())] = property_values;
  }
  result["extra_root_properties"] = extra_properties;
  return result;
}

inline bool GoNotes::can_undo() const { return go_notes_->can_undo(); }

inline bool GoNotes::can_redo() const { return go_notes_->can_redo(); }

void initialize_go_gdext(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
    return;
  GDREGISTER_CLASS(GoNotes)
}

void uninitialize_go_gdext(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE)
    return;
}
} // namespace nd::go::gdext

extern "C" {
GDExtensionBool GDE_EXPORT
go_gdext_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                      const GDExtensionClassLibraryPtr library,
                      GDExtensionInitialization *initialization) {
  godot::GDExtensionBinding::InitObject init_object(get_proc_address, library,
                                                    initialization);
  init_object.register_initializer(nd::go::gdext::initialize_go_gdext);
  init_object.register_terminator(nd::go::gdext::uninitialize_go_gdext);
  init_object.set_minimum_library_initialization_level(
      godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return init_object.init();
}
}
