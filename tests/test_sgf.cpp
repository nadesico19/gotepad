#include "../src/go_notes.hpp"

#include <ISgfcDocument.h>
#include <ISgfcDocumentReadResult.h>
#include <ISgfcDocumentReader.h>
#include <ISgfcGame.h>
#include <ISgfcGoMove.h>
#include <ISgfcGoMovePropertyValue.h>
#include <ISgfcGoPoint.h>
#include <ISgfcMovePropertyValue.h>
#include <ISgfcNode.h>
#include <ISgfcProperty.h>
#include <ISgfcSinglePropertyValue.h>
#include <SgfcColor.h>
#include <SgfcCoordinateSystem.h>
#include <SgfcExitCode.h>
#include <SgfcPlusPlusFactory.h>
#include <SgfcPropertyType.h>

#include <cassert>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {
using Notes = nd::go::GoNotes;
using namespace LibSgfcPlusPlus;

constexpr int Black = 1;
constexpr int White = 2;
size_t skipped_fixture_tests{};

std::optional<std::filesystem::path>
resolve_sgf_fixture(const std::filesystem::path &relative_path,
                    const char *test_name) {
  namespace filesystem = std::filesystem;
  for (const auto &candidate :
       {relative_path, filesystem::u8path("..") / relative_path}) {
    if (filesystem::exists(candidate))
      return candidate;
  }
  ++skipped_fixture_tests;
  std::cout << "[ SKIPPED ] " << test_name << ": SGF fixture not found: "
            << relative_path.u8string() << '\n';
  return std::nullopt;
}

void dump_board(std::ofstream &out, const std::string &title,
                const Notes &go_notes) {
  out << "\n===== " << title << " =====\n";
  for (size_t row = 1; row <= static_cast<size_t>(go_notes.board_size());
       ++row) {
    for (size_t column = 1;
         column <= static_cast<size_t>(go_notes.board_size()); ++column) {
      out << go_notes.state_at(row, column);
      if (column != static_cast<size_t>(go_notes.board_size()))
        out << ' ';
    }
    out << '\n';
  }
}

void expect_true(bool condition, const char *message) {
  if (!condition) {
    std::cerr << message << '\n';
    assert(condition);
  }
}

void expect_eq(int actual, int expected, const char *message) {
  if (actual != expected) {
    std::cerr << message << ": expected " << expected << ", actual " << actual
              << '\n';
    assert(actual == expected);
  }
}

std::ofstream open_output_file() {
  const char *output_path = "tests/test_sgf_1.txt";
  std::ofstream out{output_path};
  if (!out) {
    output_path = "../tests/test_sgf_1.txt";
    out.clear();
    out.open(output_path);
  }
  if (!out) {
    std::cerr << "cannot open test_sgf_1.txt\n";
    return {};
  }
  out << "output: " << output_path << '\n';
  return out;
}

std::shared_ptr<ISgfcDocument> read_sgf_document(const std::string &path) {
  const auto reader = SgfcPlusPlusFactory::CreateDocumentReader();
  const auto result = reader->ReadSgfFile(path);
  expect_true(result != nullptr, "SGF read result is null");
  expect_true(result->GetExitCode() != SgfcExitCode::FatalError,
              "SGF reader reported a fatal error");
  expect_true(result->GetDocument() != nullptr, "SGF document is null");
  return result->GetDocument();
}

const ISgfcGoMovePropertyValue *
go_move_value_from_node(const std::shared_ptr<ISgfcNode> &node,
                        SgfcPropertyType property_type) {
  const auto property = node->GetProperty(property_type);
  if (!property)
    return nullptr;

  const auto property_value = property->GetPropertyValue();
  if (!property_value)
    return nullptr;

  const auto single_value =
      std::dynamic_pointer_cast<ISgfcSinglePropertyValue>(property_value);
  if (!single_value)
    return nullptr;

  const auto move_value = single_value->ToMoveValue();
  if (!move_value)
    return nullptr;

  return move_value->ToGoMoveValue();
}

int color_to_go_core(SgfcColor color) {
  return color == SgfcColor::Black ? Black : White;
}

