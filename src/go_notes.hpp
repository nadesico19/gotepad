// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// 这是棋局检讨笔记的数据封装和算法实现。以GoCore引擎为基础，实现了多样化的棋盘操作命令，能够
// 回滚的操作均实现了undo逻辑。操作命令采用独立的类型封装和派生，方便GUI程序生成和提交。
// 笔记功能非严格对标SGF规范所支持的各种特性，支持一键导出到.pptx文件。

#ifndef GOBAN_GO_NOTES_HPP
#define GOBAN_GO_NOTES_HPP

#include "go_core.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <iterator>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

namespace nd::go {
using std::uint64_t;

// 所有消息统一在字符串前赋编号，今后做国际化时以这个编号为索引。
inline constexpr char kCommandAlreadyDoneMessage[] =
    "[GNE0001] command is already done";
inline constexpr char kPositionOutsideBoardMessage[] =
    "[GNE0002] position is outside the board";
inline constexpr char kPresetStoneFailedMessage[] =
    "[GNE0003] preset_stone failed";
inline constexpr char kCommandCannotBeUndoneMessage[] =
    "[GNE0004] command cannot be undone";
inline constexpr char kPresetStoneRecoveryFailedMessage[] =
    "[GNE0005] preset_stone recovery failed";
inline constexpr char kPlaceStoneFailedMessage[] =
    "[GNE0006] place_stone failed";
inline constexpr char kTakebackFailedMessage[] = "[GNE0007] takeback failed";
inline constexpr char kTakebackRecoveryFailedMessage[] =
    "[GNE0008] takeback recovery failed";
inline constexpr char kMoveAlreadyExistsMessage[] =
    "[GNE0009] move already exists";
inline constexpr char kRoamingFailedMessage[] = "[GNE0010] roaming failed";
inline constexpr char kInvalidCommandMessage[] = "[GNE0011] invalid command";
inline constexpr char kNoCommandToUndoMessage[] =
    "[GNE0012] no command to undo";
inline constexpr char kStoneNotFoundMessage[] =
    "[GNE0013] no move found at position";
inline constexpr char kNoCommandToRedoMessage[] =
    "[GNE0014] no command to redo";

inline constexpr char kNoteIndexOutOfRangeMessage[] =
    "[GNE0016] note index is out of range";
inline constexpr char kNotePositionOutsideBoardMessage[] =
    "[GNE0017] note mark position is outside the board";
inline constexpr char kSequentialMarkAlreadyExistsMessage[] =
    "[GNE0018] sequential mark already exists";
inline constexpr char kSequentialMarkNotFoundMessage[] =
    "[GNE0019] sequential mark does not exist";
inline constexpr char kSymbolMarkNotFoundMessage[] =
    "[GNE0020] symbol mark does not exist";
inline constexpr char kNoteRecoveryFailedMessage[] =
    "[GNE0021] note recovery failed";
inline constexpr char kCutBranchFailedMessage[] = "[GNE0022] cut branch failed";
inline constexpr char kPresetAlreadyExistsMessage[] =
    "[GNE0023] preset branch already exists";
inline constexpr char kNoteNumberingOutOfRangeMessage[] =
    "[GNE0024] note numbering option is out of range";
inline constexpr char kUnknownSgfMetadataFieldMessage[] =
    "[GNE0030] unknown SGF metadata field";
inline constexpr char kInvalidSgfMetadataValueMessage[] =
    "[GNE0031] invalid SGF metadata value";
inline constexpr char kSgfMetadataRecoveryFailedMessage[] =
    "[GNE0032] SGF metadata recovery failed";

inline constexpr uint8_t kNoteNumberingOptionCount = 4;

// 棋局局面笔记，含文字描述和各种标记。每一个棋局状态都可以有一个笔记列表，支持对同一局面进行
// 多层级的描述和标记。在SGF层面，位于第0层级的笔记将附加在落子节点上；从第1层级起的笔记则会
// 包含在紧跟落子节点的非落子节点上。客户端在实现笔记显示时，可以采用激活显示的形式，支持在棋盘
// 和界面上同时显示多个层级的笔记。但编辑时未避免混乱，应仅激活一个层级的笔记。
struct GoNotesRecord {
  // 棋子编号排版方式，对应客户端下拉框下标：0分支相对编号、
  // 1分支绝对编号、2全局绝对编号、3无编号。
  uint8_t numbering{};
  // 节点标题，对应SGF中的[N]，使用utf-8编码。
  std::string title{};
  // 长文本评论，对应SGF中的[C]，使用utf-8编码。
  std::string comment{};
  // 顺序符号标记集合，表示在棋盘上按顺序编号的位置标记。集合保存每个标记在棋盘上的位置，
  // 按（row，column）成对存放。每个标记的根据在集合中的下标进行编号，编号总数目限制到52，
  // 即与[A-Za-z]字符范围的个数一致，客户端也推荐按照这个字符集合显示编号。
  // 注意在GoNotes内部没有严格限制编号总数小于52，以及编号位置不可重叠，因此客户端需要自行
  // 考虑这些限制，处理这些情况。
  std::vector<std::pair<uint16_t, uint16_t>> sequential_marks{};
  // 符号标记集合。与sequential_marks不同，使用具体符号字符而非连续编号进行标记。
  // 集合总数原则上按棋盘交叉点个数进行限制，且每个交叉点只能有一种符号。符号使用字符串表达，
  // 支持SGF所规定的“TR”、“SQ”、“CR”、“MA”，分别对应三角、方框、圆圈、叉号标记。
  // 理论上也应支持任意的unicode码点字符，但目前客户端应优先支持上述4种SGF特别指定的符号。
  // 当客户端解析到4种符号对应的字符串时，将其按对应的图形进行显示。
  std::vector<std::tuple<uint16_t, uint16_t, std::string>> symbol_marks{};
};

// SGF根节点及GameInfo节点中的常用棋谱信息。所有字符串均使用UTF-8编码；数值类属性也保留
// SGF原始文本形式，以免读取再保存时丢失精度或原有表示。FF、GM、CA、SZ、AP、GP和XU由
// GoNotes保存器统一生成，不包含在此结构中。
struct GoNotesSgfMetadata {
  std::string game_name{};       // GN
  std::string event{};           // EV
  std::string round{};           // RO
  std::string date{};            // DT
  std::string place{};           // PC
  std::string result{};          // RE
  std::string rules{};           // RU
  std::string komi{};            // KM
  std::string handicap{};        // HA
  std::string time_limit{};      // TM
  std::string overtime{};        // OT
  std::string black_name{};      // PB
  std::string black_rank{};      // BR
  std::string black_team{};      // BT
  std::string white_name{};      // PW
  std::string white_rank{};      // WR
  std::string white_team{};      // WT
  std::string annotator{};       // AN
  std::string copyright{};       // CP
  std::string source{};          // SO
  std::string user{};            // US
  std::string game_comment{};    // GC
  std::string opening{};         // ON
  std::string variation_style{}; // ST
  std::string player_to_play{};  // PL，仅允许空字符串、"B"或"W"

