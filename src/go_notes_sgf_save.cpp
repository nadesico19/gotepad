// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// SGF文件写入相关功能的实现。

#include "go_notes.hpp"

#include <ISgfcArguments.h>
#include <ISgfcColorPropertyValue.h>
#include <ISgfcComposedPropertyValue.h>
#include <ISgfcDocumentWriteResult.h>
#include <ISgfcDocumentWriter.h>
#include <ISgfcGame.h>
#include <ISgfcGoMovePropertyValue.h>
#include <ISgfcGoPointPropertyValue.h>
#include <ISgfcGoStonePropertyValue.h>
#include <ISgfcMessage.h>
#include <ISgfcMovePropertyValue.h>
#include <ISgfcNode.h>
#include <ISgfcNumberPropertyValue.h>
#include <ISgfcPointPropertyValue.h>
#include <ISgfcPropertyFactory.h>
#include <ISgfcPropertyValue.h>
#include <ISgfcPropertyValueFactory.h>
#include <ISgfcRealPropertyValue.h>
#include <ISgfcSimpleTextPropertyValue.h>
#include <ISgfcSinglePropertyValue.h>
#include <ISgfcStonePropertyValue.h>
#include <ISgfcTextPropertyValue.h>
#include <ISgfcTreeBuilder.h>
#include <SgfcArgumentType.h>
#include <SgfcBoardSize.h>
#include <SgfcColor.h>
#include <SgfcExitCode.h>
#include <SgfcGameResult.h>
#include <SgfcGameType.h>
#include <SgfcPlusPlusFactory.h>
#include <SgfcPropertyType.h>

#include <algorithm>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace nd::go {
namespace {
using LibSgfcPlusPlus::ISgfcNode;
using LibSgfcPlusPlus::ISgfcPropertyFactory;
using LibSgfcPlusPlus::ISgfcPropertyValue;
using LibSgfcPlusPlus::ISgfcPropertyValueFactory;
using LibSgfcPlusPlus::ISgfcTreeBuilder;
using LibSgfcPlusPlus::SgfcArgumentType;
using LibSgfcPlusPlus::SgfcBoardSize;
using LibSgfcPlusPlus::SgfcColor;
using LibSgfcPlusPlus::SgfcExitCode;
using LibSgfcPlusPlus::SgfcGameResult;
using LibSgfcPlusPlus::SgfcGameType;
using LibSgfcPlusPlus::SgfcPlusPlusFactory;
using LibSgfcPlusPlus::SgfcPropertyType;

inline constexpr char kGotepadVersion[] = "0.1.10";
inline constexpr char kGotepadProfileVersion[] = "1";
inline constexpr char kInvalidGameResultMessage[] =
    "[GNE0029] SGF result is not valid";
inline constexpr char kSequentialMarkLetters[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

struct SgfSaveContext {
  std::shared_ptr<ISgfcPropertyFactory> property_factory{};
  std::shared_ptr<ISgfcPropertyValueFactory> value_factory{};
  std::shared_ptr<ISgfcTreeBuilder> tree_builder{};
  SgfcBoardSize board_size{};
  const std::unordered_map<uint64_t, std::vector<GoNotesRecord>> *notes{};
};

void set_property_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::shared_ptr<ISgfcPropertyValue> &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory) {
  node->SetProperty(property_factory->CreateProperty(type, value));
}

void set_property_values_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::vector<std::shared_ptr<ISgfcPropertyValue>> &values,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory) {
  if (!values.empty())
    node->SetProperty(property_factory->CreateProperty(type, values));
}

void set_custom_property_(
    const std::shared_ptr<ISgfcNode> &node, const std::string &name,
    const std::vector<std::string> &values,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  std::vector<std::shared_ptr<ISgfcPropertyValue>> property_values{};
  property_values.reserve(values.size());
  for (const auto &value : values)
    property_values.push_back(value_factory->CreateCustomPropertyValue(value));
  node->SetProperty(property_factory->CreateProperty(name, property_values));
}

void set_custom_property_(
    const std::shared_ptr<ISgfcNode> &node, const std::string &name,
    const std::string &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  set_custom_property_(node, name, std::vector<std::string>{value},
                       property_factory, value_factory);
}

void set_simple_text_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::string &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  if (!value.empty())
    set_property_(node, type,
                  value_factory->CreateSimpleTextPropertyValue(value),
                  property_factory);
}

void set_text_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::string &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  if (!value.empty())
    set_property_(node, type, value_factory->CreateTextPropertyValue(value),
                  property_factory);
}