void replay_move(Notes &go_notes, std::ofstream &out,
                 const std::shared_ptr<ISgfcGoMove> &move, size_t move_number,
                 std::vector<std::pair<size_t, size_t>> &captured_positions) {
  expect_true(move != nullptr, "SGF move is null");

  const int color = color_to_go_core(move->GetPlayerColor());
  if (move->IsPassMove()) {
    out << "move " << move_number << ": color=" << color << ", pass\n";
    dump_board(out, "SGF move " + std::to_string(move_number) + ": pass",
               go_notes);
    return;
  }

  const auto point = move->GetStoneLocation();
  expect_true(point != nullptr, "SGF move point is null");

  const auto column = static_cast<size_t>(
      point->GetXPosition(SgfcCoordinateSystem::UpperLeftOrigin));
  const auto row = static_cast<size_t>(
      point->GetYPosition(SgfcCoordinateSystem::UpperLeftOrigin));
  std::vector<int> states_before;
  states_before.reserve(19 * 19);
  for (size_t board_row = 1; board_row <= 19; ++board_row) {
    for (size_t board_column = 1; board_column <= 19; ++board_column) {
      states_before.push_back(go_notes.state_at(board_row, board_column));
    }
  }

  const int result = go_notes.execute(
      std::make_unique<nd::go::GoNotes::PlaceStoneCommand>(color, row, column));

  out << "move " << move_number << ": color=" << color << ", row=" << row
      << ", column=" << column << ", result=" << result << '\n';
  expect_eq(
      result, 0,
      ("SGF move " + std::to_string(move_number) + " should be legal").c_str());

  size_t state_index = 0;
  for (size_t board_row = 1; board_row <= 19; ++board_row) {
    for (size_t board_column = 1; board_column <= 19;
         ++board_column, ++state_index) {
      if (states_before[state_index] != 0 &&
          go_notes.state_at(board_row, board_column) == 0) {
        captured_positions.emplace_back(board_row, board_column);
      }
    }
  }
  dump_board(out, "SGF move " + std::to_string(move_number), go_notes);
}

void test_find_command(
    Notes &go_notes, std::ofstream &out,
    const std::vector<std::pair<size_t, size_t>> &captured_positions) {
  const auto final_uid = go_notes.current_uid();

  std::pair<size_t, size_t> occupied_position{};
  for (size_t row = 1; row <= 19 && occupied_position.first == 0; ++row) {
    for (size_t column = 1; column <= 19; ++column) {
      if (go_notes.state_at(row, column) != 0) {
        occupied_position = {row, column};
        break;
      }
    }
  }
  expect_true(occupied_position.first != 0,
              "final SGF position has no stone to find");

  std::pair<size_t, size_t> captured_empty_position{};
  for (auto position : captured_positions) {
    if (go_notes.state_at(position.first, position.second) == 0) {
      captured_empty_position = position;
      break;
    }
  }
  expect_true(captured_empty_position.first != 0,
              "final SGF position has no captured empty point to find");

  expect_eq(go_notes.execute(std::make_unique<nd::go::GoNotes::FindCommand>(
                occupied_position.first, occupied_position.second)),
            0, "find command should roam to an occupied point's move");
  expect_true(go_notes.current_node().row == occupied_position.first &&
                  go_notes.current_node().column == occupied_position.second,
              "find command should stop at the occupied point's move record");
  expect_true(
      go_notes.state_at(occupied_position.first, occupied_position.second) != 0,
      "occupied point should contain its stone after find roaming");
  dump_board(
      out,
      "find occupied point: row=" + std::to_string(occupied_position.first) +
          ", column=" + std::to_string(occupied_position.second),
      go_notes);
  expect_eq(go_notes.undo(), 0,
            "undo occupied-point find should restore final position");
  expect_true(go_notes.current_uid() == final_uid,
              "undo should restore final SGF uid");

  expect_eq(go_notes.execute(std::make_unique<nd::go::GoNotes::FindCommand>(
                captured_empty_position.first, captured_empty_position.second)),
            0, "find command should roam to a captured stone's move");
  expect_true(go_notes.current_node().row == captured_empty_position.first &&
                  go_notes.current_node().column ==
                      captured_empty_position.second,
              "find command should stop at the captured stone's move record");
  expect_true(
      go_notes.state_at(captured_empty_position.first,
                        captured_empty_position.second) != 0,
      "captured point should contain its former stone after find roaming");
  dump_board(out,
             "find captured point: row=" +
                 std::to_string(captured_empty_position.first) +
                 ", column=" + std::to_string(captured_empty_position.second),
             go_notes);
  expect_eq(go_notes.undo(), 0,
            "undo captured-point find should restore final position");
  expect_true(go_notes.current_uid() == final_uid,
              "second undo should restore final SGF uid");

  expect_eq(
      go_notes.execute(std::make_unique<nd::go::GoNotes::FindCommand>(0, 0)),
      -1, "find command should reject a position with no move record");
  expect_true(go_notes.current_uid() == final_uid,
              "failed find should keep the final SGF position");
  expect_true(go_notes.message() == nd::go::kStoneNotFoundMessage,
              "failed find should report that no move was found");
}