  // 其他根节点自定义属性。键为属性名，值为该属性的原始值列表。
  std::unordered_map<std::string, std::vector<std::string>>
      extra_root_properties{};
};

// 只读棋盘快照。states和move_numbers均按照行优先顺序存储；move_numbers中的0表示
// 对应位置不显示手数。
struct GoNotesPositionSnapshot {
  int board_size{};
  std::vector<int> states{};
  std::vector<int> move_numbers{};
};

// 围棋笔记，实现对棋谱的多分支记录。
// GoNotes是GoCore状态的唯一修改边界；运行期操作统一通过Command执行并支持undo/redo。
class GoNotes {
public:
  // 定义围棋笔记支持的操作命令基类。
  class Command {
  public:
    virtual ~Command() = default;

    // 将字符串命令解析为具体命令实例，解析失败时返回空unique_ptr。命令示例：
    // - GoNotes::PresetCommand: "PRESET,1,4,4,2,16,16,0,10,10;"
    // - GoNotes::PlaceStoneCommand: "PLACESTONE,2,16,16;"
    // - GoNotes::TakebackCommand: "TAKEBACK;"
    // - GoNotes::CutBranchCommand: "CUTBRANCH,42;"
    // - GoNotes::RoamingCommand: "ROAMING,42;"
    // - GoNotes::FindCommand: "FIND,4,4;"或"FIND,-1,4,4;"
    // - GoNotes::FindCommand: "FIND,1,4,4;"
    [[nodiscard]] static std::unique_ptr<Command>
    parse(std::string_view command);

  private:
    friend class GoNotes;

    // 执行棋盘操作。成功时返回0；失败时由具体命令返回小于0的错误码，并通过
    // GoNotes::message()提供utf-8编码的结果信息。redo期间执行失败时会清空redo栈。
    [[nodiscard]] virtual int execute(GoNotes &go_notes) = 0;

    // 回滚棋盘操作。成功时返回0，失败时返回-1，并通过GoNotes::message()提供结果信息。
    // undo期间回滚失败时会清空undo栈和redo栈。
    [[nodiscard]] virtual int undo(GoNotes &go_notes) = 0;

    // execute之后为true，undo之后为false，用于防止命令被重复执行或回滚。
    bool done_{};
  };

  // 将一次完整的预置过程作为一个原子命令提交，对应GoCore的preset_stones函数。
  // 每个点位只需传入最终状态；undo会剪掉整个setup节点，redo会恢复原节点及uid。
  class PresetCommand final : public Command {
  public:
    explicit PresetCommand(std::vector<GoCorePresetStone> preset_stones)
        : preset_stones_(std::move(preset_stones)) {}
    PresetCommand(int color, size_t row, size_t column)
        : preset_stones_{{static_cast<uint16_t>(color),
                          static_cast<uint16_t>(row),
                          static_cast<uint16_t>(column)}} {}

  private:
    friend class GoNotes;
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;

    std::vector<GoCorePresetStone> preset_stones_{};
    // undo时保存被剪掉的完整setup子树，供redo按原uid恢复。
    std::vector<GoCoreRecord> takeback_records_{};
    // 已存在的等价预置子分支uid；不存在时为0。
    uint64_t existing_uid_{};
  };

  // 对应GoCore的place_stone函数，undo时使用takeback进行回滚。
  // 如果current_cursor_的下一手分支已经存在相同落子，直接place_stone会在undo时破坏记录树，
  // 因此execute返回-100，再由GoNotes把该操作转换成RoamingCommand。
  class PlaceStoneCommand final : public Command {
  public:
    PlaceStoneCommand(int color, size_t row, size_t column)
        : color_(color), row_(row), column_(column) {}

  private:
    friend class GoNotes;
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    int color_;
    size_t row_;
    size_t column_;

    // 已存在的下一手分支uid；不存在时为0。
    uint64_t existing_uid_{};
  };

  // 对应GoCore的takeback函数，undo时使用takeback_recovery进行回滚。
  class TakebackCommand final : public Command {
  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;

    // takeback返回的记录，用于undo时恢复局面。
    std::vector<GoCoreRecord> takeback_records_{};
  };

  // 剪掉指定uid节点及其全部子节点。execute先漫游至目标节点，再使用takeback删除子树；
  // undo使用takeback_recovery恢复子树，并漫游回命令首次执行时的局面。
  class CutBranchCommand final : public Command {
  public:
    explicit CutBranchCommand(uint64_t target_uid) : target_uid_(target_uid) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<GoCoreRecord> takeback_records_{};
    uint64_t target_uid_;
    uint64_t start_uid_{};
    bool start_uid_set_{};
  };

  // 调整指定父节点的直属分支顺序。首次执行时保存原始完整顺序，undo和redo均直接
  // 修改目标父节点，不依赖命令执行时GoNotes的当前游标位置。
  class ReorderBranchesCommand final : public Command {
  public:
    ReorderBranchesCommand(uint64_t parent_uid,
                           std::vector<uint64_t> ordered_uids)
        : parent_uid_(parent_uid), ordered_uids_(std::move(ordered_uids)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    uint64_t parent_uid_;
    std::vector<uint64_t> ordered_uids_{};
    std::vector<uint64_t> original_uids_{};
    bool original_uids_set_{};
  };

  // 对应GoCore的roaming_to函数，undo时恢复到last_uid_指向的棋局记录。
  class RoamingCommand final : public Command {
  public:
    explicit RoamingCommand(uint64_t target_uid) : target_uid_(target_uid) {}

  private:
    friend class GoNotes;
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    uint64_t target_uid_;
    uint64_t last_uid_{};
  };

  // 向前或向后找子功能。向前找子时，从当前局面朝父节点方向遍历，根据指定坐标找到对应落子记录，
  // 并漫游至该记录；向后找子时，从当前局面朝子节点方向遍历，每个子节点集合只取第一分支，直到
  // 找到该位置的落子记录，并漫游至该记录。若遍历到棋局起点或终点仍未找到时，不修改状态并返回-1；
  // 找到并成功漫游时返回0。
  class FindCommand final : public Command {
  public:
    enum class Direction {
      TowardParent = -1,
      TowardFirstChild = 1,
    };

    FindCommand(size_t row, size_t column)
        : FindCommand(Direction::TowardParent, row, column) {}
    FindCommand(Direction direction, size_t row, size_t column)
        : direction_(direction), row_(row), column_(column) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    Direction direction_;
    size_t row_;
    size_t column_;
    uint64_t target_uid_{};
    uint64_t last_uid_{};
  };

  // 在当前局面的笔记列表末尾追加一个空笔记。undo时删除同一层级的笔记。
  class AppendNote final : public Command {
  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    uint64_t target_uid_{};
    size_t note_index_{};
    bool target_set_{};
  };

  // 删除当前局面指定层级的笔记，并保存完整内容供undo恢复。
  class RemoveNote final : public Command {
  public:
    explicit RemoveNote(size_t note_index) : note_index_(note_index) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    GoNotesRecord removed_note_{};
    uint64_t target_uid_{};
    size_t note_index_;
    bool target_set_{};
  };

