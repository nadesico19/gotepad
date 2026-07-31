#include "../src/go_core.hpp"

#include <cassert>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <map>
#include <string>

namespace {
using Board = nd::go::GoCore;
using TreeNode = nd::go::GoCoreRecordTreeNode;

constexpr int Black = 1;
constexpr int White = 2;
using MoveLabels = std::map<uint64_t, std::string>;

void dump_board(std::ofstream &out, const std::string &title, Board &board) {
  out << "\n===== " << title << " =====\n";
  board.text_output(out);
}

void expect_eq(int actual, int expected, const char *message) {
  if (actual != expected) {
    std::cerr << message << ": expected " << expected << ", actual " << actual
              << '\n';
    assert(actual == expected);
  }
}

uint64_t max_uid(const TreeNode &node) {
  uint64_t result = node.uid;
  for (const auto &child : node.children) {
    const auto child_max = max_uid(child);
    if (child_max > result)
      result = child_max;
  }
  return result;
}

uint64_t newest_uid(Board &board) { return max_uid(board.record_tree()); }

bool same_record_tree_shape(const TreeNode &left, const TreeNode &right) {
  if (left.color != right.color || left.row != right.row ||
      left.column != right.column ||
      left.preset_stones != right.preset_stones)
    return false;
  if (left.children.size() != right.children.size())
    return false;

  for (size_t index = 0; index < left.children.size(); ++index) {
    if (!same_record_tree_shape(left.children[index], right.children[index]))
      return false;
  }

  return true;
}

void dump_record_tree_node(std::ofstream &out, const TreeNode &node,
                           const MoveLabels &move_labels, size_t depth) {
  for (size_t i = 0; i < depth; ++i)
    out << "  ";

  if (node.uid == 0) {
    out << "- uid=0 root\n";
  } else {
    out << "- uid=" << node.uid << " color=" << node.color
        << ", row=" << node.row << ", column=" << node.column;
    if (node.color == 0)
      out << ", preset_count=" << node.preset_stones.size();
    const auto label_it = move_labels.find(node.uid);
    if (label_it != move_labels.end()) {
      out << ", " << label_it->second;
    }
    out << '\n';
  }

  for (const auto &child : node.children) {
    dump_record_tree_node(out, child, move_labels, depth + 1);
  }
}

void dump_record_tree(std::ofstream &out, const std::string &title,
                      Board &board, const MoveLabels &move_labels) {
  out << "\n===== record tree: " << title << " =====\n";
  dump_record_tree_node(out, board.record_tree(), move_labels, 0);
}

uint64_t place(Board &board, std::ofstream &out, MoveLabels &move_labels,
               int color, size_t row, size_t column, const std::string &label) {
  const int result = board.place_stone(color, row, column);
  expect_eq(result, 0, label.c_str());
  const auto uid = newest_uid(board);
  out << "move: " << label << ", uid=" << uid << ", color=" << color
      << ", row=" << row << ", column=" << column << '\n';
  move_labels[uid] = label;
  dump_record_tree(out, "after " + label, board, move_labels);
  return uid;
}

void roam_and_dump(Board &board, std::ofstream &out, uint64_t uid,
                   const std::string &before_title,
                   const std::string &after_title) {
  dump_board(out, before_title, board);
  out << "roaming_to: uid=" << uid << '\n';
  board.roaming_to(uid);
  dump_board(out, after_title, board);
}

void expect_empty(Board &board, size_t row, size_t column,
                  const char *message) {
  expect_eq(board.state_of_position(row, column), 0, message);
}

void expect_stone(Board &board, size_t row, size_t column, int color,
                  const char *message) {
  expect_eq(board.state_of_position(row, column), color, message);
}

void test_roaming_across_branches(std::ofstream &out) {
  Board board{19};
  MoveLabels move_labels;
  dump_board(out, "roaming: initial board", board);
  dump_record_tree(out, "initial", board, move_labels);

  const auto main_1 = place(board, out, move_labels, Black, 4, 4,
                            "main 1: black at upper-left star");
  const auto main_2 = place(board, out, move_labels, White, 4, 16,
                            "main 2: white at upper-right star");
  const auto main_3 = place(board, out, move_labels, Black, 16, 4,
                            "main 3: black at lower-left star");
  const auto main_4 = place(board, out, move_labels, White, 16, 16,
                            "main 4: white at lower-right star");
  (void)main_1;
  (void)main_3;

  roam_and_dump(board, out, main_2,
                "roaming: main branch before returning to shared node",
                "roaming: after returning to uid main_2");
  expect_stone(board, 4, 4, Black, "main_2 keeps first black");
  expect_stone(board, 4, 16, White, "main_2 keeps second white");
  expect_empty(board, 16, 4, "main_2 removes main third move");
  expect_empty(board, 16, 16, "main_2 removes main fourth move");

  const auto center_1 = place(board, out, move_labels, Black, 10, 10,
                              "center branch 1: black at center");
  const auto center_2 = place(board, out, move_labels, White, 10, 11,
                              "center branch 2: white beside center");
  const auto center_3 = place(board, out, move_labels, Black, 10, 12,
                              "center branch 3: black extends center line");
  (void)center_1;
  (void)center_2;

  roam_and_dump(board, out, main_2,
                "roaming: center branch leaf before creating sibling",
                "roaming: returned to shared node for sibling branch");

  const auto top_1 = place(board, out, move_labels, Black, 3, 10,
                           "top branch 1: black above center");
  const auto top_2 = place(board, out, move_labels, White, 4, 10,
                           "top branch 2: white below top black");
  const auto top_3 = place(board, out, move_labels, Black, 5, 10,
                           "top branch 3: black extends downward");
  (void)top_1;
  (void)top_2;

  roam_and_dump(board, out, center_3,
                "roaming: top branch leaf before sibling jump",
                "roaming: after jumping from top branch to center branch");
  expect_stone(board, 10, 10, Black, "center branch restores black at 10,10");
  expect_stone(board, 10, 11, White, "center branch restores white at 10,11");
  expect_stone(board, 10, 12, Black, "center branch restores black at 10,12");
  expect_empty(board, 3, 10, "center branch removes top branch first move");
  expect_empty(board, 4, 10, "center branch removes top branch second move");
  expect_empty(board, 5, 10, "center branch removes top branch third move");

  roam_and_dump(board, out, top_3,
                "roaming: center branch leaf before jumping back to top branch",
                "roaming: after jumping back to top branch");
  expect_stone(board, 3, 10, Black, "top branch restores black at 3,10");
  expect_stone(board, 4, 10, White, "top branch restores white at 4,10");
  expect_stone(board, 5, 10, Black, "top branch restores black at 5,10");
  expect_empty(board, 10, 10, "top branch removes center branch first move");
  expect_empty(board, 10, 11, "top branch removes center branch second move");
  expect_empty(board, 10, 12, "top branch removes center branch third move");

  roam_and_dump(board, out, main_4,
                "roaming: top branch leaf before returning to main line",
                "roaming: after returning to main line leaf");
  expect_stone(board, 16, 4, Black, "main line restores third move");
  expect_stone(board, 16, 16, White, "main line restores fourth move");
  expect_empty(board, 3, 10, "main line removes top branch first move");
  expect_empty(board, 4, 10, "main line removes top branch second move");
  expect_empty(board, 5, 10, "main line removes top branch third move");

  const auto main_5 = place(board, out, move_labels, Black, 10, 4,
                            "main extension: black on left side");
  roam_and_dump(board, out, 0,
                "roaming: main extension before returning to root",
                "roaming: after returning to root");
  expect_empty(board, 4, 4, "root clears first main move");
  expect_empty(board, 4, 16, "root clears second main move");
  expect_empty(board, 16, 4, "root clears third main move");
  expect_empty(board, 16, 16, "root clears fourth main move");
  expect_empty(board, 10, 4, "root clears main extension");

  const auto root_1 = place(board, out, move_labels, Black, 1, 1,
                            "root branch 1: black at corner");
  const auto root_2 = place(board, out, move_labels, White, 2, 1,
                            "root branch 2: white below corner");
  (void)root_1;

  roam_and_dump(board, out, main_5,
                "roaming: root branch before jumping to main extension",
                "roaming: after jumping from root branch to main extension");
  expect_stone(board, 10, 4, Black, "main extension restores black at 10,4");
  expect_empty(board, 1, 1, "main extension removes root branch first move");
  expect_empty(board, 2, 1, "main extension removes root branch second move");

  roam_and_dump(board, out, root_2,
                "roaming: main extension before jumping back to root branch",
                "roaming: after jumping back to root branch");
  expect_stone(board, 1, 1, Black, "root branch restores black at 1,1");
  expect_stone(board, 2, 1, White, "root branch restores white at 2,1");
  expect_empty(board, 10, 4, "root branch removes main extension");

  const auto tree = board.record_tree();
  Board loaded{19};
  expect_eq(loaded.load_record_tree(tree, {}), 0, "load_record_tree succeeds");
  const auto loaded_tree = loaded.record_tree();
  assert(same_record_tree_shape(tree, loaded_tree));
  out << "record tree load: round-trip shape matched, original max uid="
      << max_uid(tree) << ", loaded max uid=" << max_uid(loaded_tree) << '\n';

  const auto before_failed_load = loaded.record_tree();
  TreeNode invalid_tree{};
  invalid_tree.children.push_back(TreeNode{});
  invalid_tree.children.back().color = Black;
  invalid_tree.children.back().row = 0;
  invalid_tree.children.back().column = 0;
  expect_eq(loaded.load_record_tree(invalid_tree, {}), -1,
            "load_record_tree rejects invalid tree");
  assert(same_record_tree_shape(before_failed_load, loaded.record_tree()));
}
void test_roaming_across_preset_branches(std::ofstream &out) {
  Board board{19};
  expect_eq(board.preset_stone(Black, 4, 4), 0,
            "preset roaming: first root setup succeeds");
  expect_eq(board.preset_stone(White, 16, 16), 0,
            "preset roaming: root setup operations merge");
  const auto root_setup_uid = newest_uid(board);

  expect_eq(board.place_stone(Black, 10, 10), 0,
            "preset roaming: move after setup succeeds");
  const auto shared_move_uid = newest_uid(board);

  expect_eq(board.preset_stones(
                {{White, 4, 4}, {0, 16, 16}, {Black, 10, 11}}),
            0, "preset roaming: first setup branch succeeds");
  const auto first_setup_uid = newest_uid(board);
  expect_eq(board.place_stone(White, 11, 11), 0,
            "preset roaming: move after first setup branch succeeds");
  const auto first_leaf_uid = newest_uid(board);

  expect_eq(board.roaming_to(shared_move_uid), 0,
            "preset roaming: return to shared move succeeds");
  expect_stone(board, 4, 4, Black,
               "preset roaming: parent restores original black setup");
  expect_stone(board, 16, 16, White,
               "preset roaming: parent restores original white setup");
  expect_empty(board, 10, 11,
               "preset roaming: parent removes branch-only setup stone");

  expect_eq(board.preset_stones(
                {{White, 4, 4}, {Black, 16, 16}, {White, 10, 11}}),
            0, "preset roaming: sibling setup branch succeeds");
  const auto second_setup_uid = newest_uid(board);
  assert(second_setup_uid != first_setup_uid);

  expect_eq(board.roaming_to(first_leaf_uid), 0,
            "preset roaming: cross from second branch to first leaf");
  expect_stone(board, 4, 4, White,
               "preset roaming: first branch overwrites root setup stone");
  expect_empty(board, 16, 16,
               "preset roaming: first branch clears root setup stone");
  expect_stone(board, 10, 11, Black,
               "preset roaming: first branch restores black preset stone");
  expect_stone(board, 11, 11, White,
               "preset roaming: first branch restores descendant move");

  expect_eq(board.roaming_to(second_setup_uid), 0,
            "preset roaming: cross to second setup branch");
  expect_stone(board, 4, 4, White,
               "preset roaming: second branch keeps white overwrite");
  expect_stone(board, 16, 16, Black,
               "preset roaming: second branch applies black overwrite");
  expect_stone(board, 10, 11, White,
               "preset roaming: second branch uses its own preset color");
  expect_empty(board, 11, 11,
               "preset roaming: sibling branch excludes first descendant move");

  expect_eq(board.roaming_to(root_setup_uid), 0,
            "preset roaming: return to opening setup node");
  expect_stone(board, 4, 4, Black,
               "preset roaming: opening setup restores black stone");
  expect_stone(board, 16, 16, White,
               "preset roaming: opening setup restores white stone");
  expect_empty(board, 10, 10,
               "preset roaming: opening setup excludes later move");

  expect_eq(board.roaming_to(0), 0,
            "preset roaming: virtual root is reachable");
  expect_empty(board, 4, 4,
               "preset roaming: virtual root is strictly empty");
  expect_empty(board, 16, 16,
               "preset roaming: virtual root has no opening setup stones");

  const auto tree = board.record_tree();
  Board loaded{19};
  expect_eq(loaded.load_record_tree(tree, {}), 0,
            "preset roaming: mixed record tree round-trip succeeds");
  assert(same_record_tree_shape(tree, loaded.record_tree()));
  expect_eq(loaded.roaming_to(first_leaf_uid), 0,
            "preset roaming: loaded tree reaches first leaf");
  expect_stone(loaded, 10, 11, Black,
               "preset roaming: loaded tree replays setup delta");
  expect_stone(loaded, 11, 11, White,
               "preset roaming: loaded tree replays move after setup");

  dump_record_tree(out, "preset branches", board, {});
}

void test_reorder_next_records() {
  Board board{19};
  const auto first = board.place_stone(Black, 4, 4);
  expect_eq(first, 0, "reorder: first root branch succeeds");
  const auto first_uid = newest_uid(board);
  expect_eq(board.roaming_to(0), 0, "reorder: return to root");
  expect_eq(board.place_stone(Black, 10, 10), 0,
            "reorder: second root branch succeeds");
  const auto second_uid = newest_uid(board);
  expect_eq(board.roaming_to(0), 0, "reorder: return to root again");
  expect_eq(board.preset_stones({{White, 16, 16}}), 0,
            "reorder: preset root branch succeeds");
  const auto preset_uid = newest_uid(board);

  expect_eq(board.reorder_next_records(
                0, {preset_uid, 999999, preset_uid, first_uid}),
            0, "reorder: tolerant root reorder succeeds");
  const auto reordered = board.record_tree();
  assert(reordered.children.size() == 3);
  assert(reordered.children[0].uid == preset_uid);
  assert(reordered.children[1].uid == first_uid);
  assert(reordered.children[2].uid == second_uid);

  expect_eq(board.reorder_next_records(999999, {first_uid}), 0,
            "reorder: missing parent is a successful no-op");
  const auto unchanged = board.record_tree();
  assert(unchanged.children[0].uid == preset_uid);
  assert(unchanged.children[1].uid == first_uid);
  assert(unchanged.children[2].uid == second_uid);
}
} // namespace

int main() {
  const char *output_path = "tests/test_roaming.txt";
  std::ofstream out{output_path};
  if (!out) {
    output_path = "../tests/test_roaming.txt";
    out.clear();
    out.open(output_path);
  }
  if (!out) {
    std::cerr << "cannot open test_roaming.txt\n";
    return 1;
  }
  out << "output: " << output_path << '\n';

  test_roaming_across_branches(out);
  test_roaming_across_preset_branches(out);
  test_reorder_next_records();

  out << "\nAll roaming tests passed.\n";
  return 0;
}