void test_sgf_preset_stones() {
  const auto path = resolve_sgf_fixture(
      std::filesystem::u8path("tests/test_sgf_preset.sgf"),
      "preset stones");
  if (!path)
    return;

  std::string error_message{};
  auto go_notes = Notes::from_sgf_file(path->u8string(), error_message);
  expect_true(go_notes != nullptr, error_message.c_str());
  expect_eq(go_notes->board_size(), 9,
            "preset SGF should retain its board size");
  expect_eq(go_notes->state_at(3, 3), Black,
            "preset SGF should load the first black setup stone");
  expect_eq(go_notes->state_at(4, 3), Black,
            "preset SGF should expand compressed setup stones");
  expect_eq(go_notes->state_at(7, 7), Black,
            "preset SGF should load the last black setup stone");
  expect_eq(go_notes->state_at(7, 3), White,
            "preset SGF should load the first white setup stone");
  expect_eq(go_notes->state_at(3, 7), White,
            "preset SGF should load the second white setup stone");
  expect_eq(go_notes->state_at(5, 5), Black,
            "preset SGF should replay the first formal move");
  expect_eq(go_notes->state_at(6, 5), White,
            "preset SGF should select the first variation");

  const auto root = go_notes->node_at(0);
  expect_true(root.has_value(), "preset SGF should expose its virtual root");
  expect_true(root->children.size() == 1,
              "preset SGF should have one recorded setup root child");
  const auto &setup = root->children.front();
  expect_true(setup.color == 0,
              "preset SGF root child should be a setup record");
  expect_true(setup.row == 0 && setup.column == 0,
              "preset SGF setup record should not expose a move point");
  expect_true(setup.preset_stones.size() == 5,
              "preset SGF setup record should contain all expanded stones");

  expect_eq(go_notes->execute("ROAMING,0;"), 0,
            "preset SGF should roam to its empty virtual root");
  expect_eq(go_notes->state_at(3, 3), 0,
            "virtual root should not contain black setup stones");
  expect_eq(go_notes->state_at(7, 3), 0,
            "virtual root should not contain white setup stones");
  expect_eq(go_notes->state_at(5, 5), 0,
            "formal moves should be absent at the virtual root");

  expect_eq(go_notes->execute("ROAMING," + std::to_string(setup.uid) + ";"), 0,
            "preset SGF should roam to its recorded setup node");
  expect_eq(go_notes->state_at(3, 3), Black,
            "setup node should restore the first black stone");
  expect_eq(go_notes->state_at(7, 3), White,
            "setup node should restore the first white stone");
  expect_eq(go_notes->state_at(5, 5), 0,
            "setup node should not include formal moves");
  expect_eq(go_notes->state_at(6, 5), 0,
            "setup node should not include variation moves");
}