  // 更新当前局面对应笔记的长文本评论。
  // 注意由于笔记是一个列表，因此命令需要一个下标参数，用于获取列表中的具体笔记对象。
  // 如下标超出列表范围，不修改文本并返回-1。
  class UpdateComment final : public Command {
  public:
    UpdateComment(size_t note_index, std::string comment)
        : note_index_(note_index), comment_(std::move(comment)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::string old_comment_{};
    uint64_t target_uid_{};
    size_t note_index_;
    std::string comment_;
    bool target_set_{};
  };

  // 原子更新当前局面指定层级笔记的节点标题和长文本评论，使界面一次确认只产生一条
  // undo记录。
  class UpdateNoteText final : public Command {
  public:
    UpdateNoteText(size_t note_index, std::string title, std::string comment)
        : note_index_(note_index), title_(std::move(title)),
          comment_(std::move(comment)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::string old_title_{};
    std::string old_comment_{};
    uint64_t target_uid_{};
    size_t note_index_;
    std::string title_;
    std::string comment_;
    bool target_set_{};
  };

  // 更新当前局面指定层级笔记的棋子编号排版方式。
  class UpdateNoteNumbering final : public Command {
  public:
    UpdateNoteNumbering(size_t note_index, uint8_t numbering)
        : note_index_(note_index), numbering_(numbering) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    uint64_t target_uid_{};
    size_t note_index_;
    uint8_t numbering_;
    uint8_t old_numbering_{};
    bool target_set_{};
  };

  // 更新当前局面对应笔记的顺序符号标记集合。一次指定一个位置，将该位置插入当前集合中，插入前
  // 注意检查该位置是否已存在于集合中。支持删除已有位置的符号，因此参数需要有一个delete:bool，
  // 用于区分是添加新位置还是删除旧位置。
  // 对于客户端来说，当删除了旧位置的顺序符号标记，需要关注其余所有标记位置是否需要更新显示的
  // 符号。
  // 注意由于笔记是一个列表，因此命令需要一个下标参数，用于获取列表中的具体笔记对象。
  // 如下标超出列表范围，不修改文本并返回-1。
  class UpdateSequentialMarks final : public Command {
  public:
    UpdateSequentialMarks(size_t note_index, size_t row, size_t column,
                          bool delete_mark)
        : note_index_(note_index), row_(row), column_(column),
          delete_mark_(delete_mark) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<std::pair<uint16_t, uint16_t>> old_marks_{};
    uint64_t target_uid_{};
    size_t note_index_;
    size_t row_;
    size_t column_;
    bool delete_mark_;
    bool target_set_{};
  };

  // 更新当前局面对应笔记的符号标记集合。一次指定一个位置，对指定位置的标记内容进行更新。
  // 首先遍历当前集合，查看此位置是否已存在标记，若存在则将其标记内容更新为参数指定的符号；
  // 若不存在则插入新的标记数据；若参数指定了空字符串，则清除此位置的标记。
  // 注意由于笔记是一个列表，因此命令需要一个下标参数，用于获取列表中的具体笔记对象。
  // 如下标超出列表范围，不修改文本并返回-1。
  class UpdateSymbolMarks final : public Command {
  public:
    UpdateSymbolMarks(size_t note_index, size_t row, size_t column,
                      std::string symbol)
        : note_index_(note_index), row_(row), column_(column),
          symbol_(std::move(symbol)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<std::tuple<uint16_t, uint16_t, std::string>> old_marks_{};
    uint64_t target_uid_{};
    size_t note_index_;
    size_t row_;
    size_t column_;
    std::string symbol_;
    bool target_set_{};
  };

  // 原子替换当前局面指定层级笔记的完整顺序标记集合。用于客户端先编辑草稿，再通过一次
  // Command提交全部结果，使一次确认只对应一条undo记录。
  class ReplaceSequentialMarks final : public Command {
  public:
    ReplaceSequentialMarks(
        size_t note_index,
        std::vector<std::pair<uint16_t, uint16_t>> sequential_marks)
        : note_index_(note_index),
          sequential_marks_(std::move(sequential_marks)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<std::pair<uint16_t, uint16_t>> old_marks_{};
    uint64_t target_uid_{};
    size_t note_index_;
    std::vector<std::pair<uint16_t, uint16_t>> sequential_marks_;
    bool target_set_{};
  };

  // 原子替换当前局面指定层级笔记的完整符号标记集合。每个点位只能保留一种符号，
  // 空字符串不作为有效的最终标记。
  class ReplaceSymbolMarks final : public Command {
  public:
    ReplaceSymbolMarks(
        size_t note_index,
        std::vector<std::tuple<uint16_t, uint16_t, std::string>> symbol_marks)
        : note_index_(note_index), symbol_marks_(std::move(symbol_marks)) {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<std::tuple<uint16_t, uint16_t, std::string>> old_marks_{};
    uint64_t target_uid_{};
    size_t note_index_;
    std::vector<std::tuple<uint16_t, uint16_t, std::string>> symbol_marks_;
    bool target_set_{};
  };

  // 原子更新一项或多项SGF棋谱信息。字段使用GoNotesSgfMetadata成员的snake_case名称；
  // execute先校验全部字段再统一写入，确保失败时不会留下部分修改。undo恢复整批旧值。
  class UpdateSgfMetadataCommand final : public Command {
  public:
    explicit UpdateSgfMetadataCommand(
        std::vector<std::pair<std::string, std::string>> changes)
        : changes_(std::move(changes)) {}
    UpdateSgfMetadataCommand(std::string name, std::string value)
        : changes_{{std::move(name), std::move(value)}} {}

  private:
    [[nodiscard]] int execute(GoNotes &go_notes) override;
    [[nodiscard]] int undo(GoNotes &go_notes) override;
    std::vector<std::pair<std::string, std::string>> changes_{};
    std::vector<std::pair<std::string, std::string>> old_values_{};
  };

  explicit GoNotes(int ngrids) : go_core_(ngrids) {}

  // 从SGF文件创建完整的GoNotes。导入期间直接构造尚未对外发布的状态，不生成undo/redo记录；
  // 成功后游标位于第一分支的最后一个节点，失败时返回空unique_ptr并填写error_message。
  [[nodiscard]] static std::unique_ptr<GoNotes>
  from_sgf_file(const std::string &path, std::string &error_message);

  // 将完整记录树、笔记、标记和棋谱信息保存为UTF-8编码的SGF文件。保存成功返回true；
  // 失败返回false并填写error_message。保存操作不改变棋局状态及undo/redo记录。
  [[nodiscard]] bool save_sgf_file(const std::string &path,
                                   std::string &error_message) const;

  // 按B5横版出版模板，将记录树中所有可达笔记导出为PPTX。每层笔记生成一组页面；
  // 评论过长时自动生成续页。template_path为模板PPTX路径，导出不改变棋局状态及
  // undo/redo记录。成功返回true；失败返回false并填写error_message。
  [[nodiscard]] bool export_pptx_file(const std::string &path,
                                      const std::string &template_path,
                                      std::string &error_message) const;

  // 使用内存中的模板PPTX导出，供模板被打包在GUI资源容器中的客户端使用。
  [[nodiscard]] bool export_pptx_file(const std::string &path,
                                      const std::vector<uint8_t> &template_data,
                                      std::string &error_message) const;

