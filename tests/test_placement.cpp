#include "../src/go_notes.hpp"

#include <algorithm>

#include <cassert>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
    using Board = nd::go::GoCore;

    constexpr int Black = 1;
    constexpr int White = 2;

    using RecordTreeNode = nd::go::GoCoreRecordTreeNode;
    using PresetStone = nd::go::GoCorePresetStone;

    bool same_record_tree(const RecordTreeNode &left, const RecordTreeNode &right) {
        if (left.uid != right.uid || left.color != right.color ||
            left.row != right.row || left.column != right.column ||
            left.preset_stones != right.preset_stones ||
            left.children.size() != right.children.size()) {
            return false;
        }

        for (size_t index = 0; index < left.children.size(); ++index) {
            if (!same_record_tree(left.children[index], right.children[index])) {
                return false;
            }
        }
        return true;
    }

    void dump_board(std::ofstream &out, const std::string &title, Board &board) {
        out << "\n===== " << title << " =====\n";
        board.text_output(out);
    }

    void expect_eq(int actual, int expected, const char *message) {
        if (actual != expected) {
            std::cerr << message << ": expected " << expected << ", actual " << actual << '\n';
            assert(actual == expected);
        }
    }

    void place_and_dump(
        Board &board,
        std::ofstream &out,
        int expected_result,
        int color,
        size_t row,
        size_t column,
        const std::string &title
    ) {
        const int result = board.place_stone(color, row, column);
        expect_eq(result, expected_result, title.c_str());
        out << "move: color=" << color << ", row=" << row << ", column=" << column
            << ", result=" << result << '\n';
        dump_board(out, title, board);
    }

    void test_board_size_validation() {
        bool below_minimum_rejected = false;
        try {
            Board invalid_board{0};
        } catch (const std::invalid_argument &) {
            below_minimum_rejected = true;
        }
        assert(below_minimum_rejected);

        bool above_maximum_rejected = false;
        try {
            Board invalid_board{53};
        } catch (const std::invalid_argument &) {
            above_maximum_rejected = true;
        }
        assert(above_maximum_rejected);

        Board board{1};
        expect_eq(board.ngrids(), 1, "board size: runtime size is retained");
        expect_eq(board.state_of_position(1, 1), 0, "board size: only point is valid");
        expect_eq(board.state_of_position(0, 1), -1, "board size: row below range is rejected");
        expect_eq(board.state_of_position(2, 1), -1, "board size: row above range is rejected");
        expect_eq(board.preset_stone(Black, 1, 2), -2, "board size: preset outside range is rejected");
        expect_eq(board.place_stone(Black, 2, 1), -1, "board size: move outside range is rejected");

        Board largest_board{52};
        expect_eq(largest_board.ngrids(), 52, "board size: maximum size is retained");
        expect_eq(largest_board.place_stone(Black, 52, 52), 0,
                  "board size: maximum coordinate is usable");
    }

    void test_command_parse() {
        auto preset = nd::go::GoNotes::Command::parse("PRESET,1,4,5;");
        assert(dynamic_cast<nd::go::GoNotes::PresetCommand *>(preset.get()) != nullptr);
        auto batch_preset = nd::go::GoNotes::Command::parse(
            "PRESET,1,4,5,2,16,16,0,10,10;");
        assert(dynamic_cast<nd::go::GoNotes::PresetCommand *>(
                   batch_preset.get()) != nullptr);
        auto edit_preset = nd::go::GoNotes::Command::parse(
            "EDITPRESET,1,4,5,0,16,16;");
        assert(dynamic_cast<nd::go::GoNotes::EditPresetCommand *>(
                   edit_preset.get()) != nullptr);
        assert(!nd::go::GoNotes::Command::parse("PRESET,1,4,5,2,16;"));
        auto keep_main_line =
            nd::go::GoNotes::Command::parse("KEEPMAINLINE;");
        assert(dynamic_cast<nd::go::GoNotes::KeepMainLineCommand *>(
                   keep_main_line.get()) != nullptr);
        auto clear_notes = nd::go::GoNotes::Command::parse("CLEARNOTES;");
        assert(dynamic_cast<nd::go::GoNotes::ClearNotesCommand *>(
                   clear_notes.get()) != nullptr);

        auto place = nd::go::GoNotes::Command::parse("PLACESTONE,2,16,17;");
        assert(dynamic_cast<nd::go::GoNotes::PlaceStoneCommand *>(place.get()) != nullptr);

        auto takeback = nd::go::GoNotes::Command::parse("TAKEBACK;");
        assert(dynamic_cast<nd::go::GoNotes::TakebackCommand *>(takeback.get()) != nullptr);

        auto roaming = nd::go::GoNotes::Command::parse("ROAMING,42;");
        assert(dynamic_cast<nd::go::GoNotes::RoamingCommand *>(roaming.get()) != nullptr);

        auto find = nd::go::GoNotes::Command::parse("FIND,8,9;");
        assert(dynamic_cast<nd::go::GoNotes::FindCommand *>(find.get()) != nullptr);
        auto find_parent = nd::go::GoNotes::Command::parse("FIND,-1,8,9;");
        assert(dynamic_cast<nd::go::GoNotes::FindCommand *>(find_parent.get()) != nullptr);
        auto find_child = nd::go::GoNotes::Command::parse("FIND,1,8,9;");
        assert(dynamic_cast<nd::go::GoNotes::FindCommand *>(find_child.get()) != nullptr);

        assert(!nd::go::GoNotes::Command::parse("TAKEBACK"));
        assert(!nd::go::GoNotes::Command::parse("TAKEBACK,1;"));
        assert(!nd::go::GoNotes::Command::parse("ROAMING,-1;"));
        assert(!nd::go::GoNotes::Command::parse("FIND,1x,2;"));
        assert(!nd::go::GoNotes::Command::parse("FIND,0,8,9;"));
        assert(!nd::go::GoNotes::Command::parse("FIND,2,8,9;"));
        assert(!nd::go::GoNotes::Command::parse("UNKNOWN;"));
    }

    void test_go_notes_construction() {
        nd::go::GoNotes go_notes{19};
        expect_eq(go_notes.board_size(), 19, "go notes: board size is initialized");

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::PresetCommand>(
                          Black, 4, 4)),
                  0, "go notes: preset command succeeds");
        expect_eq(go_notes.state_at(4, 4), Black,
                  "go notes: preset command changes board");
        expect_eq(go_notes.undo(), 0, "go notes: preset undo succeeds");
        expect_eq(go_notes.state_at(4, 4), 0,
                  "go notes: preset undo restores board");

        nd::go::GoNotes batch_preset_notes{19};
        expect_eq(batch_preset_notes.execute(
                      "PRESET,1,4,4,2,16,16,1,10,10;"),
                  0, "go notes: batch preset command succeeds");
        const auto setup_uid = batch_preset_notes.current_uid();
        const auto setup_node = batch_preset_notes.current_node();
        assert(setup_uid != 0 && setup_node.color == 0);
        assert(setup_node.preset_stones.size() == 3);
        expect_eq(batch_preset_notes.undo(), 0,
                  "go notes: batch preset undo removes the complete setup");
        expect_eq(batch_preset_notes.current_uid(), 0,
                  "go notes: batch preset undo returns to the parent");
        expect_eq(batch_preset_notes.state_at(4, 4), 0,
                  "go notes: batch preset undo clears all setup stones");
        expect_eq(batch_preset_notes.redo(), 0,
                  "go notes: batch preset redo restores the complete setup");
        expect_eq(batch_preset_notes.current_uid(), setup_uid,
                  "go notes: batch preset redo preserves the setup uid");
        expect_eq(batch_preset_notes.state_at(16, 16), White,
                  "go notes: batch preset redo restores every setup stone");

        nd::go::GoNotes duplicate_preset_notes{19};
        expect_eq(duplicate_preset_notes.execute("PLACESTONE,1,10,10;"), 0,
                  "go notes: duplicate preset parent move succeeds");
        const auto duplicate_parent_uid = duplicate_preset_notes.current_uid();
        expect_eq(duplicate_preset_notes.execute(
                      "PRESET,2,10,11,1,11,10;"),
                  0, "go notes: first preset branch succeeds");
        const auto duplicate_setup_uid = duplicate_preset_notes.current_uid();
        expect_eq(duplicate_preset_notes.execute(
                      "ROAMING," + std::to_string(duplicate_parent_uid) + ";"),
                  0, "go notes: return to preset branch parent");
        expect_eq(duplicate_preset_notes.execute(
                      "PRESET,1,11,10,2,10,11;"),
                  0, "go notes: equivalent preset branch becomes roaming");
        expect_eq(duplicate_preset_notes.current_uid(), duplicate_setup_uid,
                  "go notes: equivalent preset branch selects existing uid");
        const auto duplicate_parent =
            duplicate_preset_notes.node_at(duplicate_parent_uid);
        assert(duplicate_parent.has_value());
        expect_eq(static_cast<int>(duplicate_parent->children.size()), 1,
                  "go notes: equivalent preset does not add a second branch");

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::PlaceStoneCommand>(
                          Black, 4, 4)),
                  0, "go notes: place command succeeds");
        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::TakebackCommand>()),
                  0, "go notes: takeback command succeeds");
        expect_eq(go_notes.state_at(4, 4), 0,
                  "go notes: takeback removes stone");
        expect_eq(go_notes.undo(), 0, "go notes: takeback undo succeeds");
        expect_eq(go_notes.state_at(4, 4), Black,
                  "go notes: takeback undo restores stone");
        expect_eq(go_notes.undo(), 0, "go notes: place undo succeeds");
        expect_eq(go_notes.state_at(4, 4), 0,
                  "go notes: place undo removes stone");
    }

    void test_reorder_branches_command() {
        nd::go::GoNotes notes{19};
        expect_eq(notes.execute("PLACESTONE,1,4,4;"), 0,
                  "reorder command: first branch succeeds");
        const auto first_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING,0;"), 0,
                  "reorder command: returns to root");
        expect_eq(notes.execute("PLACESTONE,1,10,10;"), 0,
                  "reorder command: second branch succeeds");
        const auto second_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING,0;"), 0,
                  "reorder command: returns to root again");
        expect_eq(notes.execute("PRESET,2,16,16;"), 0,
                  "reorder command: preset branch succeeds");
        const auto preset_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING,0;"), 0,
                  "reorder command: prepares root ordering");

        expect_eq(notes.execute(
                      std::make_unique<
                          nd::go::GoNotes::ReorderBranchesCommand>(
                          0, std::vector<uint64_t>{preset_uid, first_uid,
                                                   second_uid})),
                  0, "reorder command: execute succeeds");
        auto children = notes.next_moves();
        assert(children.size() == 3);
        assert(children[0].uid == preset_uid);
        assert(children[1].uid == first_uid);
        assert(children[2].uid == second_uid);

        expect_eq(notes.execute(
                      std::make_unique<nd::go::GoNotes::RoamingCommand>(
                          first_uid)),
                  0, "reorder command: cursor can move before undo");
        expect_eq(notes.undo(), 0,
                  "reorder command: undo latest roaming");
        expect_eq(notes.undo(), 0,
                  "reorder command: undo restores original order");
        children = notes.next_moves();
        assert(children[0].uid == first_uid);
        assert(children[1].uid == second_uid);
        assert(children[2].uid == preset_uid);
        expect_eq(notes.redo(), 0,
                  "reorder command: redo restores requested order");
        children = notes.next_moves();
        assert(children[0].uid == preset_uid);
        assert(children[1].uid == first_uid);
        assert(children[2].uid == second_uid);
    }

    void test_keep_main_line_command() {
        nd::go::GoNotes notes{19};
        expect_eq(notes.execute("PLACESTONE,1,4,4;"), 0,
                  "keep main line: creates first root branch");
        const auto main_first_uid = notes.current_uid();
        expect_eq(notes.execute("PLACESTONE,2,4,5;"), 0,
                  "keep main line: extends first child");
        const auto main_leaf_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING," + std::to_string(main_first_uid) + ";"), 0,
                  "keep main line: returns to first node");
        expect_eq(notes.execute("PLACESTONE,2,5,4;"), 0,
                  "keep main line: creates a deeper side branch");
        const auto deeper_side_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING,0;"), 0,
                  "keep main line: returns to root");
        expect_eq(notes.execute("PLACESTONE,1,10,10;"), 0,
                  "keep main line: creates a root side branch");
        const auto root_side_uid = notes.current_uid();

        expect_eq(notes.execute("KEEPMAINLINE;"), 0,
                  "keep main line: command succeeds");
        assert(notes.current_uid() == main_leaf_uid);
        assert(notes.node_at(main_first_uid).has_value());
        assert(notes.node_at(main_leaf_uid).has_value());
        assert(!notes.node_at(deeper_side_uid).has_value());
        assert(!notes.node_at(root_side_uid).has_value());

        expect_eq(notes.undo(), 0,
                  "keep main line: one undo restores every removed branch");
        assert(notes.current_uid() == root_side_uid);
        assert(notes.node_at(deeper_side_uid).has_value());
        assert(notes.node_at(root_side_uid).has_value());

        expect_eq(notes.redo(), 0,
                  "keep main line: redo removes every side branch again");
        assert(notes.current_uid() == main_leaf_uid);
        assert(!notes.node_at(deeper_side_uid).has_value());
        assert(!notes.node_at(root_side_uid).has_value());
    }

    void test_clear_notes_command() {
        nd::go::GoNotes notes{19};
        expect_eq(notes.execute("PLACESTONE,1,4,4;"), 0,
                  "clear notes: creates a recorded position");
        const auto noted_uid = notes.current_uid();
        expect_eq(notes.execute(std::make_unique<nd::go::GoNotes::AppendNote>()),
                  0, "clear notes: appends a note");
        expect_eq(notes.execute(std::make_unique<nd::go::GoNotes::UpdateNoteText>(
                      0, "Title", "Comment")),
                  0, "clear notes: fills note text");
        expect_eq(notes.execute(
                      std::make_unique<nd::go::GoNotes::UpdateSequentialMarks>(
                          0, 4, 4, false)),
                  0, "clear notes: adds a sequential mark");
        expect_eq(notes.execute(
                      std::make_unique<nd::go::GoNotes::UpdateSymbolMarks>(
                          0, 5, 5, "TR")),
                  0, "clear notes: adds a symbol mark");

        expect_eq(notes.execute("CLEARNOTES;"), 0,
                  "clear notes: command succeeds");
        assert(notes.notes_at(noted_uid).empty());

        expect_eq(notes.undo(), 0,
                  "clear notes: one undo restores all note content");
        const auto restored = notes.notes_at(noted_uid);
        assert(restored.size() == 1);
        assert(restored.front().title == "Title");
        assert(restored.front().comment == "Comment");
        assert(restored.front().sequential_marks.size() == 1);
        assert(restored.front().symbol_marks.size() == 1);

        expect_eq(notes.redo(), 0,
                  "clear notes: redo clears all note content again");
        assert(notes.notes_at(noted_uid).empty());
    }

    void test_go_notes_execute_and_undo() {
        nd::go::GoNotes empty_notes{19};
        expect_eq(empty_notes.execute(std::unique_ptr<nd::go::GoNotes::Command>{}), -1,
                  "go notes: null command is rejected");
        assert(empty_notes.message() == nd::go::kInvalidCommandMessage);
        expect_eq(empty_notes.undo(), -1, "go notes: empty undo is rejected");
        assert(empty_notes.message() == nd::go::kNoCommandToUndoMessage);

        nd::go::GoNotes go_notes{19};
        expect_eq(go_notes.execute("PLACESTONE,1,4,4;"), 0,
                  "go notes execute: string command succeeds");
        const auto first_uid = go_notes.current_uid();
        assert(first_uid != 0);
        assert(go_notes.can_undo());
        assert(!go_notes.can_redo());
        assert(go_notes.message().empty());

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::PlaceStoneCommand>(
                          White, 4, 5)),
                  0, "go notes execute: second placement succeeds");
        const auto second_uid = go_notes.current_uid();
        assert(second_uid != 0 && second_uid != first_uid);

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::RoamingCommand>(
                          first_uid)),
                  0, "go notes execute: roaming succeeds");
        assert(go_notes.current_uid() == first_uid);
        const auto tree_before_existing_move = go_notes.node_at(0);
        assert(tree_before_existing_move.has_value());

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::PlaceStoneCommand>(
                          White, 4, 5)),
                  0, "go notes execute: existing move becomes roaming");
        assert(go_notes.current_uid() == second_uid);
        const auto tree_after_existing_move = go_notes.node_at(0);
        assert(tree_after_existing_move.has_value());
        assert(same_record_tree(*tree_after_existing_move,
                                *tree_before_existing_move));

        expect_eq(go_notes.undo(), 0,
                  "go notes undo: merged roaming is undone");
        assert(go_notes.current_uid() == first_uid);
        assert(go_notes.can_undo());
        assert(go_notes.can_redo());
        assert(go_notes.message().empty());

        expect_eq(go_notes.execute(
                      std::make_unique<nd::go::GoNotes::PlaceStoneCommand>(
                          White, 5, 4)),
                  0, "go notes execute: new branch clears redo");
        assert(!go_notes.can_redo());
    }

    void test_find_command_directions() {
        nd::go::GoNotes go_notes{19};
        expect_eq(go_notes.execute("PLACESTONE,1,4,4;"), 0,
                  "find directions: first move succeeds");
        const auto first_uid = go_notes.current_uid();
        expect_eq(go_notes.execute("PLACESTONE,2,4,5;"), 0,
                  "find directions: second move succeeds");
        const auto second_uid = go_notes.current_uid();
        expect_eq(go_notes.execute("PLACESTONE,1,4,6;"), 0,
                  "find directions: third move succeeds");
        const auto final_uid = go_notes.current_uid();

        expect_eq(go_notes.execute("FIND,-1,4,4;"), 0,
                  "find directions: parent search succeeds");
        assert(go_notes.current_uid() == first_uid);
        expect_eq(go_notes.undo(), 0,
                  "find directions: parent search undo succeeds");
        assert(go_notes.current_uid() == final_uid);

        expect_eq(go_notes.execute("ROAMING,0;"), 0,
                  "find directions: roam to root succeeds");
        expect_eq(go_notes.execute("FIND,1,4,5;"), 0,
                  "find directions: first-child search succeeds");
        assert(go_notes.current_uid() == second_uid);
        expect_eq(go_notes.undo(), 0,
                  "find directions: first-child search undo succeeds");
        assert(go_notes.current_uid() == 0);

        expect_eq(go_notes.execute("FIND,1,9,9;"), -1,
                  "find directions: missing child move is rejected");
        assert(go_notes.current_uid() == 0);
        assert(go_notes.message() == nd::go::kStoneNotFoundMessage);
    }

    void test_preset_stone_export_and_record_tree_load() {
        Board source{19};
        expect_eq(source.preset_stone(Black, 4, 4), 0,
                  "preset export: black setup stone succeeds");
        expect_eq(source.preset_stone(White, 16, 16), 0,
                  "preset export: white setup stone succeeds");
        const auto setup_tree = source.record_tree();
        assert(setup_tree.children.size() == 1);
        const auto setup_uid = setup_tree.children.front().uid;
        assert(setup_uid != 0);
        assert(setup_tree.children.front().color == 0);
        assert(setup_tree.children.front().preset_stones.size() == 2);

        expect_eq(source.place_stone(Black, 10, 10), 0,
                  "preset export: first formal move succeeds");
        expect_eq(source.place_stone(White, 10, 11), 0,
                  "preset export: second formal move succeeds");

        RecordTreeNode current_before{};
        expect_eq(current_before.move_current(source), 0,
                  "preset export: current record is readable");
        const auto preset_stones = source.get_preset_stones();
        assert(preset_stones.size() == 2);
        assert(preset_stones[0].color == Black && preset_stones[0].row == 4 &&
               preset_stones[0].column == 4);
        assert(preset_stones[1].color == White &&
               preset_stones[1].row == 16 && preset_stones[1].column == 16);

        const auto tree = source.record_tree();
        Board loaded{19};
        expect_eq(loaded.load_record_tree(tree, {}), 0,
                  "preset load: recorded setup tree is accepted");
        expect_eq(loaded.state_of_position(4, 4), 0,
                  "preset load: uid zero is an empty board");
        expect_eq(loaded.state_of_position(16, 16), 0,
                  "preset load: root contains no white setup stone");
        expect_eq(loaded.roaming_to(setup_uid), 0,
                  "preset load: setup node can be roamed to");
        expect_eq(loaded.state_of_position(4, 4), Black,
                  "preset load: setup node restores black stone");
        expect_eq(loaded.state_of_position(16, 16), White,
                  "preset load: setup node restores white stone");
        expect_eq(loaded.roaming_to(current_before.uid), 0,
                  "preset load: imported current record can be roamed to");
        expect_eq(loaded.state_of_position(10, 10), Black,
                  "preset load: first formal move is replayed");
        expect_eq(loaded.state_of_position(10, 11), White,
                  "preset load: second formal move is replayed");

        RecordTreeNode moves_only{};
        moves_only.children.push_back({20, Black, 10, 10, {}, {}});
        Board legacy_loaded{19};
        expect_eq(legacy_loaded.load_record_tree(moves_only, preset_stones), 0,
                  "preset load: legacy setup parameter becomes a record");
        const auto legacy_tree = legacy_loaded.record_tree();
        assert(legacy_tree.children.size() == 1);
        assert(legacy_tree.children.front().color == 0);
        assert(legacy_tree.children.front().uid != 20);
        assert(legacy_tree.children.front().children.size() == 1);
        assert(legacy_tree.children.front().children.front().uid == 20);
        expect_eq(legacy_loaded.state_of_position(4, 4), 0,
                  "legacy preset load: uid zero remains empty");

        Board transactional_board{19};
        expect_eq(transactional_board.preset_stone(White, 3, 3), 0,
                  "preset load rollback: original setup succeeds");
        expect_eq(transactional_board.place_stone(Black, 9, 9), 0,
                  "preset load rollback: original move succeeds");
        const auto original_tree = transactional_board.record_tree();
        RecordTreeNode original_current{};
        expect_eq(original_current.move_current(transactional_board), 0,
                  "preset load rollback: original current record is readable");

        const std::vector<PresetStone> invalid_preset_stones{{Black, 20, 1}};
        expect_eq(transactional_board.load_record_tree(tree,
                                                       invalid_preset_stones),
                  -1, "preset load rollback: invalid setup is rejected");
        assert(same_record_tree(transactional_board.record_tree(),
                                original_tree));
        RecordTreeNode restored_current{};
        expect_eq(restored_current.move_current(transactional_board), 0,
                  "preset load rollback: current record remains readable");
        assert(restored_current.uid == original_current.uid);
        expect_eq(transactional_board.state_of_position(3, 3), White,
                  "preset load rollback: original setup is retained");
        expect_eq(transactional_board.state_of_position(9, 9), Black,
                  "preset load rollback: original move is retained");
    }
    void test_load_record_tree_preserves_uids() {
        RecordTreeNode tree{};
        tree.children.push_back({100, Black, 4, 4, {}, {}});
        tree.children.back().children.push_back({42, White, 4, 5, {}, {}});
        tree.children.push_back({7, Black, 16, 16, {}, {}});

        Board loaded{19};
        expect_eq(loaded.load_record_tree(tree, {}), 0,
                  "load tree: valid tree is accepted");
        assert(same_record_tree(loaded.record_tree(), tree));
        expect_eq(loaded.state_of_position(4, 4), 0,
                  "load tree: successful load returns to initial state");

        expect_eq(loaded.roaming_to(42), 0,
                  "load tree: imported descendant uid can be roamed to");
        expect_eq(loaded.state_of_position(4, 4), Black,
                  "load tree: descendant replays its parent");
        expect_eq(loaded.state_of_position(4, 5), White,
                  "load tree: descendant replays its own move");
        expect_eq(loaded.roaming_to(7), 0,
                  "load tree: non-monotonic root uid can be roamed to");
        expect_eq(loaded.state_of_position(16, 16), Black,
                  "load tree: selected root branch is replayed");
        expect_eq(loaded.state_of_position(4, 4), 0,
                  "load tree: other root branch is not replayed");

        expect_eq(loaded.roaming_to(0), 0,
                  "load tree: roam to root before adding a move");
        expect_eq(loaded.place_stone(White, 10, 10), 0,
                  "load tree: new move after import succeeds");
        const auto extended_tree = loaded.record_tree();
        assert(extended_tree.children.size() == 3);
        assert(extended_tree.children.back().uid == 101);

        Board transactional_board{19};
        expect_eq(transactional_board.place_stone(Black, 9, 9), 0,
                  "load tree rollback: initial move succeeds");
        const auto original_tree = transactional_board.record_tree();
        auto expect_rejected = [&transactional_board, &original_tree](
                                   const RecordTreeNode &invalid_tree) {
            expect_eq(transactional_board.load_record_tree(invalid_tree, {}), -1,
                      "load tree validation: invalid tree is rejected");
            assert(same_record_tree(transactional_board.record_tree(),
                                    original_tree));
            expect_eq(transactional_board.state_of_position(9, 9), Black,
                      "load tree rollback: original board is retained");
        };

        auto nonzero_root = tree;
        nonzero_root.uid = 1;
        expect_rejected(nonzero_root);

        RecordTreeNode zero_child{};
        zero_child.children.push_back({0, Black, 1, 1, {}, {}});
        expect_rejected(zero_child);

        RecordTreeNode duplicate_uid{};
        duplicate_uid.children.push_back({5, Black, 1, 1, {}, {}});
        duplicate_uid.children.push_back({5, White, 2, 2, {}, {}});
        expect_rejected(duplicate_uid);

        RecordTreeNode maximum_uid{};
        maximum_uid.children.push_back(
            {std::numeric_limits<std::uint64_t>::max(), Black, 1, 1, {}, {}});
        expect_rejected(maximum_uid);

        RecordTreeNode invalid_color{};
        invalid_color.children.push_back({6, 3, 1, 1, {}, {}});
        expect_rejected(invalid_color);

        RecordTreeNode invalid_position{};
        invalid_position.children.push_back({6, Black, 20, 1, {}, {}});
        expect_rejected(invalid_position);

        RecordTreeNode duplicate_sibling_move{};
        duplicate_sibling_move.children.push_back({6, Black, 1, 1, {}, {}});
        duplicate_sibling_move.children.push_back({7, Black, 1, 1, {}, {}});
        expect_rejected(duplicate_sibling_move);

        RecordTreeNode illegal_replay{};
        illegal_replay.children.push_back({6, Black, 1, 1, {}, {}});
        illegal_replay.children.back().children.push_back(
            {7, White, 1, 1, {}, {}});
        expect_rejected(illegal_replay);

        RecordTreeNode empty_setup{};
        empty_setup.children.push_back({6, 0, 0, 0, {}, {}});
        expect_rejected(empty_setup);

        RecordTreeNode duplicate_setup_point{};
        duplicate_setup_point.children.push_back(
            {6, 0, 0, 0, {{Black, 1, 1}, {White, 1, 1}}, {}});
        expect_rejected(duplicate_setup_point);

        RecordTreeNode invalid_setup_color{};
        invalid_setup_color.children.push_back(
            {6, 0, 0, 0, {{3, 1, 1}}, {}});
        expect_rejected(invalid_setup_color);

        RecordTreeNode move_with_setup_payload{};
        move_with_setup_payload.children.push_back(
            {6, Black, 1, 1, {{White, 2, 2}}, {}});
        expect_rejected(move_with_setup_payload);

        RecordTreeNode no_liberty_setup{};
        no_liberty_setup.children.push_back(
            {6, 0, 0, 0,
             {{Black, 1, 2}, {Black, 2, 1}, {White, 1, 1}}, {}});
        expect_rejected(no_liberty_setup);

        expect_eq(transactional_board.place_stone(White, 9, 10), 0,
                  "load tree rollback: uid counter is restored");
        const auto rollback_tree = transactional_board.record_tree();
        assert(rollback_tree.children.front().children.front().uid == 2);
    }

    void test_edit_current_preset_transaction() {
        Board board{9};
        expect_eq(board.preset_stones({{Black, 1, 1}}), 0,
                  "edit preset: initial setup succeeds");
        RecordTreeNode cursor{};
        expect_eq(cursor.move_current(board), 0,
                  "edit preset: setup cursor is readable");
        const auto setup_uid = cursor.uid;
        expect_eq(board.place_stone(White, 3, 3), 0,
                  "edit preset: descendant move succeeds");
        expect_eq(cursor.move_current(board), 0,
                  "edit preset: descendant cursor is readable");
        const auto move_uid = cursor.uid;
        expect_eq(board.roaming_to(setup_uid), 0,
                  "edit preset: returns to setup node");

        uint64_t failed_uid = 0;
        expect_eq(board.edit_current_preset_stones({{Black, 2, 2}}, failed_uid),
                  0, "edit preset: compatible change commits");
        assert(failed_uid == 0);
        expect_eq(cursor.move_current(board), 0,
                  "edit preset: edited cursor is readable");
        assert(cursor.uid == setup_uid);
        expect_eq(board.state_of_position(2, 2), Black,
                  "edit preset: edited stone is visible");
        expect_eq(board.roaming_to(move_uid), 0,
                  "edit preset: compatible descendant remains replayable");
        expect_eq(board.state_of_position(3, 3), White,
                  "edit preset: descendant move is preserved");

        expect_eq(board.roaming_to(setup_uid), 0,
                  "edit preset: returns before incompatible edit");
        const auto tree_before_failure = board.record_tree();
        expect_eq(board.edit_current_preset_stones({{Black, 3, 3}}, failed_uid),
                  -4, "edit preset: occupied descendant move is rejected");
        assert(failed_uid == move_uid);
        expect_eq(cursor.move_current(board), 0,
                  "edit preset: failed edit cursor is readable");
        assert(cursor.uid == setup_uid);
        assert(same_record_tree(board.record_tree(), tree_before_failure));
        expect_eq(board.state_of_position(3, 3), 0,
                  "edit preset: failed transaction leaves board unchanged");

        nd::go::GoNotes notes{9};
        expect_eq(notes.execute("PRESET,1,1,1;"), 0,
                  "edit preset command: initial setup succeeds");
        const auto notes_setup_uid = notes.current_uid();
        expect_eq(notes.execute("PLACESTONE,2,3,3;"), 0,
                  "edit preset command: descendant succeeds");
        const auto notes_move_uid = notes.current_uid();
        expect_eq(notes.execute("ROAMING," + std::to_string(notes_setup_uid) +
                                ";"),
                  0, "edit preset command: returns to setup");
        expect_eq(notes.execute("EDITPRESET,1,2,2;"), 0,
                  "edit preset command: edit succeeds");
        assert(notes.current_uid() == notes_setup_uid);
        expect_eq(notes.state_at(2, 2), Black,
                  "edit preset command: edited point is visible");
        expect_eq(notes.undo(), 0, "edit preset command: undo succeeds");
        expect_eq(notes.state_at(2, 2), 0,
                  "edit preset command: undo restores old setup");
        expect_eq(notes.redo(), 0, "edit preset command: redo succeeds");
        expect_eq(notes.state_at(2, 2), Black,
                  "edit preset command: redo restores edited setup");
        expect_eq(notes.execute("EDITPRESET,1,3,3;"), -4,
                  "edit preset command: incompatible edit is rejected");
        assert(notes.error_uid() == notes_move_uid);
        expect_eq(notes.state_at(3, 3), 0,
                  "edit preset command: rejected edit is transactional");
    }

    void test_basic_placement(std::ofstream &out) {
        Board board{19};
        dump_board(out, "basic: initial 19x19 board", board);

        place_and_dump(board, out, 0, Black, 10, 10, "basic: black at center");
        expect_eq(board.state_of_position(10, 10), Black, "basic: black stone state");

        place_and_dump(board, out, 0, White, 1, 1, "basic: white at corner");
        expect_eq(board.state_of_position(1, 1), White, "basic: white stone state");

        place_and_dump(board, out, -2, Black, 10, 10, "basic: occupied point is rejected");
        expect_eq(board.state_of_position(10, 10), Black, "basic: occupied rejection keeps board");

        place_and_dump(board, out, -1, Black, 0, 1, "basic: out of board is rejected");
        place_and_dump(board, out, -1, 3, 5, 5, "basic: invalid color is rejected");
    }

    void test_preset_stones(std::ofstream &out) {
        Board board{19};
        dump_board(out, "preset records: initial empty board", board);

        expect_eq(board.preset_stone(Black, 4, 4), 0,
                  "preset merge: first operation creates a node");
        const auto first_tree = board.record_tree();
        assert(first_tree.children.size() == 1);
        const auto preset_uid = first_tree.children.front().uid;
        assert(first_tree.children.front().color == 0);
        assert(first_tree.children.front().preset_stones.size() == 1);

        expect_eq(board.preset_stone(Black, 16, 16), 0,
                  "preset merge: second point merges into current node");
        auto merged_tree = board.record_tree();
        assert(merged_tree.children.size() == 1);
        assert(merged_tree.children.front().uid == preset_uid);
        assert(merged_tree.children.front().preset_stones.size() == 2);

        expect_eq(board.preset_stone(White, 4, 4), 0,
                  "preset merge: repeated point keeps its latest state");
        merged_tree = board.record_tree();
        assert(merged_tree.children.front().preset_stones.size() == 2);
        const auto repeated = std::find_if(
            merged_tree.children.front().preset_stones.begin(),
            merged_tree.children.front().preset_stones.end(),
            [](const auto &stone) { return stone.row == 4 && stone.column == 4; });
        assert(repeated != merged_tree.children.front().preset_stones.end());
        assert(repeated->color == White);
        expect_eq(board.state_of_position(4, 4), White,
                  "preset merge: board uses latest repeated-point state");

        expect_eq(board.preset_stone(0, 4, 4), 0,
                  "preset merge: returning a point to parent removes it");
        merged_tree = board.record_tree();
        assert(merged_tree.children.front().preset_stones.size() == 1);
        expect_eq(board.preset_stone(0, 4, 4), 0,
                  "preset merge: clearing an already empty point is a no-op");
        assert(board.record_tree().children.front().preset_stones.size() == 1);

        expect_eq(board.preset_stone(0, 16, 16), 0,
                  "preset merge: cancelling the final change succeeds");
        assert(board.record_tree().children.empty());
        RecordTreeNode empty_cursor{};
        expect_eq(empty_cursor.move_current(board), 0,
                  "preset merge: deleting an empty node returns to root");
        assert(empty_cursor.uid == 0);
        expect_eq(board.state_of_position(16, 16), 0,
                  "preset merge: cancelled node leaves an empty board");

        Board no_liberty_board{19};
        expect_eq(no_liberty_board.preset_stones(
                      {{Black, 1, 2}, {Black, 2, 1}}),
                  0, "preset validation: blocking stones are accepted");
        const auto before_rejected_self = no_liberty_board.record_tree();
        expect_eq(no_liberty_board.preset_stone(White, 1, 1), -3,
                  "preset validation: no-liberty new group is rejected");
        assert(same_record_tree(no_liberty_board.record_tree(),
                                before_rejected_self));
        expect_eq(no_liberty_board.state_of_position(1, 1), 0,
                  "preset validation: rejected operation rolls back board");

        Board global_validation_board{5};
        expect_eq(global_validation_board.preset_stones(
                      {{White, 2, 2}, {Black, 1, 2},
                       {Black, 2, 1}, {Black, 3, 2}}),
                  0, "preset validation: group with one liberty is accepted");
        const auto before_rejected_capture =
            global_validation_board.record_tree();
        expect_eq(global_validation_board.preset_stone(Black, 2, 3), -3,
                  "preset validation: removing another group's last liberty is rejected");
        assert(same_record_tree(global_validation_board.record_tree(),
                                before_rejected_capture));
        expect_eq(global_validation_board.state_of_position(2, 2), White,
                  "preset validation: rejected operation retains surrounded group");
        expect_eq(global_validation_board.state_of_position(2, 3), 0,
                  "preset validation: rejected operation clears tentative stone");

        expect_eq(global_validation_board.preset_stones(
                      {{Black, 2, 3}, {0, 2, 2}}),
                  0, "preset batch: final valid position is committed atomically");
        expect_eq(global_validation_board.state_of_position(2, 2), 0,
                  "preset batch: explicit clear is applied");
        expect_eq(global_validation_board.state_of_position(2, 3), Black,
                  "preset batch: companion placement is applied");
        const auto batch_tree = global_validation_board.record_tree();
        assert(batch_tree.children.front().children.size() == 1);
        assert(batch_tree.children.front().children.front().color == 0);
        assert(batch_tree.children.front().children.front().preset_stones.size() == 2);

        Board after_move_board{19};
        expect_eq(after_move_board.place_stone(Black, 10, 10), 0,
                  "preset after move: parent move succeeds");
        expect_eq(after_move_board.can_preset_stone(), 0,
                  "preset after move: GoCore permits a recorded setup child");
        expect_eq(after_move_board.preset_stone(White, 10, 11), 0,
                  "preset after move: first setup creates a child node");
        expect_eq(after_move_board.preset_stone(0, 10, 10), 0,
                  "preset after move: clearing a move stone merges into setup node");
        expect_eq(after_move_board.state_of_position(10, 10), 0,
                  "preset after move: merged clear changes current board");
        expect_eq(after_move_board.state_of_position(10, 11), White,
                  "preset after move: merged placement remains visible");

        const auto removed_setup = after_move_board.takeback();
        assert(removed_setup.size() == 1);
        assert(removed_setup.front().color == 0);
        expect_eq(after_move_board.state_of_position(10, 10), Black,
                  "preset takeback: overwritten parent stone is restored");
        expect_eq(after_move_board.state_of_position(10, 11), 0,
                  "preset takeback: newly preset stone is removed");
        expect_eq(after_move_board.takeback_recovery(removed_setup), 0,
                  "preset recovery: removed setup node is restored");
        expect_eq(after_move_board.state_of_position(10, 10), 0,
                  "preset recovery: clear operation is replayed");
        expect_eq(after_move_board.state_of_position(10, 11), White,
                  "preset recovery: placement operation is replayed");
        dump_board(out, "preset records: recovered setup after move",
                   after_move_board);

        Board duplicate_branch_board{19};
        expect_eq(duplicate_branch_board.place_stone(Black, 10, 10), 0,
                  "preset duplicate: parent move succeeds");
        RecordTreeNode duplicate_parent{};
        assert(duplicate_parent.move_current(duplicate_branch_board) == 0);
        expect_eq(duplicate_branch_board.preset_stones(
                      {{White, 10, 11}, {Black, 11, 10}}),
                  0, "preset duplicate: first setup branch succeeds");
        RecordTreeNode duplicate_setup{};
        assert(duplicate_setup.move_current(duplicate_branch_board) == 0);
        expect_eq(duplicate_branch_board.roaming_to(duplicate_parent.uid), 0,
                  "preset duplicate: roam back to parent");
        expect_eq(
            duplicate_branch_board.matching_preset_branch_uid(
                {{Black, 11, 10}, {White, 10, 11}}),
            duplicate_setup.uid,
            "preset duplicate: equivalent unordered batch finds existing uid");
        const auto tree_before_duplicate = duplicate_branch_board.record_tree();
        expect_eq(duplicate_branch_board.preset_stones(
                      {{Black, 11, 10}, {White, 10, 11}}),
                  -1, "preset duplicate: equivalent branch is rejected");
        assert(same_record_tree(duplicate_branch_board.record_tree(),
                                tree_before_duplicate));
        RecordTreeNode duplicate_current{};
        assert(duplicate_current.move_current(duplicate_branch_board) == 0);
        expect_eq(duplicate_current.uid, duplicate_parent.uid,
                  "preset duplicate: rejection keeps the parent current");
        expect_eq(duplicate_branch_board.state_of_position(10, 11), 0,
                  "preset duplicate: rejection rolls back the tentative board");

        expect_eq(duplicate_branch_board.roaming_to(duplicate_setup.uid), 0,
                  "preset duplicate recovery: roam to original setup");
        const auto removed_duplicate_setup = duplicate_branch_board.takeback();
        expect_eq(duplicate_branch_board.preset_stones(
                      {{Black, 11, 10}, {White, 10, 11}}),
                  0, "preset duplicate recovery: replacement branch succeeds");
        expect_eq(duplicate_branch_board.roaming_to(duplicate_parent.uid), 0,
                  "preset duplicate recovery: return to parent");
        expect_eq(
            duplicate_branch_board.takeback_recovery(removed_duplicate_setup),
            -1,
            "preset duplicate recovery: equivalent sibling blocks recovery");
    }
    void test_takeback_recovery(std::ofstream &out) {
        Board board{19};
        place_and_dump(board, out, 0, Black, 10, 10, "recovery: first move");
        place_and_dump(board, out, 0, White, 10, 11, "recovery: target move");
        place_and_dump(board, out, 0, Black, 11, 10, "recovery: target child");

        const auto tree = board.record_tree();
        expect_eq(static_cast<int>(tree.children.size()), 1, "recovery: one root record");
        expect_eq(
            static_cast<int>(tree.children.at(0).children.size()), 1,
            "recovery: target is the only child of first move"
        );
        const auto first_uid = tree.children.at(0).uid;
        const auto target_uid = tree.children.at(0).children.at(0).uid;
        const auto child_uid = tree.children.at(0).children.at(0).children.at(0).uid;

        expect_eq(board.roaming_to(target_uid), 0, "recovery: roam to target before takeback");
        auto removed = board.takeback();
        expect_eq(static_cast<int>(removed.size()), 2, "recovery: target and child are removed");
        expect_eq(board.state_of_position(10, 11), 0, "recovery: takeback removes target stone");
        expect_eq(board.state_of_position(11, 10), 0, "recovery: takeback keeps child unapplied");

        expect_eq(board.takeback_recovery(removed), 0, "recovery: restore target and child branch");
        expect_eq(board.state_of_position(10, 11), White, "recovery: target stone is replayed");
        expect_eq(board.state_of_position(11, 10), 0, "recovery: child remains available but unapplied");
        expect_eq(board.roaming_to(child_uid), 0, "recovery: restored child can be replayed");
        expect_eq(board.state_of_position(11, 10), Black, "recovery: restored child stone is replayed");

        expect_eq(board.roaming_to(first_uid), 0, "recovery: roam to parent for duplicate uid check");
        expect_eq(board.takeback_recovery(removed), -1, "recovery: records with existing uid are rejected");
        expect_eq(board.state_of_position(10, 11), 0, "recovery: existing uid rejection keeps board");

        expect_eq(board.roaming_to(target_uid), 0, "recovery: roam to target for second takeback");
        auto removed_again = board.takeback();
        expect_eq(static_cast<int>(removed_again.size()), 2, "recovery: second takeback removes subtree");

        expect_eq(board.takeback_recovery({}), -2, "recovery: empty records are rejected as tampered");
        expect_eq(board.state_of_position(10, 11), 0, "recovery: empty rejection keeps board");

        auto duplicate_records = removed_again;
        duplicate_records.push_back(removed_again.front());
        expect_eq(
            board.takeback_recovery(duplicate_records), -2,
            "recovery: duplicate uid inside records is rejected"
        );

        auto future_uid_records = removed_again;
        future_uid_records.front().uid += 1000;
        expect_eq(
            board.takeback_recovery(future_uid_records), -2,
            "recovery: uid above uid counter is rejected"
        );

        auto broken_records = removed_again;
        broken_records.at(1).last_uid = 0;
        expect_eq(
            board.takeback_recovery(broken_records), -2,
            "recovery: broken child parent link is rejected"
        );
        expect_eq(board.state_of_position(10, 11), 0, "recovery: tampered records keep board");

        place_and_dump(board, out, 0, White, 10, 11, "recovery: replacement sibling");
        expect_eq(board.roaming_to(first_uid), 0, "recovery: roam to parent for sibling conflict");
        expect_eq(
            board.takeback_recovery(removed_again), -1,
            "recovery: sibling with the same move rejects restoration"
        );
        expect_eq(board.state_of_position(10, 11), 0, "recovery: sibling conflict keeps parent board");

        Board root_board{19};
        place_and_dump(root_board, out, 0, Black, 4, 4, "root recovery: target move");
        place_and_dump(root_board, out, 0, White, 4, 5, "root recovery: target child");
        const auto root_tree = root_board.record_tree();
        const auto root_target_uid = root_tree.children.at(0).uid;
        const auto root_child_uid = root_tree.children.at(0).children.at(0).uid;
        expect_eq(root_board.roaming_to(root_target_uid), 0, "root recovery: roam to target");
        auto root_removed = root_board.takeback();
        expect_eq(static_cast<int>(root_removed.size()), 2, "root recovery: subtree is removed");
        expect_eq(root_board.takeback_recovery(root_removed), 0, "root recovery: subtree is restored");
        expect_eq(root_board.state_of_position(4, 4), Black, "root recovery: target stone is replayed");
        expect_eq(root_board.roaming_to(root_child_uid), 0, "root recovery: restored child can be replayed");
        expect_eq(root_board.state_of_position(4, 5), White, "root recovery: child stone is replayed");
    }

    void test_corner_single_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "corner single: initial board", board);

        place_and_dump(board, out, 0, White, 1, 1, "corner single: white target at 1,1");
        place_and_dump(board, out, 0, Black, 1, 2, "corner single: black at 1,2");
        expect_eq(board.state_of_position(1, 1), White, "corner single: white still has one liberty");

        place_and_dump(board, out, 0, Black, 2, 1, "corner single: black at 2,1 captures");
        expect_eq(board.state_of_position(1, 1), 0, "corner single: white removed");
    }

    void test_corner_chain_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "corner chain: initial board", board);

        place_and_dump(board, out, 0, White, 1, 1, "corner chain: white at 1,1");
        place_and_dump(board, out, 0, White, 1, 2, "corner chain: white at 1,2");
        place_and_dump(board, out, 0, Black, 1, 3, "corner chain: black at 1,3");
        place_and_dump(board, out, 0, Black, 2, 1, "corner chain: black at 2,1");
        expect_eq(board.state_of_position(1, 1), White, "corner chain: chain alive before final liberty");
        expect_eq(board.state_of_position(1, 2), White, "corner chain: chain alive before final liberty");

        place_and_dump(board, out, 0, Black, 2, 2, "corner chain: black at 2,2 captures chain");
        expect_eq(board.state_of_position(1, 1), 0, "corner chain: first white removed");
        expect_eq(board.state_of_position(1, 2), 0, "corner chain: second white removed");
    }

    void test_edge_single_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "edge single: initial board", board);

        place_and_dump(board, out, 0, White, 1, 10, "edge single: white target at top edge");
        place_and_dump(board, out, 0, Black, 1, 9, "edge single: black left");
        place_and_dump(board, out, 0, Black, 1, 11, "edge single: black right");
        expect_eq(board.state_of_position(1, 10), White, "edge single: white still has one liberty");

        place_and_dump(board, out, 0, Black, 2, 10, "edge single: black below captures");
        expect_eq(board.state_of_position(1, 10), 0, "edge single: white removed");
    }

    void test_edge_chain_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "edge chain: initial board", board);

        place_and_dump(board, out, 0, White, 1, 9, "edge chain: white left");
        place_and_dump(board, out, 0, White, 1, 10, "edge chain: white right");
        place_and_dump(board, out, 0, Black, 1, 8, "edge chain: black far-left");
        place_and_dump(board, out, 0, Black, 1, 11, "edge chain: black far-right");
        place_and_dump(board, out, 0, Black, 2, 9, "edge chain: black below-left");
        expect_eq(board.state_of_position(1, 9), White, "edge chain: chain alive before final liberty");
        expect_eq(board.state_of_position(1, 10), White, "edge chain: chain alive before final liberty");

        place_and_dump(board, out, 0, Black, 2, 10, "edge chain: black below-right captures chain");
        expect_eq(board.state_of_position(1, 9), 0, "edge chain: first white removed");
        expect_eq(board.state_of_position(1, 10), 0, "edge chain: second white removed");
    }

    void test_center_single_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "center single: initial board", board);

        place_and_dump(board, out, 0, White, 10, 10, "center single: white target");
        place_and_dump(board, out, 0, Black, 9, 10, "center single: black above");
        place_and_dump(board, out, 0, Black, 10, 9, "center single: black left");
        place_and_dump(board, out, 0, Black, 10, 11, "center single: black right");
        expect_eq(board.state_of_position(10, 10), White, "center single: white still has one liberty");

        place_and_dump(board, out, 0, Black, 11, 10, "center single: black below captures");
        expect_eq(board.state_of_position(10, 10), 0, "center single: white removed");
    }

    void test_center_chain_capture(std::ofstream &out) {
        Board board{19};
        dump_board(out, "center chain: initial board", board);

        place_and_dump(board, out, 0, White, 10, 10, "center chain: white corner of chain");
        place_and_dump(board, out, 0, White, 10, 11, "center chain: white horizontal arm");
        place_and_dump(board, out, 0, White, 11, 10, "center chain: white vertical arm");
        place_and_dump(board, out, 0, Black, 9, 10, "center chain: black at 9,10");
        place_and_dump(board, out, 0, Black, 10, 9, "center chain: black at 10,9");
        place_and_dump(board, out, 0, Black, 9, 11, "center chain: black at 9,11");
        place_and_dump(board, out, 0, Black, 10, 12, "center chain: black at 10,12");
        place_and_dump(board, out, 0, Black, 11, 9, "center chain: black at 11,9");
        place_and_dump(board, out, 0, Black, 12, 10, "center chain: black at 12,10");
        expect_eq(board.state_of_position(10, 10), White, "center chain: chain alive before final liberty");
        expect_eq(board.state_of_position(10, 11), White, "center chain: chain alive before final liberty");
        expect_eq(board.state_of_position(11, 10), White, "center chain: chain alive before final liberty");

        place_and_dump(board, out, 0, Black, 11, 11, "center chain: black at 11,11 captures chain");
        expect_eq(board.state_of_position(10, 10), 0, "center chain: first white removed");
        expect_eq(board.state_of_position(10, 11), 0, "center chain: second white removed");
        expect_eq(board.state_of_position(11, 10), 0, "center chain: third white removed");
    }

    void test_simple_ko_rejection(std::ofstream &out) {
        Board board{19};
        dump_board(out, "simple ko: initial board", board);

        place_and_dump(board, out, 0, White, 10, 10, "simple ko: white target");
        place_and_dump(board, out, 0, White, 9, 11, "simple ko: white above capture point");
        place_and_dump(board, out, 0, White, 10, 12, "simple ko: white right of capture point");
        place_and_dump(board, out, 0, White, 11, 11, "simple ko: white below capture point");
        place_and_dump(board, out, 0, Black, 9, 10, "simple ko: black above target");
        place_and_dump(board, out, 0, Black, 10, 9, "simple ko: black left of target");
        place_and_dump(board, out, 0, Black, 11, 10, "simple ko: black below target");

        place_and_dump(board, out, 0, Black, 10, 11, "simple ko: black captures one white");
        expect_eq(board.state_of_position(10, 10), 0, "simple ko: captured point is empty");
        expect_eq(board.state_of_position(10, 11), Black, "simple ko: capturing stone remains");

        place_and_dump(board, out, -4, White, 10, 10, "simple ko: immediate recapture is rejected");
        expect_eq(board.state_of_position(10, 10), 0, "simple ko: rejected recapture keeps captured point empty");
        expect_eq(board.state_of_position(10, 11), Black, "simple ko: rejected recapture keeps black stone");
    }

    void test_snapback_capture_two_then_one(std::ofstream &out) {
        Board board{19};
        dump_board(out, "snapback: initial board", board);

        place_and_dump(board, out, 0, White, 10, 10, "snapback: white chain first stone");
        place_and_dump(board, out, 0, White, 10, 11, "snapback: white chain second stone");
        place_and_dump(board, out, 0, White, 9, 9, "snapback: white above capture point");
        place_and_dump(board, out, 0, White, 10, 8, "snapback: white left of capture point");
        place_and_dump(board, out, 0, White, 11, 9, "snapback: white below capture point");
        place_and_dump(board, out, 0, Black, 9, 10, "snapback: black above chain");
        place_and_dump(board, out, 0, Black, 11, 10, "snapback: black below first chain stone");
        place_and_dump(board, out, 0, Black, 9, 11, "snapback: black above second chain stone");
        place_and_dump(board, out, 0, Black, 10, 12, "snapback: black right of chain");
        place_and_dump(board, out, 0, Black, 11, 11, "snapback: black below second chain stone");
        expect_eq(board.state_of_position(10, 10), White, "snapback: first white alive before capture");
        expect_eq(board.state_of_position(10, 11), White, "snapback: second white alive before capture");

        place_and_dump(board, out, 0, Black, 10, 9, "snapback: black captures two whites");
        expect_eq(board.state_of_position(10, 10), 0, "snapback: first white removed");
        expect_eq(board.state_of_position(10, 11), 0, "snapback: second white removed");
        expect_eq(board.state_of_position(10, 9), Black, "snapback: capturing black stone remains");

        place_and_dump(board, out, 0, White, 10, 10, "snapback: white immediately captures one back");
        expect_eq(board.state_of_position(10, 10), White, "snapback: white recapture is allowed");
        expect_eq(board.state_of_position(10, 9), 0, "snapback: black stone is removed");
        expect_eq(board.state_of_position(10, 11), 0, "snapback: other captured point stays empty");
    }
}

int main() {
    const char *output_path = "tests/test_placement.txt";
    std::ofstream out{output_path};
    if (!out) {
        output_path = "../tests/test_placement.txt";
        out.clear();
        out.open(output_path);
    }
    if (!out) {
        std::cerr << "cannot open test_placement.txt\n";
        return 1;
    }
    out << "output: " << output_path << '\n';

    test_board_size_validation();
    test_command_parse();
    test_go_notes_construction();
    test_reorder_branches_command();
    test_keep_main_line_command();
    test_clear_notes_command();
    test_go_notes_execute_and_undo();
    test_find_command_directions();
    test_preset_stone_export_and_record_tree_load();
    test_load_record_tree_preserves_uids();
    test_edit_current_preset_transaction();
    test_basic_placement(out);
    test_preset_stones(out);
    test_takeback_recovery(out);
    test_corner_single_capture(out);
    test_corner_chain_capture(out);
    test_edge_single_capture(out);
    test_edge_chain_capture(out);
    test_center_single_capture(out);
    test_center_chain_capture(out);
    test_simple_ko_rejection(out);
    test_snapback_capture_two_then_one(out);

    out << "\nAll placement tests passed.\n";
    return 0;
}
