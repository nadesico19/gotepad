#include "../src/go_core.hpp"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <utility>

namespace {
using Board = nd::go::GoCore;
using Cursor = nd::go::GoCoreRecordTreeNode;
using std::size_t;
using std::uint64_t;

constexpr int kBlack = 1;
constexpr int kWhite = 2;

void expect_eq(int actual, int expected, const char *message) {
  if (actual != expected) {
    std::cerr << message << ": expected " << expected << ", actual " << actual
              << '\n';
    assert(actual == expected);
  }
}

bool same_node(const Cursor &left, const Cursor &right) {
  if (left.uid != right.uid || left.color != right.color ||
      left.row != right.row || left.column != right.column ||
      left.preset_stones != right.preset_stones ||
      left.children.size() != right.children.size()) {
    return false;
  }
  for (size_t index = 0; index < left.children.size(); ++index) {
    if (!same_node(left.children[index], right.children[index]))
      return false;
  }
  return true;
}

void expect_cursor(const Cursor &cursor, uint64_t uid, int color, size_t row,
                   size_t column, size_t child_count) {
  assert(cursor.uid == uid);
  assert(cursor.color == color);
  assert(cursor.row == row);
  assert(cursor.column == column);
  assert(cursor.children.size() == child_count);
  for (const auto &child : cursor.children)
    assert(child.children.empty());
}

void build_branched_game(Board &board) {
  expect_eq(board.place_stone(kBlack, 4, 4), 0, "place uid 1");
  expect_eq(board.place_stone(kWhite, 4, 5), 0, "place uid 2");
  expect_eq(board.roaming_to(1), 0, "return to uid 1");
  expect_eq(board.place_stone(kWhite, 5, 4), 0, "place uid 3");
  expect_eq(board.roaming_to(0), 0, "return to root");
  expect_eq(board.place_stone(kBlack, 10, 10), 0, "place uid 4");
  expect_eq(board.place_stone(kWhite, 10, 11), 0, "place uid 5");
}

void test_move_to() {
  Board board{19};
  build_branched_game(board);
  Cursor cursor{};

  expect_eq(cursor.move_to(board, 0), 0, "move cursor to root");
  expect_cursor(cursor, 0, 0, 0, 0, 2);
  expect_cursor(cursor.children[0], 1, kBlack, 4, 4, 0);
  expect_cursor(cursor.children[1], 4, kBlack, 10, 10, 0);

  expect_eq(cursor.move_to(board, 1), 0, "move cursor to uid 1");
  expect_cursor(cursor, 1, kBlack, 4, 4, 2);
  expect_cursor(cursor.children[0], 2, kWhite, 4, 5, 0);
  expect_cursor(cursor.children[1], 3, kWhite, 5, 4, 0);

  const auto before_failure = cursor;
  expect_eq(cursor.move_to(board, 999), -1, "reject unknown uid");
  assert(same_node(cursor, before_failure));

  assert(board.state_of_position(10, 10) == kBlack);
  assert(board.state_of_position(10, 11) == kWhite);
  assert(board.state_of_position(4, 4) == 0);
}

void test_move_back() {
  Board board{19};
  build_branched_game(board);
  Cursor cursor{};

  expect_eq(cursor.move_to(board, 2), 0, "start cursor at uid 2");
  expect_eq(cursor.move_back(board), 0, "move cursor back to uid 1");
  expect_cursor(cursor, 1, kBlack, 4, 4, 2);
  expect_eq(cursor.move_back(board), 0, "move cursor back to root");
  expect_cursor(cursor, 0, 0, 0, 0, 2);

  const auto root = cursor;
  expect_eq(cursor.move_back(board), 0, "moving back at root succeeds");
  assert(same_node(cursor, root));

  cursor.uid = 999;
  const auto invalid = cursor;
  expect_eq(cursor.move_back(board), -1, "invalid cursor cannot move back");
  assert(same_node(cursor, invalid));
}

void test_ensure_status() {
  Board board{19};
  build_branched_game(board);
  Cursor cursor{};

  expect_eq(cursor.move_to(board, 1), 0, "prepare uid 1 cursor");
  std::reverse(cursor.children.begin(), cursor.children.end());
  const auto reordered = cursor;
  expect_eq(cursor.ensure_status(board), 0, "accept reordered children");
  assert(same_node(cursor, reordered));

  cursor.children[0].row = 19;
  cursor.children[1].children.push_back(Cursor{});
  expect_eq(cursor.ensure_status(board), 0, "repair invalid child data");
  expect_cursor(cursor.children[0], 2, kWhite, 4, 5, 0);
  expect_cursor(cursor.children[1], 3, kWhite, 5, 4, 0);

  cursor.color = kWhite;
  const auto invalid_identity = cursor;
  expect_eq(cursor.ensure_status(board), -1, "reject invalid cursor identity");
  assert(same_node(cursor, invalid_identity));
}

void test_refresh_after_game_change() {
  Board board{19};
  build_branched_game(board);
  Cursor cursor{};
  expect_eq(cursor.move_to(board, 1), 0, "prepare stale cursor");

  expect_eq(board.roaming_to(1), 0, "return board to uid 1");
  expect_eq(board.place_stone(kWhite, 6, 4), 0, "add uid 6 branch");
  assert(cursor.children.size() == 2);
  expect_eq(cursor.ensure_status(board), 0, "refresh stale children");
  expect_cursor(cursor, 1, kBlack, 4, 4, 3);
  expect_cursor(cursor.children[2], 6, kWhite, 6, 4, 0);

  Cursor removed{};
  expect_eq(removed.move_to(board, 6), 0, "prepare removed-node cursor");
  const auto removed_snapshot = removed;
  const auto records = board.takeback();
  assert(!records.empty());
  expect_eq(removed.ensure_status(board), -1, "detect removed cursor node");
  assert(same_node(removed, removed_snapshot));
}
void test_preset_cursor() {
  Board board{19};
  expect_eq(board.preset_stone(kBlack, 4, 4), 0,
            "preset cursor: first setup succeeds");
  expect_eq(board.preset_stone(kWhite, 16, 16), 0,
            "preset cursor: second setup merges");

  Cursor root{};
  expect_eq(root.move_to(board, 0), 0,
            "preset cursor: move cursor to empty root");
  expect_cursor(root, 0, 0, 0, 0, 1);
  const auto preset_uid = root.children.front().uid;
  assert(root.children.front().color == 0);
  assert(root.children.front().row == 0);
  assert(root.children.front().column == 0);
  assert(root.children.front().preset_stones.size() == 2);

  Cursor preset{};
  expect_eq(preset.move_to(board, preset_uid), 0,
            "preset cursor: move cursor to setup node");
  expect_cursor(preset, preset_uid, 0, 0, 0, 0);
  assert(preset.preset_stones.size() == 2);
  assert(preset.preset_stones[0].color == kBlack);
  assert(preset.preset_stones[1].color == kWhite);

  expect_eq(board.place_stone(kBlack, 10, 10), 0,
            "preset cursor: add move child");
  assert(preset.children.empty());
  expect_eq(preset.ensure_status(board), 0,
            "preset cursor: refresh move child");
  assert(preset.children.size() == 1);
  expect_cursor(preset.children.front(), preset.children.front().uid,
                kBlack, 10, 10, 0);

  preset.preset_stones.front().color = kWhite;
  const auto invalid = preset;
  expect_eq(preset.ensure_status(board), -1,
            "preset cursor: reject modified setup identity");
  assert(same_node(preset, invalid));

  Cursor back{};
  expect_eq(back.move_to(board, preset_uid), 0,
            "preset cursor: prepare setup cursor for move_back");
  expect_eq(back.move_back(board), 0,
            "preset cursor: setup parent is virtual root");
  expect_cursor(back, 0, 0, 0, 0, 1);
}
} // namespace

int main() {
  test_move_to();
  test_move_back();
  test_ensure_status();
  test_refresh_after_game_change();
  test_preset_cursor();
  std::cout << "All cursor tests passed.\n";
  return 0;
}