void set_number_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::string &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  if (!value.empty())
    set_property_(node, type,
                  value_factory->CreateNumberPropertyValue(std::stoll(value)),
                  property_factory);
}

void set_real_(
    const std::shared_ptr<ISgfcNode> &node, SgfcPropertyType type,
    const std::string &value,
    const std::shared_ptr<ISgfcPropertyFactory> &property_factory,
    const std::shared_ptr<ISgfcPropertyValueFactory> &value_factory) {
  if (!value.empty())
    set_property_(node, type,
                  value_factory->CreateRealPropertyValue(std::stod(value)),
                  property_factory);
}

std::string sgf_point_(uint16_t row, uint16_t column) {
  const auto encode_axis = [](uint16_t position) {
    return static_cast<char>(position <= 26 ? 'a' + position - 1
                                            : 'A' + position - 27);
  };
  return {encode_axis(column), encode_axis(row)};
}

bool note_has_content_(const GoNotesRecord &note) {
  return note.numbering != 0 || !note.title.empty() || !note.comment.empty() ||
         !note.sequential_marks.empty() || !note.symbol_marks.empty();
}

void append_note_properties_(const std::shared_ptr<ISgfcNode> &node,
                             const GoNotesRecord &note,
                             const SgfSaveContext &context) {
  set_custom_property_(node, "XN", std::to_string(note.numbering),
                       context.property_factory, context.value_factory);
  set_simple_text_(node, SgfcPropertyType::N, note.title,
                   context.property_factory, context.value_factory);
  set_text_(node, SgfcPropertyType::C, note.comment, context.property_factory,
            context.value_factory);

  std::vector<std::shared_ptr<ISgfcPropertyValue>> labels{};
  const auto label_count =
      std::min(note.sequential_marks.size(),
               static_cast<size_t>(sizeof(kSequentialMarkLetters) - 1));
  labels.reserve(label_count);
  for (size_t index = 0; index < label_count; ++index) {
    const auto &[row, column] = note.sequential_marks[index];
    labels.push_back(
        context.value_factory->CreateComposedGoPointAndSimpleTextPropertyValue(
            sgf_point_(row, column), context.board_size,
            std::string(1, kSequentialMarkLetters[index])));
  }
  set_property_values_(node, SgfcPropertyType::LB, labels,
                       context.property_factory);

  std::unordered_map<std::string,
                     std::vector<std::shared_ptr<ISgfcPropertyValue>>>
      symbol_values{};
  for (const auto &[row, column, symbol] : note.symbol_marks) {
    if (symbol != "TR" && symbol != "SQ" && symbol != "CR" && symbol != "MA")
      continue;
    symbol_values[symbol].push_back(
        context.value_factory->CreateGoPointPropertyValue(
            sgf_point_(row, column), context.board_size));
  }
  const std::pair<const char *, SgfcPropertyType> symbol_types[] = {
      {"TR", SgfcPropertyType::TR},
      {"SQ", SgfcPropertyType::SQ},
      {"CR", SgfcPropertyType::CR},
      {"MA", SgfcPropertyType::MA}};
  for (const auto &[symbol, type] : symbol_types)
    set_property_values_(node, type, symbol_values[symbol],
                         context.property_factory);
}

std::vector<const GoNotesRecord *>
notes_with_content_(uint64_t uid, const SgfSaveContext &context) {
  std::vector<const GoNotesRecord *> notes{};
  const auto found = context.notes->find(uid);
  if (found == context.notes->end())
    return notes;
  for (const auto &note : found->second) {
    if (note_has_content_(note))
      notes.push_back(&note);
  }
  return notes;
}

std::shared_ptr<ISgfcNode>
append_note_nodes_(const std::shared_ptr<ISgfcNode> &state_node, uint64_t uid,
                   const std::vector<const GoNotesRecord *> &notes,
                   size_t first_note_index, const SgfSaveContext &context) {
  auto tail = state_node;
  for (auto index = first_note_index; index < notes.size(); ++index) {
    auto note_node = SgfcPlusPlusFactory::CreateNode();
    set_custom_property_(note_node, "XU", std::to_string(uid),
                         context.property_factory, context.value_factory);
    append_note_properties_(note_node, *notes[index], context);
    context.tree_builder->AppendChild(tail, note_node);
    tail = std::move(note_node);
  }
  return tail;
}

