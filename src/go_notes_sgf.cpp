// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// SGF文件导入相关功能的实现。

#include "go_notes.hpp"

#include <ISgfcArguments.h>
#include <ISgfcComposedPropertyValue.h>
#include <ISgfcDocument.h>
#include <ISgfcDocumentReadResult.h>
#include <ISgfcDocumentReader.h>
#include <ISgfcGame.h>
#include <ISgfcGoMove.h>
#include <ISgfcGoMovePropertyValue.h>
#include <ISgfcGoPoint.h>
#include <ISgfcGoPointPropertyValue.h>
#include <ISgfcGoStone.h>
#include <ISgfcGoStonePropertyValue.h>
#include <ISgfcMovePropertyValue.h>
#include <ISgfcNode.h>
#include <ISgfcPointPropertyValue.h>
#include <ISgfcProperty.h>
#include <ISgfcSinglePropertyValue.h>
#include <ISgfcStonePropertyValue.h>
#include <SgfcArgumentType.h>
#include <SgfcColor.h>
#include <SgfcCoordinateSystem.h>
#include <SgfcGameResult.h>
#include <SgfcGameType.h>
#include <SgfcPlusPlusFactory.h>
#include <SgfcPropertyType.h>

#include <algorithm>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <memory>
#include <string>
#include <string_view>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace nd::go {
namespace {
using LibSgfcPlusPlus::ISgfcGame;
using LibSgfcPlusPlus::ISgfcGoMove;
using LibSgfcPlusPlus::ISgfcGoPoint;
using LibSgfcPlusPlus::ISgfcNode;
using LibSgfcPlusPlus::ISgfcSinglePropertyValue;
using LibSgfcPlusPlus::SgfcArgumentType;
using LibSgfcPlusPlus::SgfcColor;
using LibSgfcPlusPlus::SgfcCoordinateSystem;
using LibSgfcPlusPlus::SgfcGameResult;
using LibSgfcPlusPlus::SgfcGameType;
using LibSgfcPlusPlus::SgfcPlusPlusFactory;
using LibSgfcPlusPlus::SgfcPropertyType;

using SgfNotes = std::unordered_map<uint64_t, std::vector<GoNotesRecord>>;

bool is_valid_utf8_(std::string_view text) {
  for (size_t index = 0; index < text.size();) {
    const auto first = static_cast<unsigned char>(text[index]);
    size_t continuation_count{};
    uint32_t code_point{};
    if (first <= 0x7f) {
      ++index;
      continue;
    } else if (first >= 0xc2 && first <= 0xdf) {
      continuation_count = 1;
      code_point = first & 0x1f;
    } else if (first >= 0xe0 && first <= 0xef) {
      continuation_count = 2;
      code_point = first & 0x0f;
    } else if (first >= 0xf0 && first <= 0xf4) {
      continuation_count = 3;
      code_point = first & 0x07;
    } else {
      return false;
    }
    if (index + continuation_count >= text.size())
      return false;
    for (size_t offset = 1; offset <= continuation_count; ++offset) {
      const auto continuation =
          static_cast<unsigned char>(text[index + offset]);
      if ((continuation & 0xc0) != 0x80)
        return false;
      code_point = (code_point << 6) | (continuation & 0x3f);
    }
    if ((continuation_count == 2 && code_point < 0x800) ||
        (continuation_count == 3 && code_point < 0x10000) ||
        code_point > 0x10ffff ||
        (code_point >= 0xd800 && code_point <= 0xdfff)) {
      return false;
    }
    index += continuation_count + 1;
  }
  return true;
}

bool read_sgf_file_content_(const std::string &path, std::string &content,
                            std::string &error_message) {
  std::ifstream file(std::filesystem::u8path(path), std::ios::binary);
  if (!file) {
    error_message = "Unable to open SGF file";
    return false;
  }

  content.assign(std::istreambuf_iterator<char>(file),
                 std::istreambuf_iterator<char>());
  if (file.bad()) {
    error_message = "Unable to read SGF file";
    return false;
  }
  return true;
}

bool append_setup_point_(const std::shared_ptr<ISgfcGoPoint> &point,
                         uint16_t color, int board_size,
                         std::vector<GoCorePresetStone> &preset_stones,
                         std::vector<uint32_t> &seen_positions,
                         std::string &error_message) {
  if (!point) {
    error_message = "SGF setup point is invalid";
    return false;
  }

  const auto column =
      point->GetXPosition(SgfcCoordinateSystem::UpperLeftOrigin);
  const auto row = point->GetYPosition(SgfcCoordinateSystem::UpperLeftOrigin);
  if (row < 1 || row > board_size || column < 1 || column > board_size) {
    error_message = "SGF setup point is outside the board";
    return false;
  }

  const auto position =
      (static_cast<uint32_t>(row) << 16U) | static_cast<uint32_t>(column);
  if (std::find(seen_positions.begin(), seen_positions.end(), position) !=
      seen_positions.end()) {
    error_message = "SGF setup properties overlap at one point";
    return false;
  }
  seen_positions.push_back(position);
  preset_stones.push_back(
      {color, static_cast<uint16_t>(row), static_cast<uint16_t>(column)});
  return true;
}

bool read_setup_stones_(const std::shared_ptr<ISgfcNode> &node, int board_size,
                        std::vector<GoCorePresetStone> &preset_stones,
                        std::string &error_message) {
  preset_stones.clear();
  std::vector<uint32_t> seen_positions{};

  if (const auto property = node->GetProperty(SgfcPropertyType::AE)) {
    for (const auto &property_value : property->GetPropertyValues()) {
      const auto *single_value =
          property_value ? property_value->ToSingleValue() : nullptr;
      const auto *point_value =
          single_value ? single_value->ToPointValue() : nullptr;
      const auto *go_point_value =
          point_value ? point_value->ToGoPointValue() : nullptr;
      if (!append_setup_point_(
              go_point_value ? go_point_value->GetGoPoint() : nullptr, 0,
              board_size, preset_stones, seen_positions, error_message)) {
        return false;
      }
    }
  }

  for (const auto property_type :
       {SgfcPropertyType::AB, SgfcPropertyType::AW}) {
    const auto property = node->GetProperty(property_type);
    if (!property)
      continue;

    const auto expected_color = property_type == SgfcPropertyType::AB
                                    ? SgfcColor::Black
                                    : SgfcColor::White;
    const auto color =
        static_cast<uint16_t>(expected_color == SgfcColor::Black ? 1 : 2);
    for (const auto &property_value : property->GetPropertyValues()) {
      const auto *single_value =
          property_value ? property_value->ToSingleValue() : nullptr;
      const auto *stone_value =
          single_value ? single_value->ToStoneValue() : nullptr;
      const auto *go_stone_value =
          stone_value ? stone_value->ToGoStoneValue() : nullptr;
      const auto stone =
          go_stone_value ? go_stone_value->GetGoStone() : nullptr;
      if (!stone || stone->GetColor() != expected_color ||
          !append_setup_point_(stone->GetLocation(), color, board_size,
                               preset_stones, seen_positions, error_message)) {
        if (error_message.empty())
          error_message = "SGF setup stone property is invalid";
        return false;
      }
    }
  }
  std::sort(preset_stones.begin(), preset_stones.end(),
            [](const auto &left, const auto &right) {
              if (left.row != right.row)
                return left.row < right.row;
              if (left.column != right.column)
                return left.column < right.column;
              return left.color < right.color;
            });
  return true;
}

bool read_move_(const std::shared_ptr<ISgfcNode> &node,
                std::shared_ptr<ISgfcGoMove> &move, std::string &error_message);
bool append_node_(const std::shared_ptr<ISgfcNode> &node,
                  std::vector<GoCoreRecordTreeNode> &records,
                  uint64_t parent_uid, uint64_t &next_uid, int board_size,
                  bool trust_gotepad_uids, SgfNotes &notes,
                  std::string &error_message);
uint64_t first_variation_last_uid_(const GoCoreRecordTreeNode &root);

std::shared_ptr<ISgfcGoPoint>
go_point_from_(const ISgfcSinglePropertyValue *value) {
  const auto *point_value = value ? value->ToPointValue() : nullptr;
  const auto *go_point_value =
      point_value ? point_value->ToGoPointValue() : nullptr;
  return go_point_value ? go_point_value->GetGoPoint() : nullptr;
}

bool mark_coordinates_(const ISgfcGoPoint *point, int board_size, uint16_t &row,
                       uint16_t &column) {
  if (!point)
    return false;
  const auto point_column =
      point->GetXPosition(SgfcCoordinateSystem::UpperLeftOrigin);
  const auto point_row =
      point->GetYPosition(SgfcCoordinateSystem::UpperLeftOrigin);
  if (point_row < 1 || point_row > board_size || point_column < 1 ||
      point_column > board_size) {
    return false;
  }
  row = static_cast<uint16_t>(point_row);
  column = static_cast<uint16_t>(point_column);
  return true;
}

std::string read_text_(const std::shared_ptr<ISgfcNode> &node,
                       SgfcPropertyType property_type) {
  const auto property = node->GetProperty(property_type);
  const auto value = property ? property->GetPropertyValue() : nullptr;
  const auto *single_value = value ? value->ToSingleValue() : nullptr;
  return single_value ? single_value->GetRawValue() : std::string{};
}

std::string raw_property_value_(
    const std::shared_ptr<LibSgfcPlusPlus::ISgfcPropertyValue> &value) {
  if (!value)
    return {};
  if (const auto *single = value->ToSingleValue())
    return single->GetRawValue();
  const auto *composed = value->ToComposedValue();
  if (!composed)
    return {};
  const auto first = composed->GetValue1();
  const auto second = composed->GetValue2();
  return (first ? first->GetRawValue() : std::string{}) + ":" +
         (second ? second->GetRawValue() : std::string{});
}

std::vector<std::string> raw_property_values_(
    const std::shared_ptr<LibSgfcPlusPlus::ISgfcProperty> &property) {
  std::vector<std::string> values{};
  if (!property)
    return values;
  for (const auto &value : property->GetPropertyValues())
    values.push_back(raw_property_value_(value));
  return values;
}

void read_metadata_property_(const std::shared_ptr<ISgfcNode> &node,
                             SgfcPropertyType type, std::string &destination) {
  const auto property = node ? node->GetProperty(type) : nullptr;
  if (property)
    destination = read_text_(node, type);
}

bool starts_with_(std::string_view value, std::string_view prefix) {
  return value.size() >= prefix.size() &&
         value.compare(0, prefix.size(), prefix) == 0;
}

bool ends_with_(std::string_view value, std::string_view suffix) {
  return value.size() >= suffix.size() &&
         value.compare(value.size() - suffix.size(), suffix.size(), suffix) ==
             0;
}

std::string normalize_game_result_(const std::string &raw_result) {
  if (raw_result.empty() ||
      SgfcGameResult::FromPropertyValue(raw_result).IsValid)
    return raw_result;

  const std::vector<std::pair<std::string_view, std::string_view>>
      fixed_results{
          {"和棋", "0"},       {"和局", "0"},       {"平局", "0"},
          {"无胜负", "Void"},  {"無勝負", "Void"},  {"未知", "?"},
          {"黑中盘胜", "B+R"}, {"黑中盤勝", "B+R"}, {"白中盘胜", "W+R"},
          {"白中盤勝", "W+R"}, {"黑超时胜", "B+T"}, {"黑超時勝", "B+T"},
          {"白超时胜", "W+T"}, {"白超時勝", "W+T"}, {"黑弃权胜", "B+F"},
          {"黑棄權勝", "B+F"}, {"白弃权胜", "W+F"}, {"白棄權勝", "W+F"}};
  for (const auto &[source, normalized] : fixed_results) {
    if (raw_result == source)
      return std::string{normalized};
  }

  const std::vector<std::pair<std::string_view, std::string_view>> win_prefixes{
      {"黑方胜", "B+"}, {"黑方勝", "B+"}, {"黑胜", "B+"}, {"黑勝", "B+"},
      {"白方胜", "W+"}, {"白方勝", "W+"}, {"白胜", "W+"}, {"白勝", "W+"}};
  for (const auto &[source_prefix, normalized_prefix] : win_prefixes) {
    if (!starts_with_(raw_result, source_prefix))
      continue;
    std::string_view score{raw_result};
    score.remove_prefix(source_prefix.size());
    if (ends_with_(score, "目") || ends_with_(score, "子"))
      score.remove_suffix(std::string_view{"目"}.size());
    const auto normalized = std::string{normalized_prefix} + std::string{score};
    if (SgfcGameResult::FromPropertyValue(normalized).IsValid)
      return normalized;
  }
  return raw_result;
}

void read_metadata_(const std::shared_ptr<ISgfcGame> &game,
                    GoNotesSgfMetadata &metadata) {
  const auto root = game->GetRootNode();
  auto game_info_node = root;
  const auto game_info_nodes = game->GetGameInfoNodes();
  if (!game_info_nodes.empty())
    game_info_node = game_info_nodes.front();

  const auto read_game_info = [&](SgfcPropertyType type,
                                  std::string &destination) {
    read_metadata_property_(root, type, destination);
    if (game_info_node != root)
      read_metadata_property_(game_info_node, type, destination);
  };
  read_game_info(SgfcPropertyType::GN, metadata.game_name);
  read_game_info(SgfcPropertyType::EV, metadata.event);
  read_game_info(SgfcPropertyType::RO, metadata.round);
  read_game_info(SgfcPropertyType::DT, metadata.date);
  read_game_info(SgfcPropertyType::PC, metadata.place);
  read_game_info(SgfcPropertyType::RE, metadata.result);
  metadata.result = normalize_game_result_(metadata.result);
  read_game_info(SgfcPropertyType::RU, metadata.rules);
  read_game_info(SgfcPropertyType::KM, metadata.komi);
  read_game_info(SgfcPropertyType::HA, metadata.handicap);
  read_game_info(SgfcPropertyType::TM, metadata.time_limit);
  read_game_info(SgfcPropertyType::OT, metadata.overtime);
  read_game_info(SgfcPropertyType::PB, metadata.black_name);
  read_game_info(SgfcPropertyType::BR, metadata.black_rank);
  read_game_info(SgfcPropertyType::BT, metadata.black_team);
  read_game_info(SgfcPropertyType::PW, metadata.white_name);
  read_game_info(SgfcPropertyType::WR, metadata.white_rank);
  read_game_info(SgfcPropertyType::WT, metadata.white_team);
  read_game_info(SgfcPropertyType::AN, metadata.annotator);
  read_game_info(SgfcPropertyType::CP, metadata.copyright);
  read_game_info(SgfcPropertyType::SO, metadata.source);
  read_game_info(SgfcPropertyType::US, metadata.user);
  read_game_info(SgfcPropertyType::GC, metadata.game_comment);
  read_game_info(SgfcPropertyType::ON, metadata.opening);
  read_metadata_property_(root, SgfcPropertyType::ST, metadata.variation_style);
  read_metadata_property_(root, SgfcPropertyType::PL, metadata.player_to_play);

  for (const auto &property : root->GetProperties()) {
    if (!property || property->GetPropertyType() != SgfcPropertyType::Unknown)
      continue;
    const auto name = property->GetPropertyName();
    if (name != "GP" && name != "XU" && name != "XN")
      metadata.extra_root_properties[name] = raw_property_values_(property);
  }
}

std::optional<uint64_t> read_custom_uid_(const std::shared_ptr<ISgfcNode> &node,
                                         std::string &error_message) {
  const auto property = node->GetProperty("XU");
  const auto values = raw_property_values_(property);
  if (!property)
    return std::nullopt;
  if (values.size() != 1 || values.front().empty()) {
    error_message = "Gotepad XU property must contain one UID";
    return std::nullopt;
  }

  uint64_t uid{};
  const auto *begin = values.front().data();
  const auto *end = begin + values.front().size();
  const auto result = std::from_chars(begin, end, uid);
  if (result.ec != std::errc{} || result.ptr != end ||
      uid > static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) {
    error_message = "Gotepad XU property must be an integer in the int64 range";
    return std::nullopt;
  }
  return uid;
}

bool detect_gotepad_sgf_(const std::shared_ptr<ISgfcNode> &root,
                         bool &gotepad_sgf, std::string &error_message) {
  gotepad_sgf = false;
  const auto application_values =
      raw_property_values_(root->GetProperty(SgfcPropertyType::AP));
  if (application_values.size() != 1)
    return true;
  const auto &application = application_values.front();
  constexpr std::string_view kGotepadPrefix = "Gotepad:";
  if (application.size() <= kGotepadPrefix.size() ||
      application.compare(0, kGotepadPrefix.size(), kGotepadPrefix) != 0) {
    return true;
  }

  const auto profile_values = raw_property_values_(root->GetProperty("GP"));
  if (profile_values.size() != 1 || profile_values.front() != "1") {
    error_message =
        "Gotepad GP property must contain the supported profile version 1";
    return false;
  }
  gotepad_sgf = true;
  return true;
}

bool read_note_numbering_(const std::shared_ptr<ISgfcNode> &node,
                          bool gotepad_sgf, uint8_t &numbering,
                          bool &has_numbering, std::string &error_message) {
  has_numbering = false;
  if (!gotepad_sgf)
    return true;
  const auto property = node->GetProperty("XN");
  if (!property)
    return true;
  const auto values = raw_property_values_(property);
  if (values.size() != 1 || values.front().empty()) {
    error_message = "Gotepad XN property must contain one numbering option";
    return false;
  }

  unsigned int parsed_numbering{};
  const auto *begin = values.front().data();
  const auto *end = begin + values.front().size();
  const auto result = std::from_chars(begin, end, parsed_numbering);
  if (result.ec != std::errc{} || result.ptr != end ||
      parsed_numbering >= kNoteNumberingOptionCount) {
    error_message = "Gotepad XN property must be an integer from 0 to 3";
    return false;
  }
  numbering = static_cast<uint8_t>(parsed_numbering);
  has_numbering = true;
  return true;
}

int sequential_mark_index_(const std::string &label) {
  if (label.size() != 1)
    return -1;
  const auto character = static_cast<unsigned char>(label.front());
  if (character >= 'A' && character <= 'Z')
    return static_cast<int>(character - 'A');
  if (character >= 'a' && character <= 'z')
    return static_cast<int>(character - 'a') + 26;
  return -1;
}

void read_sequential_marks_(const std::shared_ptr<ISgfcNode> &node,
                            int board_size,
                            std::vector<std::pair<uint16_t, uint16_t>> &marks) {
  const auto property = node->GetProperty(SgfcPropertyType::LB);
  if (!property)
    return;

  std::vector<std::tuple<int, uint16_t, uint16_t>> indexed_marks{};
  for (const auto &value : property->GetPropertyValues()) {
    const auto *composed = value ? value->ToComposedValue() : nullptr;
    const auto point_value = composed ? composed->GetValue1() : nullptr;
    const auto label_value = composed ? composed->GetValue2() : nullptr;
    const auto label_index =
        label_value ? sequential_mark_index_(label_value->GetRawValue()) : -1;
    uint16_t row{};
    uint16_t column{};
    if (label_index >= 0 &&
        mark_coordinates_(go_point_from_(point_value.get()).get(), board_size,
                          row, column)) {
      indexed_marks.emplace_back(label_index, row, column);
    }
  }

  std::sort(indexed_marks.begin(), indexed_marks.end());
  int previous_index = -1;
  for (const auto &[index, row, column] : indexed_marks) {
    if (index == previous_index)
      continue;
    previous_index = index;
    const auto position = std::make_pair(row, column);
    if (std::find(marks.begin(), marks.end(), position) == marks.end())
      marks.push_back(position);
  }
}

void append_symbol_at_(
    uint16_t row, uint16_t column, const char *symbol,
    std::vector<std::tuple<uint16_t, uint16_t, std::string>> &marks) {
  const auto existing =
      std::find_if(marks.begin(), marks.end(), [=](const auto &mark) {
        return std::get<0>(mark) == row && std::get<1>(mark) == column;
      });
  if (existing == marks.end())
    marks.emplace_back(row, column, symbol);
}

void read_symbol_marks_(
    const std::shared_ptr<ISgfcNode> &node, int board_size,
    std::vector<std::tuple<uint16_t, uint16_t, std::string>> &marks) {
  const std::pair<SgfcPropertyType, const char *> mark_types[] = {
      {SgfcPropertyType::TR, "TR"},
      {SgfcPropertyType::SQ, "SQ"},
      {SgfcPropertyType::CR, "CR"},
      {SgfcPropertyType::MA, "MA"}};
  for (const auto &[property_type, symbol] : mark_types) {
    const auto property = node->GetProperty(property_type);
    if (!property)
      continue;
    for (const auto &value : property->GetPropertyValues()) {
      if (const auto *single = value ? value->ToSingleValue() : nullptr) {
        uint16_t row{};
        uint16_t column{};
        if (mark_coordinates_(go_point_from_(single).get(), board_size, row,
                              column))
          append_symbol_at_(row, column, symbol, marks);
        continue;
      }

      const auto *composed = value ? value->ToComposedValue() : nullptr;
      const auto first = composed ? composed->GetValue1() : nullptr;
      const auto second = composed ? composed->GetValue2() : nullptr;
      uint16_t first_row{};
      uint16_t first_column{};
      uint16_t second_row{};
      uint16_t second_column{};
      if (!mark_coordinates_(go_point_from_(first.get()).get(), board_size,
                             first_row, first_column) ||
          !mark_coordinates_(go_point_from_(second.get()).get(), board_size,
                             second_row, second_column)) {
        continue;
      }
      for (auto row = std::min(first_row, second_row);
           row <= std::max(first_row, second_row); ++row) {
        for (auto column = std::min(first_column, second_column);
             column <= std::max(first_column, second_column); ++column) {
          append_symbol_at_(row, column, symbol, marks);
        }
      }
    }
  }
}

bool append_note_(const std::shared_ptr<ISgfcNode> &node, uint64_t uid,
                  int board_size, bool gotepad_sgf, SgfNotes &notes,
                  std::string &error_message) {
  GoNotesRecord note{};
  bool has_numbering{};
  if (!read_note_numbering_(node, gotepad_sgf, note.numbering, has_numbering,
                            error_message)) {
    return false;
  }
  note.title = read_text_(node, SgfcPropertyType::N);
  note.comment = read_text_(node, SgfcPropertyType::C);
  read_sequential_marks_(node, board_size, note.sequential_marks);
  read_symbol_marks_(node, board_size, note.symbol_marks);
  if (has_numbering || !note.title.empty() || !note.comment.empty() ||
      !note.sequential_marks.empty() || !note.symbol_marks.empty()) {
    notes[uid].push_back(std::move(note));
  }
  return true;
}

bool read_move_(const std::shared_ptr<ISgfcNode> &node,
                std::shared_ptr<ISgfcGoMove> &move,
                std::string &error_message) {
  for (const auto property_type : {SgfcPropertyType::B, SgfcPropertyType::W}) {
    const auto property = node->GetProperty(property_type);
    if (!property)
      continue;
    if (move) {
      error_message = "SGF node contains more than one move";
      return false;
    }

    const auto property_value = property->GetPropertyValue();
    const auto single_value =
        std::dynamic_pointer_cast<LibSgfcPlusPlus::ISgfcSinglePropertyValue>(
            property_value);
    const auto *move_value =
        single_value ? single_value->ToMoveValue() : nullptr;
    const auto *go_move_value =
        move_value ? move_value->ToGoMoveValue() : nullptr;
    move = go_move_value ? go_move_value->GetGoMove() : nullptr;
    if (!move) {
      error_message = "SGF move property is invalid";
      return false;
    }
  }
  return true;
}

GoCoreRecordTreeNode *
find_or_append_setup_(std::vector<GoCoreRecordTreeNode> &records,
                      const std::vector<GoCorePresetStone> &preset_stones,
                      std::optional<uint64_t> specified_uid, uint64_t &next_uid,
                      std::string &error_message) {
  const auto existing =
      std::find_if(records.begin(), records.end(), [&](const auto &record) {
        return record.color == 0 && record.preset_stones == preset_stones;
      });
  if (existing != records.end()) {
    if (specified_uid && existing->uid != *specified_uid) {
      error_message = "Gotepad XU conflicts with an existing setup branch";
      return nullptr;
    }
    return &*existing;
  }
  if (!specified_uid && next_uid == std::numeric_limits<uint64_t>::max()) {
    error_message = "SGF contains too many state-changing nodes";
    return nullptr;
  }

  GoCoreRecordTreeNode record{};
  record.uid = specified_uid ? *specified_uid : next_uid++;
  record.preset_stones = preset_stones;
  records.push_back(std::move(record));
  return &records.back();
}

GoCoreRecordTreeNode *
find_or_append_move_(std::vector<GoCoreRecordTreeNode> &records, int color,
                     int row, int column, std::optional<uint64_t> specified_uid,
                     uint64_t &next_uid, std::string &error_message) {
  const auto existing =
      std::find_if(records.begin(), records.end(), [=](const auto &record) {
        return record.color == color && record.row == row &&
               record.column == column;
      });
  if (existing != records.end()) {
    if (specified_uid && existing->uid != *specified_uid) {
      error_message = "Gotepad XU conflicts with an existing move branch";
      return nullptr;
    }
    return &*existing;
  }
  if (!specified_uid && next_uid == std::numeric_limits<uint64_t>::max()) {
    error_message = "SGF contains too many state-changing nodes";
    return nullptr;
  }

  GoCoreRecordTreeNode record{};
  record.uid = specified_uid ? *specified_uid : next_uid++;
  record.color = static_cast<uint16_t>(color);
  record.row = static_cast<uint16_t>(row);
  record.column = static_cast<uint16_t>(column);
  records.push_back(std::move(record));
  return &records.back();
}

bool append_node_(const std::shared_ptr<ISgfcNode> &node,
                  std::vector<GoCoreRecordTreeNode> &records,
                  uint64_t parent_uid, uint64_t &next_uid, int board_size,
                  bool trust_gotepad_uids,
                  std::unordered_set<uint64_t> &state_uids, SgfNotes &notes,
                  std::string &error_message) {
  std::vector<GoCorePresetStone> preset_stones{};
  std::shared_ptr<ISgfcGoMove> move{};
  if (!read_setup_stones_(node, board_size, preset_stones, error_message) ||
      !read_move_(node, move, error_message)) {
    return false;
  }

  const auto changes_setup = !preset_stones.empty();
  const auto changes_move = move && !move->IsPassMove();
  if (trust_gotepad_uids && changes_setup && changes_move) {
    error_message =
        "Gotepad SGF node cannot combine setup stones and a board move";
    return false;
  }
  std::optional<uint64_t> specified_uid{};
  if (trust_gotepad_uids) {
    specified_uid = read_custom_uid_(node, error_message);
    if (!specified_uid) {
      if (error_message.empty())
        error_message = "Gotepad SGF node is missing its XU property";
      return false;
    }
    if ((changes_setup || changes_move) && *specified_uid == 0) {
      error_message = "Gotepad state-changing node cannot use XU[0]";
      return false;
    }
    if ((changes_setup || changes_move) &&
        !state_uids.insert(*specified_uid).second) {
      error_message = "Gotepad state-changing XU values must be unique";
      return false;
    }
    if (!changes_setup && !changes_move && *specified_uid != parent_uid) {
      error_message = "Gotepad note node XU does not match its parent state";
      return false;
    }
  }

  auto *continuation = &records;
  auto effective_uid = parent_uid;
  if (!preset_stones.empty()) {
    auto *setup = find_or_append_setup_(*continuation, preset_stones,
                                        specified_uid, next_uid, error_message);
    if (!setup)
      return false;
    effective_uid = setup->uid;
    continuation = &setup->children;
  }

  if (move && !move->IsPassMove()) {
    const auto point = move->GetStoneLocation();
    if (!point) {
      error_message = "SGF move has no board position";
      return false;
    }
    const auto column =
        point->GetXPosition(SgfcCoordinateSystem::UpperLeftOrigin);
    const auto row = point->GetYPosition(SgfcCoordinateSystem::UpperLeftOrigin);
    if (row < 1 || row > board_size || column < 1 || column > board_size) {
      error_message = "SGF move is outside the board";
      return false;
    }
    const auto color = move->GetPlayerColor() == SgfcColor::Black ? 1 : 2;
    auto *move_record =
        find_or_append_move_(*continuation, color, row, column, specified_uid,
                             next_uid, error_message);
    if (!move_record)
      return false;
    effective_uid = move_record->uid;
    continuation = &move_record->children;
  }

  if (!append_note_(node, effective_uid, board_size, trust_gotepad_uids, notes,
                    error_message)) {
    return false;
  }
  for (const auto &child : node->GetChildren()) {
    if (!child) {
      error_message = "SGF contains an invalid child node";
      return false;
    }
    if (!append_node_(child, *continuation, effective_uid, next_uid, board_size,
                      trust_gotepad_uids, state_uids, notes, error_message)) {
      return false;
    }
  }
  return true;
}
uint64_t first_variation_last_uid_(const GoCoreRecordTreeNode &root) {
  uint64_t last_uid = 0;
  const auto *children = &root.children;
  while (!children->empty()) {
    const auto &node = children->front();
    last_uid = node.uid;
    children = &node.children;
  }
  return last_uid;
}
} // namespace