void diagnose_multigo_setup_nodes(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto path = resolve_sgf_fixture(
      filesystem::u8path("tests/01 星 挂 飞守 飞角.sgf"),
      "MultiGo setup-node diagnostics");
  if (!path)
    return;

  std::ifstream input{*path, std::ios::binary};
  expect_true(static_cast<bool>(input), "MultiGo SGF fixture cannot be opened");
  const std::string content{std::istreambuf_iterator<char>{input},
                            std::istreambuf_iterator<char>{}};
  const auto reader = SgfcPlusPlusFactory::CreateDocumentReader();
  const auto result = reader->ReadSgfContent(content);
  expect_true(result != nullptr, "MultiGo SGF read result is null");
  expect_true(result->IsSgfDataValid(), "MultiGo SGF data is invalid");
  const auto document = result->GetDocument();
  const auto game = document ? document->GetGame() : nullptr;
  const auto root = game && game->HasRootNode() ? game->GetRootNode() : nullptr;
  expect_true(root != nullptr, "MultiGo SGF root node is missing");

  struct PendingNode {
    std::shared_ptr<ISgfcNode> node{};
    size_t depth{};
    bool is_root{};
    bool under_setup_subtree{};
  };
  std::vector<PendingNode> pending{{root, 0, true, false}};
  size_t pending_index = 0;
  size_t node_count = 0;
  size_t non_root_setup_count = 0;
  size_t add_black_count = 0;
  size_t add_white_count = 0;
  size_t clear_count = 0;
  size_t pass_count = 0;
  size_t pruned_node_count = 0;
  size_t first_setup_depth = 0;
  bool first_setup_found = false;
  while (pending_index < pending.size()) {
    const auto current = pending[pending_index++];
    ++node_count;
    const bool has_ab =
        current.node->GetProperty(SgfcPropertyType::AB) != nullptr;
    const bool has_aw =
        current.node->GetProperty(SgfcPropertyType::AW) != nullptr;
    const bool has_ae =
        current.node->GetProperty(SgfcPropertyType::AE) != nullptr;
    const bool begins_setup_subtree =
        !current.is_root && (has_ab || has_aw || has_ae);
    const bool under_setup_subtree =
        current.under_setup_subtree || begins_setup_subtree;
    if (under_setup_subtree)
      ++pruned_node_count;
    if (begins_setup_subtree) {
      ++non_root_setup_count;
      add_black_count += has_ab ? 1 : 0;
      add_white_count += has_aw ? 1 : 0;
      clear_count += has_ae ? 1 : 0;
      if (!first_setup_found) {
        first_setup_found = true;
        first_setup_depth = current.depth;
      }
    }
    for (const auto property_type :
         {SgfcPropertyType::B, SgfcPropertyType::W}) {
      const auto *move_value =
          go_move_value_from_node(current.node, property_type);
      const auto move = move_value ? move_value->GetGoMove() : nullptr;
      if (move && move->IsPassMove())
        ++pass_count;
    }
    for (const auto &child : current.node->GetChildren())
      pending.push_back({child, current.depth + 1, false, under_setup_subtree});
  }

  struct ReplayResult {
    bool succeeded{};
    size_t pruned_subtrees{};
    size_t failure_depth{};
    uint64_t failure_parent_uid{};
    int failure_color{};
    int failure_row{};
    int failure_column{};
    std::string failure_message{};
  };
  auto replay = [&](bool prune_setup_subtrees) {
    Notes notes{19};
    ReplayResult replay_result{};
    std::function<bool(const std::shared_ptr<ISgfcNode> &, size_t, bool)>
        replay_node;
    replay_node = [&](const std::shared_ptr<ISgfcNode> &node, size_t depth,
                      bool is_root) {
      const bool has_setup =
          node->GetProperty(SgfcPropertyType::AB) != nullptr ||
          node->GetProperty(SgfcPropertyType::AW) != nullptr ||
          node->GetProperty(SgfcPropertyType::AE) != nullptr;
      if (!is_root && has_setup && prune_setup_subtrees) {
        ++replay_result.pruned_subtrees;
        return true;
      }

      for (const auto property_type :
           {SgfcPropertyType::B, SgfcPropertyType::W}) {
        const auto *move_value = go_move_value_from_node(node, property_type);
        const auto move = move_value ? move_value->GetGoMove() : nullptr;
        if (!move || move->IsPassMove())
          continue;
        const auto point = move->GetStoneLocation();
        if (!point)
          continue;
        const int column =
            point->GetXPosition(SgfcCoordinateSystem::UpperLeftOrigin);
        const int row =
            point->GetYPosition(SgfcCoordinateSystem::UpperLeftOrigin);
        const int color = color_to_go_core(move->GetPlayerColor());
        const auto parent_uid = notes.current_uid();
        auto command = std::make_unique<Notes::PlaceStoneCommand>(
            color, static_cast<size_t>(row), static_cast<size_t>(column));
        if (notes.execute(std::move(command)) != 0) {
          replay_result.failure_depth = depth;
          replay_result.failure_parent_uid = parent_uid;
          replay_result.failure_color = color;
          replay_result.failure_row = row;
          replay_result.failure_column = column;
          replay_result.failure_message = notes.message();
          return false;
        }
      }

      const auto node_uid = notes.current_uid();
      for (const auto &child : node->GetChildren()) {
        if (!replay_node(child, depth + 1, false))
          return false;
        if (notes.current_uid() != node_uid &&
            notes.execute(std::make_unique<Notes::RoamingCommand>(node_uid)) !=
                0) {
          replay_result.failure_depth = depth;
          replay_result.failure_parent_uid = node_uid;
          replay_result.failure_message = notes.message();
          return false;
        }
      }
      return true;
    };
    replay_result.succeeded = replay_node(root, 0, true);
    return replay_result;
  };
  const auto ignored_setup_replay = replay(false);
  const auto pruned_setup_replay = replay(true);

  std::string error_message{};
  const auto go_notes = Notes::from_sgf_file(path->u8string(), error_message);
  size_t loaded_setup_nodes = 0;
  if (go_notes) {
    std::vector<uint64_t> loaded_pending{0};
    size_t loaded_index = 0;
    while (loaded_index < loaded_pending.size()) {
      const auto loaded_node =
          go_notes->node_at(loaded_pending[loaded_index++]);
      expect_true(loaded_node.has_value(),
                  "loaded MultiGo node should remain addressable");
      if (loaded_node->uid != 0 && loaded_node->color == 0)
        ++loaded_setup_nodes;
      for (const auto &child : loaded_node->children)
        loaded_pending.push_back(child.uid);
    }
  }
  out << "\n===== MultiGo setup-node diagnostics =====\n"
      << "path=" << path->u8string() << '\n'
      << "node_count=" << node_count << '\n'
      << "non_root_setup_nodes=" << non_root_setup_count << '\n'
      << "nodes_with_AB=" << add_black_count << '\n'
      << "nodes_with_AW=" << add_white_count << '\n'
      << "nodes_with_AE=" << clear_count << '\n'
      << "pass_moves=" << pass_count << '\n'
      << "first_non_root_setup_depth=" << first_setup_depth << '\n'
      << "ignored_setup_replay_succeeded=" << ignored_setup_replay.succeeded
      << '\n'
      << "ignored_setup_first_failure_depth="
      << ignored_setup_replay.failure_depth << '\n'
      << "ignored_setup_failure_parent_uid="
      << ignored_setup_replay.failure_parent_uid << '\n'
      << "ignored_setup_failure_move=" << ignored_setup_replay.failure_color
      << ',' << ignored_setup_replay.failure_row << ','
      << ignored_setup_replay.failure_column << '\n'
      << "ignored_setup_failure_message="
      << ignored_setup_replay.failure_message << '\n'
      << "pruned_setup_replay_succeeded=" << pruned_setup_replay.succeeded
      << '\n'
      << "pruned_setup_subtrees=" << pruned_setup_replay.pruned_subtrees << '\n'
      << "pruned_setup_nodes=" << pruned_node_count << '\n'
      << "loaded_setup_nodes=" << loaded_setup_nodes << '\n'
      << "go_notes_loaded=" << static_cast<bool>(go_notes) << '\n'
      << "go_notes_error=" << error_message << '\n';
  out.flush();

  expect_true(non_root_setup_count > 0,
              "MultiGo fixture should contain non-root setup nodes");
  expect_true(!ignored_setup_replay.succeeded,
              "ignoring non-root setup should not replay faithfully");
  expect_true(pruned_setup_replay.succeeded,
              "pruning non-root setup subtrees should preserve valid branches");
  expect_true(go_notes != nullptr,
              "MultiGo fixture should load with all setup subtrees");
  expect_true(loaded_setup_nodes > 0,
              "MultiGo fixture should retain non-root setup nodes");
  expect_eq(go_notes->board_size(), 19,
            "MultiGo fixture should retain its board size");
}
void test_unicode_sgf_path(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto source_path = resolve_sgf_fixture(
      filesystem::u8path("tests/秀策vs服部正彻.sgf"), "Unicode SGF path");
  if (!source_path)
    return;

  std::string error_message{};
  const auto go_notes =
      Notes::from_sgf_file(source_path->u8string(), error_message);
  expect_true(go_notes != nullptr, error_message.c_str());
  expect_eq(go_notes->board_size(), 19,
            "Unicode-path SGF should retain its board size");
  out << "\nUnicode-path SGF loaded successfully: " << source_path->u8string()
      << '\n';
}