std::shared_ptr<ISgfcNode>
append_pass_(const std::shared_ptr<ISgfcNode> &parent, uint64_t uid, int color,
             const SgfSaveContext &context) {
  auto pass_node = SgfcPlusPlusFactory::CreateNode();
  const auto sgf_color = color == 1 ? SgfcColor::Black : SgfcColor::White;
  const auto type = color == 1 ? SgfcPropertyType::B : SgfcPropertyType::W;
  set_property_(pass_node, type,
                context.value_factory->CreateGoMovePropertyValue(sgf_color),
                context.property_factory);
  set_custom_property_(pass_node, "XU", std::to_string(uid),
                       context.property_factory, context.value_factory);
  context.tree_builder->AppendChild(parent, pass_node);
  return pass_node;
}

void append_preset_properties_(const std::shared_ptr<ISgfcNode> &node,
                               const GoCoreRecordTreeNode &record,
                               const SgfSaveContext &context) {
  std::vector<std::shared_ptr<ISgfcPropertyValue>> add_black{};
  std::vector<std::shared_ptr<ISgfcPropertyValue>> add_white{};
  std::vector<std::shared_ptr<ISgfcPropertyValue>> erase{};
  for (const auto &stone : record.preset_stones) {
    const auto point = sgf_point_(stone.row, stone.column);
    if (stone.color == 1) {
      add_black.push_back(context.value_factory->CreateGoStonePropertyValue(
          point, context.board_size, SgfcColor::Black));
    } else if (stone.color == 2) {
      add_white.push_back(context.value_factory->CreateGoStonePropertyValue(
          point, context.board_size, SgfcColor::White));
    } else {
      erase.push_back(context.value_factory->CreateGoPointPropertyValue(
          point, context.board_size));
    }
  }
  set_property_values_(node, SgfcPropertyType::AB, add_black,
                       context.property_factory);
  set_property_values_(node, SgfcPropertyType::AW, add_white,
                       context.property_factory);
  set_property_values_(node, SgfcPropertyType::AE, erase,
                       context.property_factory);
}

void append_record_(const std::shared_ptr<ISgfcNode> &parent,
                    uint64_t parent_uid, const GoCoreRecordTreeNode &record,
                    int expected_color, const SgfSaveContext &context) {
  auto state_parent = parent;
  auto next_expected_color = expected_color;
  if ((record.color == 1 || record.color == 2) &&
      record.color != expected_color) {
    state_parent = append_pass_(parent, parent_uid, expected_color, context);
    next_expected_color = expected_color == 1 ? 2 : 1;
  }

  auto state_node = SgfcPlusPlusFactory::CreateNode();
  set_custom_property_(state_node, "XU", std::to_string(record.uid),
                       context.property_factory, context.value_factory);
  if (record.color == 0) {
    append_preset_properties_(state_node, record, context);
  } else {
    const auto type =
        record.color == 1 ? SgfcPropertyType::B : SgfcPropertyType::W;
    const auto color = record.color == 1 ? SgfcColor::Black : SgfcColor::White;
    set_property_(
        state_node, type,
        context.value_factory->CreateGoMovePropertyValue(
            sgf_point_(record.row, record.column), context.board_size, color),
        context.property_factory);
    next_expected_color = record.color == 1 ? 2 : 1;
  }
  context.tree_builder->AppendChild(state_parent, state_node);

  const auto notes = notes_with_content_(record.uid, context);
  if (!notes.empty())
    append_note_properties_(state_node, *notes.front(), context);
  const auto tail =
      append_note_nodes_(state_node, record.uid, notes, 1, context);
  for (const auto &child : record.children)
    append_record_(tail, record.uid, child, next_expected_color, context);
}