  // 执行用户指定的棋盘操作命令，成功时将命令推送到undo_stack_。
  // PlaceStoneCommand返回-100且下一手分支存在相同落子时，会转换为RoamingCommand继续执行。
  // 连续的RoamingCommand会合并为一条命令。
  [[nodiscard]] int execute(std::unique_ptr<Command> command);

  // 解析并执行字符串命令，命令格式与Command::parse()一致。
  [[nodiscard]] int execute(std::string_view command);

  // 从undo_stack_取出最近的命令并执行undo，成功后将其推送到redo_stack_。
  // undo栈为空或undo失败时返回-1；undo失败时同时清空undo和redo栈。
  [[nodiscard]] int undo();

  // 从redo_stack_取出最近的命令并重新执行，成功后将其推回undo_stack_。
  // redo栈为空或执行失败时返回-1；执行失败时清空redo栈。
  [[nodiscard]] int redo();

  // 返回棋盘路数。
  [[nodiscard]] int board_size() const noexcept;

  // 返回指定坐标的当前状态；坐标超出棋盘时返回GoCore定义的错误值。
  [[nodiscard]] int state_at(size_t row, size_t column) const;

  // 返回最近一次操作生成的utf-8结果信息。
  [[nodiscard]] const std::string &message() const noexcept;

  // 返回当前棋局记录的uid。
  [[nodiscard]] uint64_t current_uid() const noexcept;

  // 从当前节点向棋局起点查找并返回最近一次真实落子的颜色；没有落子时返回0。
  [[nodiscard]] int latest_move_color() const;

  // 返回当前棋局记录的只读副本。
  [[nodiscard]] GoCoreRecordTreeNode current_node() const;

  // 返回指定uid记录的只读副本；uid不存在时返回std::nullopt。
  [[nodiscard]] std::optional<GoCoreRecordTreeNode> node_at(uint64_t uid) const;

  // 返回当前记录所有下一手分支的只读副本。
  [[nodiscard]] std::vector<GoCoreRecordTreeNode> next_moves() const;

  // 返回指定uid对应的笔记列表副本。没有笔记时返回空列表；悬空笔记仍可通过原uid读取。
  [[nodiscard]] std::vector<GoNotesRecord> notes_at(uint64_t uid) const;

  // 返回指定uid第一层笔记的标题；没有笔记时返回空字符串。
  [[nodiscard]] std::string first_note_title_at(uint64_t uid) const;

  // 返回SGF棋谱信息的只读引用。
  [[nodiscard]] const GoNotesSgfMetadata &sgf_metadata() const noexcept {
    return sgf_metadata_;
  }

  // 在GoCore副本上尝试落子，判断指定坐标是否合法，不修改GoNotes状态。
  [[nodiscard]] bool can_place_stone(int color, size_t row,
                                     size_t column) const;

  // 返回当前棋局是否允许预设棋子；允许时返回0，否则返回-1。
  [[nodiscard]] int can_preset_stone() const noexcept;

  // 分别表示当前是否有可执行的undo或redo命令。
  [[nodiscard]] bool can_undo() const noexcept;
  [[nodiscard]] bool can_redo() const noexcept;

  // 以current_cursor_为基准向上遍历至根节点，再从当前位置向下始终选择第一条分支，
  // 生成用于客户端线性棋局播放条的uid序列。
  [[nodiscard]] std::vector<uint64_t> straightforward_path() const;

  // 返回指定uid的盘面，不计算手数标记。此接口用于批量读取缩略盘面，避免复制完整记录树。
  [[nodiscard]] std::vector<int> position_states_at(uint64_t uid) const;

  // 返回指定uid的局面和手数标记。move_count大于0时最多向父节点遍历move_count-1步；
  // move_count为0时遍历到棋局起点。已被提走的棋子不会出现在move_numbers中。
  [[nodiscard]] GoNotesPositionSnapshot
  position_snapshot_at(uint64_t uid, size_t move_count) const;

private:
  [[nodiscard]] GoNotesRecord *note_at_(uint64_t uid, size_t note_index);
  [[nodiscard]] bool is_note_position_in_range_(size_t row,
                                                size_t column) const noexcept;
  void erase_empty_notes_at_(uint64_t uid);

  // 笔记表。允许保留takeback后暂时无法从记录树访问的悬空笔记，保存时再统一裁剪。
  std::unordered_map<uint64_t, std::vector<GoNotesRecord>> notes_{};

  // 从SGF读取或供后续保存使用的棋谱信息。
  GoNotesSgfMetadata sgf_metadata_{};

  // 棋盘核心引擎。
  GoCore go_core_;

  // 最近一次操作生成的结果信息，统一使用utf-8编码。
  std::string message_{};

  // 棋局当前记录的游标，仅由GoNotes及其嵌套Command维护。
  GoCoreRecordTreeNode current_cursor_{};

  // 支持undo/redo的操作命令栈。
  std::vector<std::unique_ptr<Command>> undo_stack_{};
  std::vector<std::unique_ptr<Command>> redo_stack_{};
};

inline std::unique_ptr<GoNotes::Command>
GoNotes::Command::parse(std::string_view command) {
  if (command.empty() || command.back() != ';')
    return nullptr;

  command.remove_suffix(1);
  constexpr std::string_view kMetadataPrefix = "UPDATEMETADATA,";
  if (command.compare(0, kMetadataPrefix.size(), kMetadataPrefix) == 0) {
    const auto name_begin = kMetadataPrefix.size();
    const auto value_separator = command.find(',', name_begin);
    if (value_separator == std::string_view::npos ||
        value_separator == name_begin) {
      return nullptr;
    }
    return std::make_unique<UpdateSgfMetadataCommand>(
        std::string{command.substr(name_begin, value_separator - name_begin)},
        std::string{command.substr(value_separator + 1)});
  }

  std::vector<std::string_view> fields{};
  size_t field_begin = 0;
  while (field_begin <= command.size()) {
    const auto separator = command.find(',', field_begin);
    const auto field_end =
        separator == std::string_view::npos ? command.size() : separator;
    fields.push_back(command.substr(field_begin, field_end - field_begin));
    if (separator == std::string_view::npos)
      break;
    field_begin = separator + 1;
  }

  auto parse_integer = [](std::string_view text, auto &value) {
    if (text.empty())
      return false;
    const auto [ptr, error] =
        std::from_chars(text.data(), text.data() + text.size(), value);
    return error == std::errc{} && ptr == text.data() + text.size();
  };

  if (fields.size() >= 4 && fields[0] == "PRESET" &&
      (fields.size() - 1) % 3 == 0) {
    std::vector<GoCorePresetStone> preset_stones{};
    preset_stones.reserve((fields.size() - 1) / 3);
    for (size_t index = 1; index < fields.size(); index += 3) {
      int color{};
      size_t row{};
      size_t column{};
      if (!parse_integer(fields[index], color) ||
          !parse_integer(fields[index + 1], row) ||
          !parse_integer(fields[index + 2], column) || color < 0 || color > 2 ||
          row > std::numeric_limits<uint16_t>::max() ||
          column > std::numeric_limits<uint16_t>::max()) {
        return nullptr;
      }
      preset_stones.push_back({static_cast<uint16_t>(color),
                               static_cast<uint16_t>(row),
                               static_cast<uint16_t>(column)});
    }
    return std::make_unique<PresetCommand>(std::move(preset_stones));
  } else if (fields.size() == 4 && fields[0] == "PLACESTONE") {
    int color{};
    size_t row{};
    size_t column{};
    if (parse_integer(fields[1], color) && parse_integer(fields[2], row) &&
        parse_integer(fields[3], column)) {
      return std::make_unique<PlaceStoneCommand>(color, row, column);
    }
  } else if (fields.size() == 1 && fields[0] == "TAKEBACK") {
    return std::make_unique<TakebackCommand>();
  } else if (fields.size() == 2 && fields[0] == "CUTBRANCH") {
    uint64_t target_uid{};
    if (parse_integer(fields[1], target_uid))
      return std::make_unique<CutBranchCommand>(target_uid);
  } else if (fields.size() == 2 && fields[0] == "ROAMING") {
    uint64_t target_uid{};
    if (parse_integer(fields[1], target_uid))
      return std::make_unique<RoamingCommand>(target_uid);
  } else if (fields.size() == 3 && fields[0] == "FIND") {
    size_t row{};
    size_t column{};
    if (parse_integer(fields[1], row) && parse_integer(fields[2], column))
      return std::make_unique<FindCommand>(row, column);
  } else if (fields.size() == 4 && fields[0] == "FIND") {
    int direction{};
    size_t row{};
    size_t column{};
    if (parse_integer(fields[1], direction) &&
        (direction == -1 || direction == 1) && parse_integer(fields[2], row) &&
        parse_integer(fields[3], column)) {
      return std::make_unique<FindCommand>(
          static_cast<FindCommand::Direction>(direction), row, column);
    }
  }

  return nullptr;
}

inline int GoNotes::PresetCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (preset_stones_.empty()) {
    go_notes.message_ = kPresetStoneFailedMessage;
    return -1;
  }