void test_localized_game_result_normalization(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto source_path = resolve_sgf_fixture(
      filesystem::u8path("gotepad-gd/1985-11-20 聂卫平 (黑)Vs(白) 藤泽秀行_"
                         "第一届中日擂台赛第十五局主将决战.sgf"),
      "localized game result normalization");
  if (!source_path)
    return;

  std::string error_message{};
  const auto notes =
      Notes::from_sgf_file(source_path->u8string(), error_message);
  expect_true(notes != nullptr, error_message.c_str());
  expect_true(notes->sgf_metadata().result == "B+3.5",
              "Localized RE should be normalized to SGF format");

  auto temporary_directory = filesystem::u8path(".tmp");
  if (!filesystem::exists(temporary_directory))
    temporary_directory = filesystem::u8path("../.tmp");
  filesystem::create_directories(temporary_directory);
  const auto saved_path =
      temporary_directory / "localized_result_roundtrip.sgf";
  expect_true(notes->save_sgf_file(saved_path.u8string(), error_message),
              error_message.c_str());

  std::ifstream saved_file(saved_path, std::ios::binary);
  const std::string saved_content{std::istreambuf_iterator<char>(saved_file),
                                  std::istreambuf_iterator<char>()};
  expect_true(saved_content.find("RE[B+3.5]") != std::string::npos,
              "Saved SGF should contain normalized RE[B+3.5]");
  out << "\nLocalized SGF result normalized and saved successfully: "
      << saved_path.u8string() << '\n';
}