void append_metadata_(const std::shared_ptr<ISgfcNode> &root, int board_size,
                      const GoNotesSgfMetadata &metadata,
                      const SgfSaveContext &context) {
  set_property_(root, SgfcPropertyType::FF,
                context.value_factory->CreateNumberPropertyValue(4),
                context.property_factory);
  set_property_(
      root, SgfcPropertyType::GM,
      context.value_factory->CreateGameTypePropertyValue(SgfcGameType::Go),
      context.property_factory);
  set_property_(root, SgfcPropertyType::SZ,
                context.value_factory->CreateBoardSizePropertyValue(
                    SgfcBoardSize{board_size, board_size}, SgfcGameType::Go),
                context.property_factory);
  set_simple_text_(root, SgfcPropertyType::CA, "UTF-8",
                   context.property_factory, context.value_factory);
  set_property_(
      root, SgfcPropertyType::AP,
      context.value_factory->CreateComposedSimpleTextAndSimpleTextPropertyValue(
          "Gotepad", kGotepadVersion),
      context.property_factory);
  set_custom_property_(root, "GP", kGotepadProfileVersion,
                       context.property_factory, context.value_factory);
  set_custom_property_(root, "XU", "0", context.property_factory,
                       context.value_factory);

  set_simple_text_(root, SgfcPropertyType::GN, metadata.game_name,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::EV, metadata.event,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::RO, metadata.round,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::DT, metadata.date,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::PC, metadata.place,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::RE, metadata.result,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::RU, metadata.rules,
                   context.property_factory, context.value_factory);
  set_real_(root, SgfcPropertyType::KM, metadata.komi, context.property_factory,
            context.value_factory);
  set_number_(root, SgfcPropertyType::HA, metadata.handicap,
              context.property_factory, context.value_factory);
  set_real_(root, SgfcPropertyType::TM, metadata.time_limit,
            context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::OT, metadata.overtime,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::PB, metadata.black_name,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::BR, metadata.black_rank,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::BT, metadata.black_team,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::PW, metadata.white_name,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::WR, metadata.white_rank,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::WT, metadata.white_team,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::AN, metadata.annotator,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::CP, metadata.copyright,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::SO, metadata.source,
                   context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::US, metadata.user,
                   context.property_factory, context.value_factory);
  set_text_(root, SgfcPropertyType::GC, metadata.game_comment,
            context.property_factory, context.value_factory);
  set_simple_text_(root, SgfcPropertyType::ON, metadata.opening,
                   context.property_factory, context.value_factory);
  set_number_(root, SgfcPropertyType::ST, metadata.variation_style,
              context.property_factory, context.value_factory);
  if (metadata.player_to_play == "B" || metadata.player_to_play == "W") {
    set_property_(root, SgfcPropertyType::PL,
                  context.value_factory->CreateColorPropertyValue(
                      metadata.player_to_play == "B" ? SgfcColor::Black
                                                     : SgfcColor::White),
                  context.property_factory);
  }
  for (const auto &[name, values] : metadata.extra_root_properties)
    set_custom_property_(root, name, values, context.property_factory,
                         context.value_factory);
}

std::string write_error_(
    const std::shared_ptr<LibSgfcPlusPlus::ISgfcDocumentWriteResult> &result) {
  if (!result)
    return "SGF writer returned no result";
  const auto messages = result->GetParseResult();
  return messages.empty() ? "SGF writer rejected the document"
                          : messages.back()->GetFormattedMessageText();
}

std::filesystem::path save_temporary_path_(const std::filesystem::path &target,
                                           const std::string &suffix) {
  const auto temporary_name =
      "." + target.filename().u8string() + ".gotepad-" + suffix + ".tmp";
  return target.parent_path() / std::filesystem::u8path(temporary_name);
}

bool recover_interrupted_sgf_save_(const std::filesystem::path &target,
                                   const std::filesystem::path &staging,
                                   const std::filesystem::path &backup,
                                   std::string &error_message) {
  std::error_code error{};
  const bool backup_exists = std::filesystem::exists(backup, error);
  if (error) {
    error_message =
        "Unable to inspect temporary SGF backup: " + error.message();
    return false;
  }
  if (backup_exists) {
    const bool target_exists = std::filesystem::exists(target, error);
    if (error) {
      error_message = "Unable to inspect SGF save target: " + error.message();
      return false;
    }
    if (target_exists)
      std::filesystem::remove(backup, error);
    else
      std::filesystem::rename(backup, target, error);
    if (error) {
      error_message =
          "Unable to recover temporary SGF backup: " + error.message();
      return false;
    }
  }
  std::filesystem::remove(staging, error);
  if (error) {
    error_message =
        "Unable to remove stale SGF temporary file: " + error.message();
    return false;
  }
  return true;
}

bool write_staged_sgf_(const std::filesystem::path &staging,
                       const std::string &content, std::string &error_message) {
  std::ofstream file(staging, std::ios::binary | std::ios::trunc);
  if (!file) {
    error_message = "Unable to open temporary SGF file for writing";
    return false;
  }
  file.write(content.data(), static_cast<std::streamsize>(content.size()));
  file.flush();
  file.close();
  if (!file) {
    error_message = "Unable to write temporary SGF file";
    return false;
  }
  return true;
}