  if (!takeback_records_.empty()) {
    if (go_notes.go_core_.takeback_recovery(takeback_records_) != 0) {
      go_notes.message_ = kPresetStoneRecoveryFailedMessage;
      return -1;
    }
  } else {
    existing_uid_ =
        go_notes.go_core_.matching_preset_branch_uid(preset_stones_);
    if (existing_uid_ != 0) {
      go_notes.message_ = kPresetAlreadyExistsMessage;
      return -100;
    }

    const auto previous_uid = go_notes.current_cursor_.uid;
    const auto result = go_notes.go_core_.preset_stones(preset_stones_);
    if (result != 0) {
      if (result == -1) {
        existing_uid_ =
            go_notes.go_core_.matching_preset_branch_uid(preset_stones_);
        if (existing_uid_ != 0) {
          go_notes.message_ = kPresetAlreadyExistsMessage;
          return -100;
        }
      }
      go_notes.message_ = result == -2 ? kPositionOutsideBoardMessage
                                       : kPresetStoneFailedMessage;
      return result;
    }
    GoCoreRecordTreeNode current{};
    if (current.move_current(go_notes.go_core_) != 0 ||
        current.uid == previous_uid) {
      go_notes.message_ = kPresetStoneFailedMessage;
      return -1;
    }
  }

  if (go_notes.current_cursor_.move_current(go_notes.go_core_) != 0 ||
      go_notes.current_cursor_.color != 0) {
    go_notes.message_ = kPresetStoneFailedMessage;
    return -1;
  }
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::PresetCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  takeback_records_ = go_notes.go_core_.takeback();
  if (takeback_records_.empty() || takeback_records_.front().color != 0) {
    go_notes.message_ = kPresetStoneRecoveryFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::PlaceStoneCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }

  existing_uid_ = 0;
  for (const auto &child : go_notes.current_cursor_.children) {
    if (child.color == color_ && child.row == row_ && child.column == column_) {
      existing_uid_ = child.uid;
      go_notes.message_ = kMoveAlreadyExistsMessage;
      return -100;
    }
  }
  if (const auto result = go_notes.go_core_.place_stone(color_, row_, column_);
      result != 0) {
    go_notes.message_ = kPlaceStoneFailedMessage;
    return result;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::PlaceStoneCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  if (go_notes.go_core_.takeback().empty()) {
    go_notes.message_ = kTakebackFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::TakebackCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }

  takeback_records_ = go_notes.go_core_.takeback();
  if (takeback_records_.empty()) {
    go_notes.message_ = kTakebackFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::TakebackCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  if (go_notes.go_core_.takeback_recovery(takeback_records_) != 0) {
    go_notes.message_ = kTakebackRecoveryFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::CutBranchCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!start_uid_set_) {
    start_uid_ = go_notes.current_cursor_.uid;
    start_uid_set_ = true;
  }
  if (go_notes.go_core_.roaming_to(target_uid_) != 0) {
    go_notes.message_ = kRoamingFailedMessage;
    return -1;
  }

  takeback_records_ = go_notes.go_core_.takeback();
  if (takeback_records_.empty()) {
    if (go_notes.go_core_.roaming_to(start_uid_) != 0) {
      (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
      go_notes.message_ = kRoamingFailedMessage;
      return -1;
    }
    (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
    go_notes.message_ = kCutBranchFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::CutBranchCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  if (go_notes.go_core_.takeback_recovery(takeback_records_) != 0) {
    go_notes.message_ = kTakebackRecoveryFailedMessage;
    return -1;
  }
  if (go_notes.go_core_.roaming_to(start_uid_) != 0) {
    (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
    go_notes.message_ = kRoamingFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReorderBranchesCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!original_uids_set_) {
    const auto parent = go_notes.node_at(parent_uid_);
    if (parent) {
      original_uids_.reserve(parent->children.size());
      for (const auto &child : parent->children)
        original_uids_.push_back(child.uid);
    }
    original_uids_set_ = true;
  }

  (void)go_notes.go_core_.reorder_next_records(parent_uid_, ordered_uids_);
  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReorderBranchesCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }

  (void)go_notes.go_core_.reorder_next_records(parent_uid_, original_uids_);
  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::RoamingCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }

  const auto previous_uid = go_notes.current_cursor_.uid;
  if (const auto result = go_notes.go_core_.roaming_to(target_uid_);
      result != 0) {
    go_notes.message_ = kRoamingFailedMessage;
    return result;
  }

  last_uid_ = previous_uid;
  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::RoamingCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  if (go_notes.go_core_.roaming_to(last_uid_) != 0) {
    go_notes.message_ = kRoamingFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::FindCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }

  auto cursor = go_notes.current_cursor_;
  target_uid_ = 0;
  if (direction_ == Direction::TowardParent) {
    while (cursor.uid != 0) {
      if (cursor.row == row_ && cursor.column == column_) {
        target_uid_ = cursor.uid;
        break;
      }
      if (cursor.move_back(go_notes.go_core_) != 0) {
        go_notes.message_ = kStoneNotFoundMessage;
        return -1;
      }
    }
  } else {
    while (!cursor.children.empty()) {
      const auto next_uid = cursor.children.front().uid;
      if (cursor.move_to(go_notes.go_core_, next_uid) != 0) {
        go_notes.message_ = kStoneNotFoundMessage;
        return -1;
      }
      if (cursor.row == row_ && cursor.column == column_) {
        target_uid_ = cursor.uid;
        break;
      }
    }
  }
  if (target_uid_ == 0) {
    go_notes.message_ = kStoneNotFoundMessage;
    return -1;
  }

  last_uid_ = go_notes.current_cursor_.uid;
  if (go_notes.go_core_.roaming_to(target_uid_) != 0) {
    go_notes.message_ = kRoamingFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::FindCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  if (go_notes.go_core_.roaming_to(last_uid_) != 0) {
    go_notes.message_ = kRoamingFailedMessage;
    return -1;
  }

  (void)go_notes.current_cursor_.move_current(go_notes.go_core_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::AppendNote::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    note_index_ = go_notes.notes_[target_uid_].size();
    target_set_ = true;
  }

  auto &notes = go_notes.notes_[target_uid_];
  if (notes.size() != note_index_) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }
  notes.emplace_back();
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::AppendNote::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto notes_it = go_notes.notes_.find(target_uid_);
  if (notes_it == go_notes.notes_.end() ||
      notes_it->second.size() != note_index_ + 1) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  notes_it->second.pop_back();
  go_notes.erase_empty_notes_at_(target_uid_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::RemoveNote::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }

  removed_note_ = std::move(*note);
  auto &notes = go_notes.notes_.at(target_uid_);
  notes.erase(notes.begin() + static_cast<std::ptrdiff_t>(note_index_));
  go_notes.erase_empty_notes_at_(target_uid_);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::RemoveNote::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto &notes = go_notes.notes_[target_uid_];
  if (note_index_ > notes.size()) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  notes.insert(notes.begin() + static_cast<std::ptrdiff_t>(note_index_),
               std::move(removed_note_));
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateComment::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }

  old_comment_ = std::move(note->comment);
  note->comment = comment_;
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateComment::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  note->comment = std::move(old_comment_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateNoteText::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }

  old_title_ = std::move(note->title);
  old_comment_ = std::move(note->comment);
  note->title = title_;
  note->comment = comment_;
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateNoteText::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  note->title = std::move(old_title_);
  note->comment = std::move(old_comment_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateNoteNumbering::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (numbering_ >= kNoteNumberingOptionCount) {
    go_notes.message_ = kNoteNumberingOutOfRangeMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }

  old_numbering_ = note->numbering;
  note->numbering = numbering_;
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateNoteNumbering::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  note->numbering = old_numbering_;
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSequentialMarks::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }
  if (!go_notes.is_note_position_in_range_(row_, column_)) {
    go_notes.message_ = kNotePositionOutsideBoardMessage;
    return -1;
  }

  const auto position = std::make_pair(static_cast<uint16_t>(row_),
                                       static_cast<uint16_t>(column_));
  const auto mark_it = std::find(note->sequential_marks.begin(),
                                 note->sequential_marks.end(), position);
  if (!delete_mark_ && mark_it != note->sequential_marks.end()) {
    go_notes.message_ = kSequentialMarkAlreadyExistsMessage;
    return -1;
  }
  if (delete_mark_ && mark_it == note->sequential_marks.end()) {
    go_notes.message_ = kSequentialMarkNotFoundMessage;
    return -1;
  }

  old_marks_ = note->sequential_marks;
  if (delete_mark_)
    note->sequential_marks.erase(mark_it);
  else
    note->sequential_marks.push_back(position);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSequentialMarks::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  note->sequential_marks = std::move(old_marks_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSymbolMarks::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }
  if (!go_notes.is_note_position_in_range_(row_, column_)) {
    go_notes.message_ = kNotePositionOutsideBoardMessage;
    return -1;
  }

  const auto mark_it = std::find_if(
      note->symbol_marks.begin(), note->symbol_marks.end(),
      [this](const auto &mark) {
        return std::get<0>(mark) == row_ && std::get<1>(mark) == column_;
      });
  if (symbol_.empty() && mark_it == note->symbol_marks.end()) {
    go_notes.message_ = kSymbolMarkNotFoundMessage;
    return -1;
  }

  old_marks_ = note->symbol_marks;
  if (symbol_.empty()) {
    note->symbol_marks.erase(mark_it);
  } else if (mark_it == note->symbol_marks.end()) {
    note->symbol_marks.emplace_back(static_cast<uint16_t>(row_),
                                    static_cast<uint16_t>(column_), symbol_);
  } else {
    std::get<2>(*mark_it) = symbol_;
  }
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSymbolMarks::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }

  note->symbol_marks = std::move(old_marks_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReplaceSequentialMarks::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }
  if (sequential_marks_.size() > 52) {
    go_notes.message_ = kInvalidCommandMessage;
    return -1;
  }
  for (size_t index = 0; index < sequential_marks_.size(); ++index) {
    const auto &[row, column] = sequential_marks_[index];
    if (!go_notes.is_note_position_in_range_(row, column)) {
      go_notes.message_ = kNotePositionOutsideBoardMessage;
      return -1;
    }
    if (std::find(sequential_marks_.begin(),
                  sequential_marks_.begin() +
                      static_cast<std::ptrdiff_t>(index),
                  sequential_marks_[index]) !=
        sequential_marks_.begin() + static_cast<std::ptrdiff_t>(index)) {
      go_notes.message_ = kSequentialMarkAlreadyExistsMessage;
      return -1;
    }
  }

  old_marks_ = std::move(note->sequential_marks);
  note->sequential_marks = sequential_marks_;
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReplaceSequentialMarks::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }
  note->sequential_marks = std::move(old_marks_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReplaceSymbolMarks::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }
  if (!target_set_) {
    target_uid_ = go_notes.current_cursor_.uid;
    target_set_ = true;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteIndexOutOfRangeMessage;
    return -1;
  }
  for (size_t index = 0; index < symbol_marks_.size(); ++index) {
    const auto &[row, column, symbol] = symbol_marks_[index];
    if (!go_notes.is_note_position_in_range_(row, column)) {
      go_notes.message_ = kNotePositionOutsideBoardMessage;
      return -1;
    }
    if (symbol.empty()) {
      go_notes.message_ = kInvalidCommandMessage;
      return -1;
    }
    const auto duplicate = std::find_if(
        symbol_marks_.begin(),
        symbol_marks_.begin() + static_cast<std::ptrdiff_t>(index),
        [row, column](const auto &mark) {
          return std::get<0>(mark) == row && std::get<1>(mark) == column;
        });
    if (duplicate !=
        symbol_marks_.begin() + static_cast<std::ptrdiff_t>(index)) {
      go_notes.message_ = kInvalidCommandMessage;
      return -1;
    }
  }

  old_marks_ = std::move(note->symbol_marks);
  note->symbol_marks = symbol_marks_;
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::ReplaceSymbolMarks::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }
  auto *note = go_notes.note_at_(target_uid_, note_index_);
  if (note == nullptr) {
    go_notes.message_ = kNoteRecoveryFailedMessage;
    return -1;
  }
  note->symbol_marks = std::move(old_marks_);
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSgfMetadataCommand::execute(GoNotes &go_notes) {
  if (done_) {
    go_notes.message_ = kCommandAlreadyDoneMessage;
    return -1;
  }

  using MetadataMember = std::string GoNotesSgfMetadata::*;
  static constexpr std::pair<std::string_view, MetadataMember> kFields[] = {
      {"game_name", &GoNotesSgfMetadata::game_name},
      {"event", &GoNotesSgfMetadata::event},
      {"round", &GoNotesSgfMetadata::round},
      {"date", &GoNotesSgfMetadata::date},
      {"place", &GoNotesSgfMetadata::place},
      {"result", &GoNotesSgfMetadata::result},
      {"rules", &GoNotesSgfMetadata::rules},
      {"komi", &GoNotesSgfMetadata::komi},
      {"handicap", &GoNotesSgfMetadata::handicap},
      {"time_limit", &GoNotesSgfMetadata::time_limit},
      {"overtime", &GoNotesSgfMetadata::overtime},
      {"black_name", &GoNotesSgfMetadata::black_name},
      {"black_rank", &GoNotesSgfMetadata::black_rank},
      {"black_team", &GoNotesSgfMetadata::black_team},
      {"white_name", &GoNotesSgfMetadata::white_name},
      {"white_rank", &GoNotesSgfMetadata::white_rank},
      {"white_team", &GoNotesSgfMetadata::white_team},
      {"annotator", &GoNotesSgfMetadata::annotator},
      {"copyright", &GoNotesSgfMetadata::copyright},
      {"source", &GoNotesSgfMetadata::source},
      {"user", &GoNotesSgfMetadata::user},
      {"game_comment", &GoNotesSgfMetadata::game_comment},
      {"opening", &GoNotesSgfMetadata::opening},
  };
  const auto member_for =
      [](std::string_view name) -> std::optional<MetadataMember> {
    for (const auto &[field_name, member] : kFields) {
      if (field_name == name)
        return member;
    }
    return std::nullopt;
  };
  const auto valid_real = [](const std::string &value,
                             bool require_nonnegative) {
    if (value.empty())
      return true;
    try {
      size_t parsed{};
      const auto number = std::stod(value, &parsed);
      return parsed == value.size() && std::isfinite(number) &&
             (!require_nonnegative || number >= 0.0);
    } catch (...) {
      return false;
    }
  };
  const auto valid_result = [&valid_real](const std::string &value) {
    if (value.empty() || value == "0" || value == "Draw" || value == "Void" ||
        value == "?") {
      return true;
    }
    if (value.size() <= 2 || (value[0] != 'B' && value[0] != 'W') ||
        value[1] != '+') {
      return false;
    }
    const auto suffix = value.substr(2);
    if (suffix == "R" || suffix == "Resign" || suffix == "T" ||
        suffix == "Time" || suffix == "F" || suffix == "Forfeit") {
      return true;
    }
    return valid_real(suffix, true);
  };

  std::vector<std::pair<std::string, std::string>> normalized{};
  normalized.reserve(changes_.size());
  for (const auto &[name, value] : changes_) {
    if (!member_for(name)) {
      go_notes.message_ = kUnknownSgfMetadataFieldMessage;
      return -1;
    }
    const auto duplicate = std::find_if(
        normalized.begin(), normalized.end(),
        [&name](const auto &change) { return change.first == name; });
    if (duplicate == normalized.end())
      normalized.emplace_back(name, value);
    else
      duplicate->second = value;
  }
  for (const auto &[name, value] : normalized) {
    bool valid = true;
    if (name == "komi")
      valid = valid_real(value, false);
    else if (name == "time_limit")
      valid = valid_real(value, true);
    else if (name == "handicap") {
      if (!value.empty()) {
        int handicap{};
        const auto [end, error] = std::from_chars(
            value.data(), value.data() + value.size(), handicap);
        valid = error == std::errc{} && end == value.data() + value.size() &&
                handicap >= 0;
      }
    } else if (name == "result") {
      valid = valid_result(value);
    }
    if (!valid) {
      go_notes.message_ = kInvalidSgfMetadataValueMessage;
      return -1;
    }
  }

  old_values_.clear();
  old_values_.reserve(normalized.size());
  for (const auto &[name, value] : normalized) {
    const auto member = *member_for(name);
    old_values_.emplace_back(name, go_notes.sgf_metadata_.*member);
    go_notes.sgf_metadata_.*member = value;
  }
  changes_ = std::move(normalized);
  done_ = true;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::UpdateSgfMetadataCommand::undo(GoNotes &go_notes) {
  if (!done_) {
    go_notes.message_ = kCommandCannotBeUndoneMessage;
    return -1;
  }

  using MetadataMember = std::string GoNotesSgfMetadata::*;
  static constexpr std::pair<std::string_view, MetadataMember> kFields[] = {
      {"game_name", &GoNotesSgfMetadata::game_name},
      {"event", &GoNotesSgfMetadata::event},
      {"round", &GoNotesSgfMetadata::round},
      {"date", &GoNotesSgfMetadata::date},
      {"place", &GoNotesSgfMetadata::place},
      {"result", &GoNotesSgfMetadata::result},
      {"rules", &GoNotesSgfMetadata::rules},
      {"komi", &GoNotesSgfMetadata::komi},
      {"handicap", &GoNotesSgfMetadata::handicap},
      {"time_limit", &GoNotesSgfMetadata::time_limit},
      {"overtime", &GoNotesSgfMetadata::overtime},
      {"black_name", &GoNotesSgfMetadata::black_name},
      {"black_rank", &GoNotesSgfMetadata::black_rank},
      {"black_team", &GoNotesSgfMetadata::black_team},
      {"white_name", &GoNotesSgfMetadata::white_name},
      {"white_rank", &GoNotesSgfMetadata::white_rank},
      {"white_team", &GoNotesSgfMetadata::white_team},
      {"annotator", &GoNotesSgfMetadata::annotator},
      {"copyright", &GoNotesSgfMetadata::copyright},
      {"source", &GoNotesSgfMetadata::source},
      {"user", &GoNotesSgfMetadata::user},
      {"game_comment", &GoNotesSgfMetadata::game_comment},
      {"opening", &GoNotesSgfMetadata::opening},
  };
  for (const auto &[name, value] : old_values_) {
    const auto field =
        std::find_if(std::begin(kFields), std::end(kFields),
                     [&name](const auto &item) { return item.first == name; });
    if (field == std::end(kFields)) {
      go_notes.message_ = kSgfMetadataRecoveryFailedMessage;
      return -1;
    }
    go_notes.sgf_metadata_.*(field->second) = value;
  }
  done_ = false;
  go_notes.message_.clear();
  return 0;
}

inline int GoNotes::execute(std::unique_ptr<Command> command) {
  if (!command) {
    message_ = kInvalidCommandMessage;
    return -1;
  }

  auto result = command->execute(*this);
  if (result == -100) {
    uint64_t existing_uid{};
    if (const auto *place_command =
            dynamic_cast<const PlaceStoneCommand *>(command.get())) {
      existing_uid = place_command->existing_uid_;
    } else if (const auto *preset_command =
                   dynamic_cast<const PresetCommand *>(command.get())) {
      existing_uid = preset_command->existing_uid_;
    }
    if (existing_uid == 0)
      return result;
    command = std::make_unique<RoamingCommand>(existing_uid);
    result = command->execute(*this);
  }
  if (result != 0)
    return result;

  redo_stack_.clear();
  const auto *roaming = dynamic_cast<const RoamingCommand *>(command.get());
  auto *previous_roaming =
      undo_stack_.empty()
          ? nullptr
          : dynamic_cast<RoamingCommand *>(undo_stack_.back().get());
  if (roaming != nullptr && previous_roaming != nullptr) {
    previous_roaming->target_uid_ = roaming->target_uid_;
    if (previous_roaming->target_uid_ == previous_roaming->last_uid_)
      undo_stack_.pop_back();
  } else {
    undo_stack_.push_back(std::move(command));
  }
  return 0;
}

inline int GoNotes::execute(std::string_view command) {
  return execute(Command::parse(command));
}

inline int GoNotes::undo() {
  if (undo_stack_.empty()) {
    message_ = kNoCommandToUndoMessage;
    return -1;
  }

  auto command = std::move(undo_stack_.back());
  undo_stack_.pop_back();
  if (const auto result = command->undo(*this); result != 0) {
    undo_stack_.clear();
    redo_stack_.clear();
    return result;
  }

  redo_stack_.push_back(std::move(command));
  return 0;
}

inline int GoNotes::redo() {
  if (redo_stack_.empty()) {
    message_ = kNoCommandToRedoMessage;
    return -1;
  }

  auto command = std::move(redo_stack_.back());
  redo_stack_.pop_back();
  if (const auto result = command->execute(*this); result != 0) {
    redo_stack_.clear();
    return result;
  }

  undo_stack_.push_back(std::move(command));
  return 0;
}

inline int GoNotes::board_size() const noexcept { return go_core_.ngrids(); }

inline int GoNotes::state_at(size_t row, size_t column) const {
  return go_core_.state_of_position(row, column);
}

inline const std::string &GoNotes::message() const noexcept { return message_; }

inline uint64_t GoNotes::current_uid() const noexcept {
  return current_cursor_.uid;
}

inline int GoNotes::latest_move_color() const {
  auto cursor = current_cursor_;
  while (cursor.uid != 0) {
    if (cursor.color == 1 || cursor.color == 2)
      return cursor.color;
    if (cursor.move_back(go_core_) != 0)
      return 0;
  }
  return 0;
}
inline GoCoreRecordTreeNode GoNotes::current_node() const {
  return current_cursor_;
}

inline std::optional<GoCoreRecordTreeNode>
GoNotes::node_at(uint64_t uid) const {
  GoCoreRecordTreeNode node{};
  if (node.move_to(go_core_, uid) != 0)
    return std::nullopt;
  return node;
}

inline std::vector<GoCoreRecordTreeNode> GoNotes::next_moves() const {
  return current_cursor_.children;
}

inline std::vector<GoNotesRecord> GoNotes::notes_at(uint64_t uid) const {
  const auto notes_it = notes_.find(uid);
  return notes_it == notes_.end() ? std::vector<GoNotesRecord>{}
                                  : notes_it->second;
}

inline std::string GoNotes::first_note_title_at(uint64_t uid) const {
  const auto notes_it = notes_.find(uid);
  return notes_it == notes_.end() || notes_it->second.empty()
             ? std::string{}
             : notes_it->second.front().title;
}

inline GoNotesRecord *GoNotes::note_at_(uint64_t uid, size_t note_index) {
  const auto notes_it = notes_.find(uid);
  if (notes_it == notes_.end() || note_index >= notes_it->second.size())
    return nullptr;
  return &notes_it->second[note_index];
}

inline bool GoNotes::is_note_position_in_range_(size_t row,
                                                size_t column) const noexcept {
  const auto board_size = static_cast<size_t>(go_core_.ngrids());
  return row >= 1 && row <= board_size && column >= 1 && column <= board_size;
}

inline void GoNotes::erase_empty_notes_at_(uint64_t uid) {
  const auto notes_it = notes_.find(uid);
  if (notes_it != notes_.end() && notes_it->second.empty())
    notes_.erase(notes_it);
}

inline bool GoNotes::can_place_stone(int color, size_t row,
                                     size_t column) const {
  auto snapshot = go_core_;
  return snapshot.place_stone(color, row, column) == 0;
}

inline int GoNotes::can_preset_stone() const noexcept {
  return go_core_.can_preset_stone();
}

inline bool GoNotes::can_undo() const noexcept { return !undo_stack_.empty(); }

inline bool GoNotes::can_redo() const noexcept { return !redo_stack_.empty(); }

inline std::vector<uint64_t> GoNotes::straightforward_path() const {
  GoCoreRecordTreeNode cursor{};
  if (cursor.move_to(go_core_, current_cursor_.uid) != 0)
    return {};

  std::vector<uint64_t> path{cursor.uid};
  while (cursor.uid != 0) {
    if (cursor.move_back(go_core_) != 0)
      return {};
    path.push_back(cursor.uid);
  }
  std::reverse(path.begin(), path.end());

  if (cursor.move_to(go_core_, current_cursor_.uid) != 0)
    return {};
  while (!cursor.children.empty()) {
    const auto next_uid = cursor.children.front().uid;
    if (cursor.move_to(go_core_, next_uid) != 0)
      return {};
    path.push_back(cursor.uid);
  }
  return path;
}

inline std::vector<int> GoNotes::position_states_at(uint64_t uid) const {
  return go_core_.position_states_at(uid);
}

inline GoNotesPositionSnapshot
GoNotes::position_snapshot_at(uint64_t uid, size_t move_count) const {
  auto snapshot = go_core_;
  if (snapshot.roaming_to(uid) != 0)
    return {};

  GoNotesPositionSnapshot result{};
  result.board_size = snapshot.ngrids();
  const auto position_count = static_cast<size_t>(result.board_size) *
                              static_cast<size_t>(result.board_size);
  result.states.resize(position_count);
  result.move_numbers.resize(position_count);
  size_t position_index = 0;
  for (int row = 1; row <= result.board_size; ++row) {
    for (int column = 1; column <= result.board_size; ++column)
      result.states[position_index++] = snapshot.state_of_position(row, column);
  }

  GoCoreRecordTreeNode cursor{};
  if (cursor.move_to(snapshot, uid) != 0)
    return {};

  std::vector<GoCoreRecordTreeNode> moves{};
  while (cursor.uid != 0 && (move_count == 0 || moves.size() < move_count)) {
    if (cursor.color == 1 || cursor.color == 2)
      moves.push_back(cursor);
    if (cursor.move_back(snapshot) != 0)
      return {};
  }
  std::reverse(moves.begin(), moves.end());

  int move_number = 0;
  for (const auto &move : moves) {
    ++move_number;
    if (snapshot.state_of_position(move.row, move.column) != move.color)
      continue;
    const auto index = static_cast<size_t>(move.row - 1) *
                           static_cast<size_t>(result.board_size) +
                       static_cast<size_t>(move.column - 1);
    result.move_numbers[index] = move_number;
  }
  return result;
}
} // namespace nd::go

#endif // GOBAN_GO_NOTES_HPP