bool same_record_tree(const Notes &left_notes, const Notes &right_notes,
                      uint64_t uid) {
  const auto left_value = left_notes.node_at(uid);
  const auto right_value = right_notes.node_at(uid);
  if (!left_value || !right_value)
    return false;
  const auto &left = *left_value;
  const auto &right = *right_value;
  if (left.uid != right.uid || left.color != right.color ||
      left.row != right.row || left.column != right.column ||
      left.preset_stones != right.preset_stones ||
      left.children.size() != right.children.size()) {
    return false;
  }
  for (size_t index = 0; index < left.children.size(); ++index) {
    if (left.children[index].uid != right.children[index].uid ||
        !same_record_tree(left_notes, right_notes, left.children[index].uid))
      return false;
  }
  return true;
}

void collect_uids(const Notes &notes, uint64_t uid,
                  std::vector<uint64_t> &uids) {
  const auto node = notes.node_at(uid);
  expect_true(node.has_value(), "Record UID should exist");
  uids.push_back(uid);
  for (const auto &child : node->children)
    collect_uids(notes, child.uid, uids);
}

void test_gotepad_sgf_roundtrip(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto source_path = resolve_sgf_fixture(
      filesystem::u8path("gotepad-gd/920-shadow-yfh2-mamor.sgf"),
      "Gotepad SGF roundtrip");
  if (!source_path)
    return;

  std::string error_message{};
  const auto original =
      Notes::from_sgf_file(source_path->u8string(), error_message);
  expect_true(original != nullptr, error_message.c_str());
  expect_true(!original->notes_at(0).empty(),
              "SGF root comment should load as a note");
  expect_eq(original->execute(std::make_unique<Notes::RoamingCommand>(0)), 0,
            "Should roam to the root note");
  expect_eq(
      original->execute(std::make_unique<Notes::UpdateNoteNumbering>(0, 2)), 0,
      "Should update the note numbering mode");

  auto temporary_directory = filesystem::u8path(".tmp");
  if (!filesystem::exists(temporary_directory))
    temporary_directory = filesystem::u8path("../.tmp");
  filesystem::create_directories(temporary_directory);
  const auto saved_path =
      temporary_directory / filesystem::u8path("sgf_roundtrip.sgf");
  expect_true(original->save_sgf_file(saved_path.u8string(), error_message),
              error_message.c_str());

  std::ifstream saved_file(saved_path, std::ios::binary);
  const std::string saved_content{std::istreambuf_iterator<char>(saved_file),
                                  std::istreambuf_iterator<char>()};
  expect_true(saved_content.find("GP[1]") != std::string::npos,
              "Saved SGF should contain GP[1]");
  expect_true(saved_content.find("XU[0]") != std::string::npos,
              "Saved SGF root should contain XU[0]");
  expect_true(saved_content.find("AP[Gotepad:0.1.7]") != std::string::npos,
              "Saved SGF should identify Gotepad as its application");

  const auto restored =
      Notes::from_sgf_file(saved_path.u8string(), error_message);
  expect_true(restored != nullptr, error_message.c_str());
  expect_true(
      same_record_tree(*original, *restored, 0),
      "SGF roundtrip should preserve the complete record tree and UIDs");

  const auto &original_metadata = original->sgf_metadata();
  const auto &restored_metadata = restored->sgf_metadata();
  expect_true(restored_metadata.game_name == original_metadata.game_name,
              "SGF roundtrip should preserve GN");
  expect_true(restored_metadata.black_name == original_metadata.black_name,
              "SGF roundtrip should preserve PB");
  expect_true(restored_metadata.white_name == original_metadata.white_name,
              "SGF roundtrip should preserve PW");
  expect_true(restored_metadata.komi == original_metadata.komi,
              "SGF roundtrip should preserve KM");

  std::vector<uint64_t> uids{};
  collect_uids(*original, 0, uids);
  size_t original_note_count{};
  size_t restored_note_count{};
  size_t original_mark_count{};
  size_t restored_mark_count{};
  for (const auto uid : uids) {
    const auto original_notes = original->notes_at(uid);
    const auto restored_notes = restored->notes_at(uid);
    original_note_count += original_notes.size();
    restored_note_count += restored_notes.size();
    for (const auto &note : original_notes)
      original_mark_count +=
          note.sequential_marks.size() + note.symbol_marks.size();
    for (const auto &note : restored_notes)
      restored_mark_count +=
          note.sequential_marks.size() + note.symbol_marks.size();
  }
  expect_true(restored_note_count == original_note_count,
              "SGF roundtrip should preserve all notes");
  expect_true(restored_mark_count == original_mark_count,
              "SGF roundtrip should preserve all supported marks");
  expect_eq(restored->notes_at(0).front().numbering, 2,
            "SGF roundtrip should preserve note numbering");
  out << "\nGotepad SGF roundtrip saved to " << saved_path.u8string() << '\n';
}