bool replace_sgf_from_staging_(const std::filesystem::path &target,
                               const std::filesystem::path &staging,
                               const std::filesystem::path &backup,
                               std::string &error_message) {
  std::error_code error{};
  const bool target_exists = std::filesystem::exists(target, error);
  if (error) {
    error_message = "Unable to inspect SGF save target: " + error.message();
    return false;
  }
  if (!target_exists) {
    std::filesystem::rename(staging, target, error);
    if (!error)
      return true;
    error_message = "Unable to install saved SGF file: " + error.message();
    return false;
  }
  if (!std::filesystem::is_regular_file(target, error) || error) {
    error_message =
        error ? "Unable to inspect SGF save target: " + error.message()
              : "SGF save target is not a regular file";
    return false;
  }
  std::filesystem::copy_file(target, backup, error);
  if (error) {
    error_message = "Unable to create temporary SGF backup: " + error.message();
    return false;
  }
  std::filesystem::remove(target, error);
  if (error) {
    std::error_code cleanup_error{};
    std::filesystem::remove(backup, cleanup_error);
    error_message = "Unable to replace existing SGF file: " + error.message();
    return false;
  }
  std::filesystem::rename(staging, target, error);
  if (error) {
    const auto replace_error = error.message();
    std::error_code restore_error{};
    std::filesystem::rename(backup, target, restore_error);
    if (restore_error) {
      error_message =
          "Unable to install saved SGF file (" + replace_error +
          "); recovery copy remains at " + backup.u8string() +
          " because automatic recovery failed: " + restore_error.message();
    } else {
      error_message = "Unable to install saved SGF file; the original file "
                      "was restored: " +
                      replace_error;
    }
    return false;
  }
  std::filesystem::remove(backup, error);
  if (error) {
    error_message = "SGF was saved, but its temporary backup could not be "
                    "removed: " +
                    error.message();
    return false;
  }
  return true;
}

bool write_sgf_safely_(const std::filesystem::path &target,
                       const std::string &content, std::string &error_message) {
  const auto staging = save_temporary_path_(target, "writing");
  const auto backup = save_temporary_path_(target, "backup");
  if (!recover_interrupted_sgf_save_(target, staging, backup, error_message))
    return false;
  if (!write_staged_sgf_(staging, content, error_message)) {
    std::error_code cleanup_error{};
    std::filesystem::remove(staging, cleanup_error);
    return false;
  }
  if (replace_sgf_from_staging_(target, staging, backup, error_message))
    return true;
  std::error_code cleanup_error{};
  std::filesystem::remove(staging, cleanup_error);
  return false;
}
} // namespace

bool GoNotes::save_sgf_file(const std::string &path,
                            std::string &error_message) const {
  error_message.clear();
  try {
    if (path.empty()) {
      error_message = "SGF save path is empty";
      return false;
    }
    if (!sgf_metadata_.result.empty() &&
        !SgfcGameResult::FromPropertyValue(sgf_metadata_.result).IsValid) {
      error_message = kInvalidGameResultMessage;
      return false;
    }

    const auto root = SgfcPlusPlusFactory::CreateNode();
    const auto game = SgfcPlusPlusFactory::CreateGame(root);
    const auto document = SgfcPlusPlusFactory::CreateDocument(game);
    const auto context =
        SgfSaveContext{SgfcPlusPlusFactory::CreatePropertyFactory(),
                       SgfcPlusPlusFactory::CreatePropertyValueFactory(),
                       game->GetTreeBuilder(),
                       SgfcBoardSize{board_size(), board_size()}, &notes_};
    append_metadata_(root, board_size(), sgf_metadata_, context);

    const auto root_notes = notes_with_content_(0, context);
    if (!root_notes.empty())
      append_note_properties_(root, *root_notes.front(), context);
    const auto root_tail = append_note_nodes_(root, 0, root_notes, 1, context);
    const auto expected_color = sgf_metadata_.player_to_play == "W" ? 2 : 1;
    for (const auto &child : go_core_.record_tree().children)
      append_record_(root_tail, 0, child, expected_color, context);

    const auto writer = SgfcPlusPlusFactory::CreateDocumentWriter();
    writer->GetArguments()->AddArgument(
        SgfcArgumentType::DoNotAddSgfcApProperty);
    std::string content{};
    const auto result = writer->WriteSgfContent(document, content);
    if (!result || result->GetExitCode() == SgfcExitCode::Error ||
        result->GetExitCode() == SgfcExitCode::FatalError) {
      error_message = write_error_(result);
      return false;
    }

    return write_sgf_safely_(std::filesystem::u8path(path), content,
                             error_message);
  } catch (const std::exception &error) {
    error_message = error.what();
    return false;
  }
}
} // namespace nd::go