std::unique_ptr<GoNotes> GoNotes::from_sgf_file(const std::string &path,
                                                std::string &error_message) {
  error_message.clear();
  try {
    std::string sgf_content{};
    if (!read_sgf_file_content_(path, sgf_content, error_message))
      return nullptr;

    const auto reader = SgfcPlusPlusFactory::CreateDocumentReader();
    if (reader && is_valid_utf8_(sgf_content)) {
      reader->GetArguments()->AddArgument(SgfcArgumentType::DefaultEncoding,
                                          "UTF-8");
    }
    const auto result = reader ? reader->ReadSgfContent(sgf_content) : nullptr;
    if (!result || !result->IsSgfDataValid()) {
      error_message = "Unable to read a valid SGF file";
      return nullptr;
    }

    const auto document = result->GetDocument();
    const auto game = document ? document->GetGame() : nullptr;
    if (!game || game->GetGameType() != SgfcGameType::Go ||
        !game->HasRootNode()) {
      error_message = "SGF does not contain a Go game";
      return nullptr;
    }

    const auto size = game->GetBoardSize();
    if (!size.IsSquare() || size.Rows < 1 || size.Rows > 52) {
      error_message = "SGF board must be square and between 1 and 52";
      return nullptr;
    }
    const auto board_size = static_cast<int>(size.Rows);
    auto go_notes = std::make_unique<GoNotes>(board_size);

    const auto root = game->GetRootNode();
    bool trust_gotepad_uids{};
    if (!detect_gotepad_sgf_(root, trust_gotepad_uids, error_message))
      return nullptr;
    read_metadata_(game, go_notes->sgf_metadata_);
    GoCoreRecordTreeNode tree{};
    uint64_t next_uid = 1;
    std::unordered_set<uint64_t> state_uids{};
    SgfNotes notes{};
    if (!append_node_(root, tree.children, 0, next_uid, board_size,
                      trust_gotepad_uids, state_uids, notes, error_message) ||
        go_notes->go_core_.load_record_tree(tree, {}) != 0) {
      if (error_message.empty())
        error_message =
            "SGF contains setup stones or moves that cannot be replayed";
      return nullptr;
    }
    go_notes->notes_ = std::move(notes);

    const auto final_uid =
        first_variation_last_uid_(go_notes->go_core_.record_tree());
    if (go_notes->go_core_.roaming_to(final_uid) != 0 ||
        go_notes->current_cursor_.move_current(go_notes->go_core_) != 0) {
      error_message = "Unable to select the SGF main variation";
      return nullptr;
    }
    return go_notes;
  } catch (const std::exception &error) {
    error_message = error.what();
    return nullptr;
  }
}
} // namespace nd::go