void test_safe_sgf_save_recovery(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  auto temporary_directory = filesystem::u8path(".tmp");
  if (!filesystem::exists(temporary_directory))
    temporary_directory = filesystem::u8path("../.tmp");
  filesystem::create_directories(temporary_directory);
  const auto target = temporary_directory / filesystem::u8path("safe_save.sgf");
  const auto temporary_path = [&](const std::string &suffix) {
    const auto temporary_name = "." + target.filename().u8string() +
                                ".gotepad-" + suffix + ".tmp";
    return target.parent_path() / filesystem::u8path(temporary_name);
  };
  const auto staging = temporary_path("writing");
  const auto backup = temporary_path("backup");

  filesystem::remove(target);
  {
    std::ofstream backup_file(backup, std::ios::binary | std::ios::trunc);
    backup_file << "original SGF backup";
  }
  {
    std::ofstream staging_file(staging, std::ios::binary | std::ios::trunc);
    staging_file << "incomplete SGF write";
  }

  Notes notes{9};
  std::string error_message{};
  expect_true(notes.save_sgf_file(target.u8string(), error_message),
              error_message.c_str());
  expect_true(filesystem::exists(target), "Safely saved SGF should exist");
  expect_true(!filesystem::exists(staging),
              "Successful SGF save should remove its staging file");
  expect_true(!filesystem::exists(backup),
              "Successful SGF save should remove its recovery backup");
  const auto restored = Notes::from_sgf_file(target.u8string(), error_message);
  expect_true(restored != nullptr,
              "Safely saved SGF should remain readable after recovery");
  out << "\nSafe SGF save recovered stale temporary files successfully.\n";
}

void test_wrongtest_sgf_loads(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto path = resolve_sgf_fixture(
      filesystem::u8path("tests/wrongtest.sgf"), "wrongtest SGF loading");
  if (!path)
    return;

  std::string error_message{};
  const auto go_notes = Notes::from_sgf_file(path->u8string(), error_message);
  if (!go_notes)
    std::cerr << "wrongtest.sgf load error: " << error_message << '\n';
  expect_true(go_notes != nullptr, "wrongtest.sgf should load successfully");
  out << "\nwrongtest.sgf loaded successfully.\n";
}

void test_invalid_property_identifier_recovery(std::ofstream &out) {
  namespace filesystem = std::filesystem;
  const auto source_path = resolve_sgf_fixture(
      filesystem::u8path(
          "tests/[柯洁]vs[福冈航太朗]1779632643010001326.sgf"),
      "invalid property identifier recovery");
  if (!source_path)
    return;

  std::string error_message{};
  const auto notes =
      Notes::from_sgf_file(source_path->u8string(), error_message);
  expect_true(notes != nullptr, error_message.c_str());
  bool reported_identifier_recovery{};
  for (const auto code : notes->sgf_import_recovery_codes()) {
    if (code == nd::go::GoNotesSgfImportRecoveryCode::
                    InvalidPropertyIdentifierSanitized) {
      reported_identifier_recovery = true;
      break;
    }
  }
  expect_true(reported_identifier_recovery,
              "SGF import should report repaired property identifiers");

  auto temporary_directory = filesystem::u8path(".tmp");
  if (!filesystem::exists(temporary_directory))
    temporary_directory = filesystem::u8path("../.tmp");
  filesystem::create_directories(temporary_directory);
  const auto saved_path =
      temporary_directory / "property_identifier_recovery.sgf";
  expect_true(notes->save_sgf_file(saved_path.u8string(), error_message),
              error_message.c_str());
  const auto restored =
      Notes::from_sgf_file(saved_path.u8string(), error_message);
  expect_true(restored != nullptr, error_message.c_str());
  expect_true(restored->sgf_import_recovery_codes().empty(),
              "Saved SGF should contain only valid property identifiers");
  out << "\nInvalid SGF property identifiers recovered successfully.\n";
}

bool has_recovery_code(const Notes &notes,
                       nd::go::GoNotesSgfImportRecoveryCode expected) {
  for (const auto code : notes.sgf_import_recovery_codes()) {
    if (code == expected)
      return true;
  }
  return false;
}

void test_analysis_metadata_recovery(std::ofstream &out) {
  using RecoveryCode = nd::go::GoNotesSgfImportRecoveryCode;
  std::string error_message{};

  const auto missing = Notes::from_sgf_content(
      "(;FF[4]GM[1]CA[UTF-8]SZ[9])", error_message);
  expect_true(missing != nullptr, error_message.c_str());
  expect_true(missing->sgf_metadata().rules == "Chinese",
              "Missing SGF rules should default to Chinese");
  expect_true(missing->sgf_metadata().komi == "7.5",
              "Missing SGF komi should default to 7.5");

  const auto valid = Notes::from_sgf_content(
      "(;FF[4]GM[1]CA[UTF-8]SZ[9]RU[Korean]KM[99.5])", error_message);
  expect_true(valid != nullptr, error_message.c_str());
  expect_true(valid->sgf_metadata().rules == "Korean",
              "Recognized KataGo rules should be preserved");
  expect_true(valid->sgf_metadata().komi == "99.5",
              "Large half-point komi should remain valid");

  const auto invalid = Notes::from_sgf_content(
      "(;FF[4]GM[1]CA[UTF-8]SZ[9]RU[Unknown Rules]KM[375])",
      error_message);
  expect_true(invalid != nullptr, error_message.c_str());
  expect_true(invalid->sgf_metadata().rules == "Chinese",
              "Unrecognized rules should default to Chinese");
  expect_true(invalid->sgf_metadata().komi == "7.5",
              "Out-of-range komi should default to 7.5");
  expect_true(has_recovery_code(*invalid, RecoveryCode::InvalidRulesDefaulted),
              "Invalid rules should produce a recovery code");
  expect_true(has_recovery_code(*invalid, RecoveryCode::InvalidKomiDefaulted),
              "Invalid komi should produce a recovery code");

  const auto subunit = Notes::from_sgf_content(
      "(;FF[4]GM[1]CA[UTF-8]SZ[9]RU[Chinese]KM[3.75])", error_message);
  expect_true(subunit != nullptr, error_message.c_str());
  expect_true(subunit->sgf_metadata().komi == "7.5",
              "Quarter-point komi should default to 7.5");
  expect_true(has_recovery_code(*subunit, RecoveryCode::SubunitKomiDefaulted),
              "Quarter-point komi should report a unit warning");
  out << "\nSGF analysis metadata defaults and validation succeeded.\n";
}

void replay_sgf_main_variation(std::ofstream &out) {
  const auto path = resolve_sgf_fixture(
      std::filesystem::u8path("tests/test_sgf_1.sgf"),
      "SGF main variation replay");
  if (!path)
    return;
  const auto document = read_sgf_document(path->u8string());
  const auto games = document->GetGames();
  expect_true(!games.empty(), "SGF document contains no games");

  const auto game = games.front();
  expect_true(game != nullptr, "SGF game is null");

  const auto root = game->GetRootNode();
  expect_true(root != nullptr, "SGF root node is null");

  Notes go_notes{19};
  dump_board(out, "SGF: initial 19x19 board", go_notes);

  size_t move_number = 0;
  std::vector<std::pair<size_t, size_t>> captured_positions;
  for (const auto &node : root->GetMainVariationNodes()) {
    const auto black_value = go_move_value_from_node(node, SgfcPropertyType::B);
    const auto white_value = go_move_value_from_node(node, SgfcPropertyType::W);

    if (black_value) {
      replay_move(go_notes, out, black_value->GetGoMove(), ++move_number,
                  captured_positions);
    }
    if (white_value) {
      replay_move(go_notes, out, white_value->GetGoMove(), ++move_number,
                  captured_positions);
    }
  }

  out << "\nReplayed " << move_number << " SGF moves.\n";
  expect_true(move_number > 0, "SGF main variation contains no moves");
  test_find_command(go_notes, out, captured_positions);
}
} // namespace

int main() {
  auto out = open_output_file();
  if (!out)
    return 1;

  diagnose_multigo_setup_nodes(out);
  test_unicode_sgf_path(out);
  test_localized_game_result_normalization(out);
  test_gotepad_sgf_roundtrip(out);
  test_safe_sgf_save_recovery(out);
  test_wrongtest_sgf_loads(out);
  test_invalid_property_identifier_recovery(out);
  test_analysis_metadata_recovery(out);
  test_sgf_preset_stones();
  replay_sgf_main_variation(out);

  out << "\nAll available SGF replay tests passed. Skipped missing fixtures: "
      << skipped_fixture_tests << ".\n";
  return 0;
}
