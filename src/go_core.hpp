// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// 这是围棋棋盘核心引擎的数据封装和算法实现，主要实现以下功能：
// - 使用每个交叉点2bit的紧凑数组保存棋盘状态，并在有效棋盘外围设置一圈
//   哨兵点位，简化棋链遍历、数气和边界判断。
// - 实现黑白落子、提子、自杀检测和劫争禁入检测；非法操作不会改变现有棋盘状态。
// - 将落子以及AB、AW、AE一类预置操作统一记录为棋盘状态节点，支持多分支棋谱；
//   不改变棋盘状态的事件（例如停着）不进入记录树。
// - 支持预置操作的合并与等价分支检测，并保证预置后的最终盘面不存在无气棋块。
// - 支持悔棋、悔棋恢复、分支剪切所需的子树保存，以及在不同分支和任意记录节点
//   之间漫游。
// - 提供记录树的导入、导出和直属分支排序接口，供记谱、SGF转换及上层GUI使用。
// - 提供只读盘面查询、记录树游标和字符棋盘输出，方便客户端展示、遍历与调试。
// 注意这不是一个高性能的实现方案，主要面向常规对局和棋局检讨类的应用场景，不适合于AI训练场景。

#ifndef GOBAN_GO_CORE_HPP
#define GOBAN_GO_CORE_HPP

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iosfwd>
#include <limits>
#include <ostream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace nd::go {
using std::size_t;
using std::uint16_t;
using std::uint64_t;
using std::uint8_t;

// 棋盘预置操作。color为0、1、2时分别表示清空、设置黑子、设置白子。
struct GoCorePresetStone {
  uint16_t color{};
  uint16_t row{};
  uint16_t column{};
};

inline bool operator==(const GoCorePresetStone &left,
                       const GoCorePresetStone &right) noexcept {
  return left.color == right.color && left.row == right.row &&
         left.column == right.column;
}

// 棋盘状态变更记录。color为1或2时是落子记录，为0时是预置记录。
struct GoCoreRecord {
  // 所有记录中唯一的ID值，使用递增的无符号整数实现，用于替代指针使用。
  uint64_t uid{};
  // 上一手落子记录的uid值，用于反向遍历。0代表树形结构的根节点。
  uint64_t last_uid{};
  // 棋子颜色，以整数1为黑子，2为白子，二进制上对应01和10，与棋盘坐标点数组的值定义一致。
  // 注意：color为0时代表此记录存放的是预置棋子信息。
  uint16_t color{};
  // 落子位置，即GoCore#grids_中有效落子点位的下标。有效点位不包含棋盘外围追加的一圈哨兵点位。
  // 由于GoCore按照SGF
  // FF[4]将棋盘尺寸限制到52路以内，因此16位无符号整数可以满足需求。
  // 注意这个值由row*棋盘存储行宽+column算出，row和column范围都在棋盘有效路数内。
  // 棋盘存储行宽是有效路数加上两端各一个冗余交叉点。
  uint16_t position{};
  // 提子集合。
  std::vector<uint16_t> captured{};
  // 下一手分支集合，存放下一手落子的uid值。
  std::vector<uint64_t> next_records{};
  // 预置记录执行后的最终点位状态。相同坐标只会出现一次。
  std::vector<GoCorePresetStone> preset_stones{};
  // 预置记录执行前的点位状态，与preset_stones按下标一一对应，仅用于倒带和悔棋还原。
  std::vector<GoCorePresetStone> preset_recovery{};
};

// 棋盘状态记录树节点。uid为0时代表空棋盘虚拟根节点，其余uid可传给GoCore::roaming_to漫游
// 棋局。除了用于构建完整的记录树以外，节点还可被用作遍历游标使用。当被用作游标时，此时节点的
// 子节点数据不再包含子子节点，即子节点的children为空。
// 注意，由于节点数据中不包含父节点，因此反向遍历需要使用专门的GoCore::traverse_back函数；
// 若要一次性使用游标按深度优先（DFS）方式遍历整个记录树，建议使用uid栈来保存回溯点，并使用
// GoCore:traverse_to进行回溯。
class GoCore;
struct GoCoreRecordTreeNode {
  uint64_t uid{};
  uint16_t color{};
  uint16_t row{};
  uint16_t column{};
  std::vector<GoCorePresetStone> preset_stones{};
  std::vector<GoCoreRecordTreeNode> children{};

  // 将游标设置到棋局当前局面的最新落子记录，此操作理论上不会发生错误，返回0。
  [[nodiscard]] int move_current(const GoCore &go_core);

  // 将游标设置到指定的指定落子记录上，与roaming_to不同，此操作仅修改外部持有的记录游标，
  // 不会改变棋盘状态。当指定的uid为0或者是有效的落子记录uid时，对cursor的相关成员进行设置：
  // 将uid设置为实参值；color、row、column在uid有效时设置为落子记录内保存的值，uid为0时则
  // 全部清零；在children中加入所有的下一手信息，但这些子节点的children则保持为空，不再添加
  // 子子节点。设置成功时返回0；失败时返回-1，且不修改游标数据。
  [[nodiscard]] int move_to(const GoCore &go_core, uint64_t uid);

  // 将游标反向移动至父节点。若游标成功设置到父节点，或游标在反向移动前已位于棋局起始
  // （即uid为0），都返回0；若游标已失效（使用ensure_status判断），或父节点不存在等
  // 失败情况，都返回-1。
  [[nodiscard]] int move_back(const GoCore &go_core);

  // 确认游标的当前状态，做如下检查，并返回对应的值：
  // - 若uid不存在，或color、row、column不一致时，返回-1。
  // - 若uid存在，但子节点与records_内不一致时（忽略顺序不一致的情况），
  //   将子节点集合更新为正确数据后返回0。
  // - 以上检查均通过时返回0。
  [[nodiscard]] int ensure_status(const GoCore &go_core);
};

// 棋盘核心算法封装类，虚拟根节点始终代表严格的空棋盘，包含：
// - 坐标数组。
// - 落子算法。
// - 悔棋算法。
// - 树状状态记录，支持落子节点、预置节点以及多分支棋谱。
// - 记录漫游，将棋盘状态恢复至任一落子记录时。
// 此类型不考虑AI训练等有极端性能需求的场景，主要用于一般对弈和多分支记谱。
class GoCore {
  friend struct GoCoreRecordTreeNode;

  static constexpr int kMinNGrids = 1;
  static constexpr int kMaxNGrids = 52;

  static int validate_ngrids_(int ngrids) {
    if (ngrids < kMinNGrids || ngrids > kMaxNGrids)
      throw std::invalid_argument{"ngrids must be in [1, 52]"};
    return ngrids;
  }

public:
  // 创建指定路数的棋盘，有效范围为[1,52]。超出范围时抛出std::invalid_argument。
  explicit GoCore(int ngrids)
      : ngrids_(validate_ngrids_(ngrids)),
        board_width_(static_cast<size_t>(ngrids_) + 2),
        bytes_per_row_((board_width_ + 3) / 4),
        grids_(bytes_per_row_ * board_width_) {
    this->clear_grids_();
  }

  [[nodiscard]] int ngrids() const noexcept { return this->ngrids_; }

  // 获取棋盘上指定坐标点的状态。row和column分别指定坐标点的行与列位置，参数值的有效范围均在
  // [1,ngrids()]，越界时返回-1。参数有效时使用int类型返回数组中坐标点的值：空0，黑1，白2，
  // 坐标越界时返回-1。
  [[nodiscard]] int state_of_position(size_t row, size_t column) const {
    if (!this->is_position_in_range_(row, column))
      return -1;
    return this->state_at_flat_(flat_position_(row, column));
  }

  // 返回指定记录节点对应的完整盘面。此接口只复制压缩棋盘数组，并沿记录路径增量倒带、重放，
  // 不复制整棵记录树；uid无效时返回空集合。
  [[nodiscard]] std::vector<int> position_states_at(uint64_t uid) const;

  // 将单个点位作为预置操作写入记录树。若当前节点是没有子节点的预置记录，则将操作合并到
  // 当前节点；否则创建新的预置子节点。相同点位只保留相对父局面的最终变化。
  // 成功返回0；颜色或坐标无效返回-2；最终盘面存在无气棋块返回-3。失败时不修改任何状态。
  [[nodiscard]] int preset_stone(int color, size_t row, size_t column);

  // 将一组点位变化原子写入一个新的预置记录节点，主要用于加载一个完整的
  // SGF Setup节点。参数中的重复点位按顺序合并，仅保留最后的有效状态。
  // 返回值与preset_stone一致。
  [[nodiscard]] int
  preset_stones(const std::vector<GoCorePresetStone> &preset_stones);

  // 将changes作为对当前盘面的修改，事务式替换当前预置节点。修改后会在独立棋盘中重放
  // 完整记录树，全部成功才提交。返回0表示成功；-1表示当前节点不可编辑或没有实际变化；
  // -2表示参数无效；-3表示修改后的预置局面存在无气棋块；-4表示后续记录无法重放；
  // -5表示修改结果与同级预置分支重复。重放失败时failed_uid返回首个失败节点。
  [[nodiscard]] int
  edit_current_preset_stones(const std::vector<GoCorePresetStone> &changes,
                             uint64_t &failed_uid);

  // 使用相对父局面的完整点位变化替换当前预置节点，主要供命令undo/redo使用。
  // 返回值与edit_current_preset_stones一致。
  [[nodiscard]] int replace_current_preset_stones(
      const std::vector<GoCorePresetStone> &preset_stones,
      uint64_t &failed_uid);

  // 计算参数在当前局面形成的最终预置变化，并查找等价的直接子分支。
  // 找到时返回该预置节点的uid；参数无效、最终没有变化或不存在等价分支时返回0。
  [[nodiscard]] uint64_t matching_preset_branch_uid(
      const std::vector<GoCorePresetStone> &preset_stones) const;

  // GoCore允许在任意有效局面后创建预置节点；上层可按具体业务限制预置模式的入口。
  [[nodiscard]] int can_preset_stone() const noexcept;

  // 返回虚拟根节点后第一条预置记录中最终存在的黑白棋子，用作旧接口的过渡兼容。
  [[nodiscard]] std::vector<GoCorePresetStone> get_preset_stones() const;

  // 落子算法。棋子颜色color指定1或2，分别代表黑或白。row和column分别指定坐标点的行与列位置，
  // 参数值的有效范围均在[1, ngrids()]。
  // 落子成功时返回0，出错时返回以下值：
  // - -1：指定位置越界。
  // - -2：指定位置上已有棋子。
  // - -3：指定位置因没有气而无法落子。
  // - -4：指定位置是劫争禁入点。
  // 出错时棋盘状态不会被改变。
  [[nodiscard]] int place_stone(int color, size_t row, size_t column);

  // 悔棋算法。从recorder_删除当前的落子记录节点，更新上一个节点的next_records集合，并将
  // 棋盘状态恢复到落子前的状态。悔棋操作可能导致recoder_中出现未连接的子分支，为了支持undo
  // 操作，将这些子分支中的节点也删除后与悔棋节点一并返回。返回值确保首元素为悔棋节点，连带被
  // 删除的子分支节点放在后面。
  [[nodiscard]] std::vector<GoCoreRecord> takeback();

  // 悔棋还原操作。由于悔棋之后可能会剪掉记录树上一个分支的所有节点，因此还需要一个专门的还原函数
  // 来支持undo操作。
  // 悔棋还原需要满足以下条件：
  // - 由调用方确保悔棋操作执行的对象节点位于记录列表参数的第一个元素，
  //   检查此节点的父节点，父节点必须是棋盘的当前节点（current_uid_）。
  // - 在悔棋对象节点的父节点的所有子节点中，不能存在与悔棋对象节点一致的落子，
  //   检查颜色和位置。
  // - 记录列表参数中，所有悔棋剪掉的记录节点的uid不能存在于records_中。
  // 当满足还原条件时，将这些记录重新插入到records_中，并将棋盘漫游至悔棋对象节点。
  // 还原操作成功时返回0；当前棋局状态不允许还原时返回-1；记录列表为空、内容被篡改或结构不完整
  // 时返回-2。失败时不会修改棋盘或落子记录。
  [[nodiscard]] int
  takeback_recovery(const std::vector<GoCoreRecord> &takeback_records);

  // 将棋局漫游至指定落子记录时的局面。参数uid必须是recorder_内有的键；或者是0，即未落子时的
  // 棋盘状态。编写算法计算出从current_uid_到参数uid的路径，沿路径正确执行重放（forward_）
  // 或倒带（backward_），需要注意路径可能会跨越不同的分支。漫游成功返回0，失败返回-1。
  [[nodiscard]] int roaming_to(uint64_t uid);

  // 按uid列表调整指定父节点的直属分支顺序，parent_uid为0时表示虚拟根节点。
  // 参数中属于该父节点的uid按首次出现的顺序排到前面；不存在或重复的uid被忽略；
  // 未指定的现有分支保持原相对顺序并追加到末尾。此操作不改变棋盘状态或当前游标，
  // 为便于上层容错，无论父节点或参数是否有效都返回0。
  [[nodiscard]] int
  reorder_next_records(uint64_t parent_uid,
                       const std::vector<uint64_t> &ordered_uids);

  // 导出当前棋盘落子记录对应的记录树，采用非扁平化的树形结构。注意此树的根节点是一个虚拟节点，
  // 因为落子记录可能有多个起始节点，因此需要要一个虚拟的父节点来合并成一颗树，调用方在使用树时
  // 需要注意这个特性。
  [[nodiscard]] GoCoreRecordTreeNode record_tree() const {
    GoCoreRecordTreeNode root{};
    root.uid = 0;
    this->build_record_tree_(0, root.children);
    return root;
  }

  // 完整加载预置棋子和一颗记录树。兼容参数中的预置棋子会转换为虚拟根节点后的预置记录。
  // 虚拟根节点的uid必须为0；其余节点的uid必须非0、全局唯一且小于uint64_t的最大值。
  // 输入树已有节点的uid保持一致；兼容预置参数可能额外占用一个空闲uid。后续新节点从最大uid的
  // 下一位开始生成。加载成功时返回0；预置棋子无效、输入树无效或落子重放失败时返回-1，失败时保持
  // 棋盘、状态记录和uid计数器不变。
  [[nodiscard]] int
  load_record_tree(const GoCoreRecordTreeNode &tree,
                   const std::vector<GoCorePresetStone> &preset_stones,
                   uint64_t *failed_uid = nullptr);

  // 输出字符版的棋盘状态。将棋盘全部坐标点都输出成一个二维字符阵列，包括有效坐标点外围的一圈值
  // 为11的虚拟坐标点，以便完整观察棋盘的内部状态。依据坐标点的值，采用不同字符表示：00优先使用
  // “.”，特殊规则见后续说明；01使用“x”；10使用“o”；11使用“#”。在棋盘的上下左右，分别用数字
  // 或字母对有效坐标点进行位置标识。左右从上到下使用从1递增的数字，注意按固定2位靠右对齐；上下
  // 19路及以下依次使用“ABCDEFGHJKLMNOPQRST”的传统围棋字母序列，注意其中按照惯例省略了和
  // L相似的I字母。20路及以上改用SGF坐标字符序列
  // “abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ”。
  // 对于19路棋盘，做特殊处理，将棋盘上九个星位的00值使用“+”表示。
  void text_output(std::ostream &os) const;

private:
  [[nodiscard]] bool is_position_in_range_(size_t row,
                                           size_t column) const noexcept {
    return row >= 1 && row <= static_cast<size_t>(this->ngrids_) &&
           column >= 1 && column <= static_cast<size_t>(this->ngrids_);
  }

  void clear_grids_();

  [[nodiscard]] size_t flat_position_(size_t row, size_t column) const {
    return row * board_width_ + column;
  }

  [[nodiscard]] int state_at_flat_(size_t position) const {
    const size_t row = position / board_width_;
    const size_t column = position % board_width_;
    const size_t byte_index = row * bytes_per_row_ + column / 4;
    const size_t shift = (column % 4) * 2;
    return (this->grids_[byte_index] >> shift) & 0x03;
  }

  int set_state_at_flat_(size_t position, int state);

  // 设置棋盘坐标点到指定的状态值：空0，黑1，白2，盘外3，并返回当前此坐标点的状态值。
  // 此函数主要用于落子时的有效性检验，以及落子无效时的回滚操作。
  int set_state_of_position_(int state, size_t row, size_t column) {
    return this->set_state_at_flat_(flat_position_(row, column), state);
  }

  // 对棋盘指定位置上的棋子检查周围的“气”数目。使用断言确保指定点位的状态必须是黑或白。
  // 使用BFS遍历此棋子以及与其上下左右相连的所有同色棋子，对这些棋子周围的气进行计数。
  // 遍历时注意参考grids_成员的注释中对异或算法的应用。
  // BFS算法使用traversal_queue_和traversal_visited_，注意状态初始化。
  [[nodiscard]] int liberty_of_stone_(size_t row, size_t column);

  // 对指定棋子四周相邻的异色棋子进行数气，若气≤0则将位置加入到提子集合中并返回，注意同一棋子
  // 不要重复加入。
  [[nodiscard]] std::vector<uint16_t> capture_stones_(size_t row,
                                                      size_t column);

  // 生成下一个落子记录的uid。
  [[nodiscard]] uint64_t next_uid_() { return ++this->uid_counter_; }

  [[nodiscard]] int place_stone_(int color, size_t row, size_t column,
                                 uint64_t specified_uid);

  [[nodiscard]] int
  preset_stones_(const std::vector<GoCorePresetStone> &preset_stones,
                 uint64_t specified_uid, bool merge_current);

  [[nodiscard]] static bool
  same_preset_result_(const std::vector<GoCorePresetStone> &left,
                      const std::vector<GoCorePresetStone> &right);

  [[nodiscard]] uint64_t matching_preset_branch_uid_(
      uint64_t parent_uid, const std::vector<GoCorePresetStone> &preset_stones,
      uint64_t ignored_uid) const;

  [[nodiscard]] bool has_valid_liberties_();

  void build_record_tree_(uint64_t uid,
                          std::vector<GoCoreRecordTreeNode> &children) const;

  [[nodiscard]] static GoCoreRecordTreeNode *
  find_record_tree_node_(GoCoreRecordTreeNode &node, uint64_t uid);

  [[nodiscard]] bool
  load_record_tree_children_(const std::vector<GoCoreRecordTreeNode> &children,
                             uint64_t *failed_uid);

  [[nodiscard]] bool validate_record_tree_children_(
      const std::vector<GoCoreRecordTreeNode> &children,
      std::unordered_set<uint64_t> &uids) const;

  // 重放落子记录推进棋局，此处理用于记录漫游。重放时无需使用与place_stone一致的复杂逻辑，
  // 直接根据落子记录设置棋子和提子。指定的落子记录必须是当前落子记录的直属子节点。注意当棋盘
  // 未落子，即current_uid_为0时，注意检查此落子记录的last_uid值，以确保它是第一顺位的
  // 落子记录。如果对uid的检查未通过，不要修改任何棋盘状态。
  void forward_(uint64_t uid);

  // 反向重放落子记录让棋局倒带。该处理直接使用当前落子记录执行反向操作，清除落子并还原提子，
  // 还需要正确设置current_uid_。
  void backward_();

  // 棋盘状态，使用行主序存放(棋盘路数+2)x(棋盘路数+2)个坐标点数组，每一个坐标点占用2bit。
  // 2bit坐标点的值定义如下：
  // - 00：此点位为空，无落子状态；
  // - 01：此点位上有黑子；
  // - 10：此点位上有白子；
  // - 11：表示棋盘外。
  // 在有效棋盘的外围增加一圈“棋盘外”点位作为“哨兵”，会得到以下好处：
  // - 使用异或结果为0作为相邻棋子同色的条件，即可省略在遍历同色棋子链时对下标做
  //   越界检测；
  // - 计算棋子的“气”时，仅当相邻点位异或结果等于棋子自身颜色时判定为气。
  //   例如：黑子01，仅在与空点位00异或时会得到01。
  // 注意由于额外增加了一圈坐标点，在指定棋盘坐标时行或列的有限范围是[1,ngrids()]。
  int ngrids_;
  size_t board_width_;
  size_t bytes_per_row_;
  std::vector<uint8_t> grids_;

  // 扁平化的树状棋盘状态记录。
  std::unordered_map<uint64_t, GoCoreRecord> recorder_{};

  // 虚拟根节点的直属分支，保持创建顺序。
  std::vector<uint64_t> root_records_{};

  // 用于生成落子记录uid的计数器，从1开始使用。注意在从外部加载一套记录后，该值应该更新为当前
  // 记录中的最大值，下一次生成uid时再递增。
  uint64_t uid_counter_{};

  // 当前棋盘状态对应的最新记录uid，0代表严格空棋盘的虚拟根节点。
  uint64_t current_uid_{};

  // 共享遍历临时区。liberty_of_stone_会覆盖其中内容，调用方不要跨调用保留其状态。
  std::vector<uint16_t> traversal_queue_{};
  std::vector<uint16_t> traversal_visited_{};
  std::vector<uint16_t> liberty_positions_{};
  std::vector<uint16_t> capture_checked_{};

  // 悔棋和悔棋还原时用于遍历记录子树的uid集合。
  std::vector<uint64_t> takeback_pending_{};

  // 悔棋还原时用于校验记录子树的uid与参数下标映射。
  std::unordered_map<uint64_t, size_t> takeback_record_indexes_{};

  // 漫游棋谱时复用的路径缓存，避免每次调用roaming_to都重新分配。
  std::vector<uint64_t> roaming_current_path_{};
  std::vector<uint64_t> roaming_target_path_{};
};

inline int GoCoreRecordTreeNode::move_current(const GoCore &go_core) {
  return this->move_to(go_core, go_core.current_uid_);
}

inline int GoCoreRecordTreeNode::move_to(const GoCore &go_core,
                                         uint64_t target_uid) {
  GoCoreRecordTreeNode target{};
  target.uid = target_uid;

  const std::vector<uint64_t> *child_uids = &go_core.root_records_;
  if (target_uid != 0) {
    const auto target_it = go_core.recorder_.find(target_uid);
    if (target_it == go_core.recorder_.end())
      return -1;

    const auto &record = target_it->second;
    target.color = record.color;
    target.row = static_cast<uint16_t>(record.position / go_core.board_width_);
    target.column =
        static_cast<uint16_t>(record.position % go_core.board_width_);
    target.preset_stones = record.preset_stones;
    child_uids = &record.next_records;
  }

  target.children.reserve(child_uids->size());
  for (const auto child_uid : *child_uids) {
    const auto child_it = go_core.recorder_.find(child_uid);
    if (child_it == go_core.recorder_.end())
      return -1;

    const auto &record = child_it->second;
    GoCoreRecordTreeNode child{};
    child.uid = child_uid;
    child.color = record.color;
    child.row = static_cast<uint16_t>(record.position / go_core.board_width_);
    child.column =
        static_cast<uint16_t>(record.position % go_core.board_width_);
    child.preset_stones = record.preset_stones;
    target.children.push_back(std::move(child));
  }

  *this = std::move(target);
  return 0;
}

inline int GoCoreRecordTreeNode::move_back(const GoCore &go_core) {
  if (this->ensure_status(go_core) != 0)
    return -1;
  if (this->uid == 0)
    return 0;

  const auto current_it = go_core.recorder_.find(this->uid);
  if (current_it == go_core.recorder_.end())
    return -1;
  return this->move_to(go_core, current_it->second.last_uid);
}

inline int GoCoreRecordTreeNode::ensure_status(const GoCore &go_core) {
  GoCoreRecordTreeNode expected{};
  if (expected.move_to(go_core, this->uid) != 0 ||
      this->color != expected.color || this->row != expected.row ||
      this->column != expected.column ||
      this->preset_stones != expected.preset_stones) {
    return -1;
  }

  if (this->children.size() == expected.children.size()) {
    std::vector<bool> matched(expected.children.size(), false);
    bool children_equal = true;
    for (const auto &child : this->children) {
      bool child_matched = false;
      for (size_t index = 0; index < expected.children.size(); ++index) {
        const auto &expected_child = expected.children[index];
        if (!matched[index] && child.uid == expected_child.uid &&
            child.color == expected_child.color &&
            child.row == expected_child.row &&
            child.column == expected_child.column &&
            child.preset_stones == expected_child.preset_stones &&
            child.children.empty()) {
          matched[index] = true;
          child_matched = true;
          break;
        }
      }
      if (!child_matched) {
        children_equal = false;
        break;
      }
    }
    if (children_equal)
      return 0;
  }

  this->children = std::move(expected.children);
  return 0;
}

inline int GoCore::preset_stone(int color, size_t row, size_t column) {
  if (color < 0 || color > 2 || !this->is_position_in_range_(row, column))
    return -2;
  return this->preset_stones_(
      {{static_cast<uint16_t>(color), static_cast<uint16_t>(row),
        static_cast<uint16_t>(column)}},
      0, true);
}

inline int
GoCore::preset_stones(const std::vector<GoCorePresetStone> &preset_stones) {
  return this->preset_stones_(preset_stones, 0, false);
}

inline int GoCore::edit_current_preset_stones(
    const std::vector<GoCorePresetStone> &changes, uint64_t &failed_uid) {
  failed_uid = 0;
  const auto current_it = this->recorder_.find(this->current_uid_);
  if (current_it == this->recorder_.end() || current_it->second.color != 0 ||
      changes.empty()) {
    return -1;
  }

  GoCore desired = *this;
  bool changed = false;
  for (const auto &stone : changes) {
    if (stone.color > 2 ||
        !this->is_position_in_range_(stone.row, stone.column)) {
      return -2;
    }
    if (desired.state_of_position(stone.row, stone.column) != stone.color) {
      desired.set_state_of_position_(stone.color, stone.row, stone.column);
      changed = true;
    }
  }
  if (!changed)
    return -1;

  GoCore parent = *this;
  parent.backward_();
  std::vector<GoCorePresetStone> replacement{};
  for (size_t row = 1; row <= static_cast<size_t>(this->ngrids_); ++row) {
    for (size_t column = 1; column <= static_cast<size_t>(this->ngrids_);
         ++column) {
      const auto desired_state = desired.state_of_position(row, column);
      if (desired_state != parent.state_of_position(row, column)) {
        replacement.push_back({static_cast<uint16_t>(desired_state),
                               static_cast<uint16_t>(row),
                               static_cast<uint16_t>(column)});
      }
    }
  }
  return this->replace_current_preset_stones(replacement, failed_uid);
}

inline int GoCore::replace_current_preset_stones(
    const std::vector<GoCorePresetStone> &preset_stones, uint64_t &failed_uid) {
  failed_uid = 0;
  const auto current_it = this->recorder_.find(this->current_uid_);
  if (current_it == this->recorder_.end() || current_it->second.color != 0 ||
      preset_stones.empty()) {
    return -1;
  }

  GoCore desired = *this;
  desired.backward_();
  for (const auto &stone : preset_stones) {
    if (stone.color > 2 ||
        !this->is_position_in_range_(stone.row, stone.column)) {
      return -2;
    }
    desired.set_state_of_position_(stone.color, stone.row, stone.column);
  }
  if (!desired.has_valid_liberties_())
    return -3;

  std::vector<GoCorePresetStone> replacement{};
  GoCore parent = *this;
  parent.backward_();
  for (size_t row = 1; row <= static_cast<size_t>(this->ngrids_); ++row) {
    for (size_t column = 1; column <= static_cast<size_t>(this->ngrids_);
         ++column) {
      const auto desired_state = desired.state_of_position(row, column);
      if (desired_state != parent.state_of_position(row, column)) {
        replacement.push_back({static_cast<uint16_t>(desired_state),
                               static_cast<uint16_t>(row),
                               static_cast<uint16_t>(column)});
      }
    }
  }
  if (replacement.empty() ||
      this->same_preset_result_(replacement,
                                current_it->second.preset_stones)) {
    return -1;
  }
  if (this->matching_preset_branch_uid_(current_it->second.last_uid,
                                        replacement, this->current_uid_) != 0) {
    return -5;
  }

  auto tree = this->record_tree();
  auto *node = this->find_record_tree_node_(tree, this->current_uid_);
  if (node == nullptr || node->color != 0)
    return -1;
  node->preset_stones = std::move(replacement);

  GoCore candidate{this->ngrids_};
  if (candidate.load_record_tree(tree, {}, &failed_uid) != 0 ||
      candidate.roaming_to(this->current_uid_) != 0) {
    if (failed_uid == 0)
      failed_uid = this->current_uid_;
    return -4;
  }
  *this = std::move(candidate);
  return 0;
}

inline uint64_t GoCore::matching_preset_branch_uid(
    const std::vector<GoCorePresetStone> &preset_stones) const {
  GoCore simulation = *this;
  if (simulation.current_uid_ == 0) {
    simulation.root_records_.clear();
  } else {
    const auto current_it = simulation.recorder_.find(simulation.current_uid_);
    if (current_it == simulation.recorder_.end())
      return 0;
    current_it->second.next_records.clear();
  }

  const auto parent_uid = this->current_uid_;
  if (simulation.preset_stones_(preset_stones, 0, false) != 0 ||
      simulation.current_uid_ == parent_uid) {
    return 0;
  }
  const auto result_it = simulation.recorder_.find(simulation.current_uid_);
  if (result_it == simulation.recorder_.end() || result_it->second.color != 0)
    return 0;
  return this->matching_preset_branch_uid_(parent_uid,
                                           result_it->second.preset_stones, 0);
}

inline int GoCore::can_preset_stone() const noexcept { return 0; }

inline std::vector<GoCorePresetStone> GoCore::get_preset_stones() const {
  for (const auto uid : this->root_records_) {
    const auto record_it = this->recorder_.find(uid);
    if (record_it == this->recorder_.end() || record_it->second.color != 0)
      continue;

    std::vector<GoCorePresetStone> stones{};
    for (const auto &stone : record_it->second.preset_stones) {
      if (stone.color == 1 || stone.color == 2)
        stones.push_back(stone);
    }
    return stones;
  }
  return {};
}

inline int
GoCore::preset_stones_(const std::vector<GoCorePresetStone> &preset_stones,
                       uint64_t specified_uid, bool merge_current) {
  if (specified_uid == std::numeric_limits<uint64_t>::max() ||
      (specified_uid != 0 &&
       this->recorder_.find(specified_uid) != this->recorder_.end())) {
    return -1;
  }
  for (const auto &stone : preset_stones) {
    if (stone.color > 2 ||
        !this->is_position_in_range_(stone.row, stone.column)) {
      return -2;
    }
  }
  if (preset_stones.empty())
    return 0;

  GoCoreRecord *merged_record = nullptr;
  if (merge_current && this->current_uid_ != 0) {
    const auto current_it = this->recorder_.find(this->current_uid_);
    if (current_it != this->recorder_.end() && current_it->second.color == 0 &&
        current_it->second.next_records.empty()) {
      merged_record = &current_it->second;
    }
  }

  auto final_states = merged_record != nullptr
                          ? merged_record->preset_stones
                          : std::vector<GoCorePresetStone>{};
  auto recovery_states = merged_record != nullptr
                             ? merged_record->preset_recovery
                             : std::vector<GoCorePresetStone>{};
  const auto original_grids = this->grids_;

  for (const auto &stone : preset_stones) {
    const auto state_before =
        static_cast<uint16_t>(this->state_of_position(stone.row, stone.column));
    const auto existing = std::find_if(
        final_states.begin(), final_states.end(), [&](const auto &candidate) {
          return candidate.row == stone.row && candidate.column == stone.column;
        });

    this->set_state_of_position_(stone.color, stone.row, stone.column);
    if (existing == final_states.end()) {
      if (state_before == stone.color)
        continue;
      final_states.push_back(stone);
      recovery_states.push_back({state_before, stone.row, stone.column});
      continue;
    }

    const auto index = static_cast<size_t>(existing - final_states.begin());
    if (recovery_states[index].color == stone.color) {
      final_states.erase(final_states.begin() +
                         static_cast<std::ptrdiff_t>(index));
      recovery_states.erase(recovery_states.begin() +
                            static_cast<std::ptrdiff_t>(index));
    } else {
      final_states[index].color = stone.color;
    }
  }

  if (!this->has_valid_liberties_()) {
    this->grids_ = original_grids;
    return -3;
  }

  if (!final_states.empty()) {
    const auto parent_uid =
        merged_record == nullptr ? this->current_uid_ : merged_record->last_uid;
    const auto ignored_uid =
        merged_record == nullptr ? uint64_t{} : merged_record->uid;
    if (this->matching_preset_branch_uid_(parent_uid, final_states,
                                          ignored_uid) != 0) {
      this->grids_ = original_grids;
      return -1;
    }
  }

  if (final_states.empty()) {
    if (merged_record == nullptr)
      return 0;

    const auto removed_uid = merged_record->uid;
    const auto parent_uid = merged_record->last_uid;
    if (parent_uid == 0) {
      this->root_records_.erase(std::remove(this->root_records_.begin(),
                                            this->root_records_.end(),
                                            removed_uid),
                                this->root_records_.end());
    } else {
      auto &siblings = this->recorder_.at(parent_uid).next_records;
      siblings.erase(std::remove(siblings.begin(), siblings.end(), removed_uid),
                     siblings.end());
    }
    this->recorder_.erase(removed_uid);
    this->current_uid_ = parent_uid;
    return 0;
  }

  if (merged_record != nullptr) {
    merged_record->preset_stones = std::move(final_states);
    merged_record->preset_recovery = std::move(recovery_states);
    return 0;
  }

  GoCoreRecord record{};
  record.uid = specified_uid == 0 ? this->next_uid_() : specified_uid;
  record.last_uid = this->current_uid_;
  record.color = 0;
  record.preset_stones = std::move(final_states);
  record.preset_recovery = std::move(recovery_states);

  const auto uid = record.uid;
  const bool inserted =
      this->recorder_.try_emplace(uid, std::move(record)).second;
  assert(inserted);
  (void)inserted;

  if (specified_uid != 0)
    this->uid_counter_ = std::max(this->uid_counter_, specified_uid);
  if (this->current_uid_ == 0) {
    this->root_records_.push_back(uid);
  } else {
    this->recorder_.at(this->current_uid_).next_records.push_back(uid);
  }
  this->current_uid_ = uid;
  return 0;
}

inline bool
GoCore::same_preset_result_(const std::vector<GoCorePresetStone> &left,
                            const std::vector<GoCorePresetStone> &right) {
  if (left.size() != right.size())
    return false;
  return std::all_of(left.begin(), left.end(), [&](const auto &stone) {
    return std::find(right.begin(), right.end(), stone) != right.end();
  });
}

inline uint64_t GoCore::matching_preset_branch_uid_(
    uint64_t parent_uid, const std::vector<GoCorePresetStone> &preset_stones,
    uint64_t ignored_uid) const {
  const std::vector<uint64_t> *children = &this->root_records_;
  if (parent_uid != 0) {
    const auto parent_it = this->recorder_.find(parent_uid);
    if (parent_it == this->recorder_.end())
      return 0;
    children = &parent_it->second.next_records;
  }
  for (const auto uid : *children) {
    if (uid == ignored_uid)
      continue;
    const auto record_it = this->recorder_.find(uid);
    if (record_it != this->recorder_.end() && record_it->second.color == 0 &&
        this->same_preset_result_(record_it->second.preset_stones,
                                  preset_stones)) {
      return uid;
    }
  }
  return 0;
}

inline bool GoCore::has_valid_liberties_() {
  for (size_t row = 1; row <= static_cast<size_t>(this->ngrids_); ++row) {
    for (size_t column = 1; column <= static_cast<size_t>(this->ngrids_);
         ++column) {
      const auto state = this->state_of_position(row, column);
      if ((state == 1 || state == 2) &&
          this->liberty_of_stone_(row, column) <= 0) {
        return false;
      }
    }
  }
  return true;
}
inline int GoCore::place_stone(int color, size_t row, size_t column) {
  return this->place_stone_(color, row, column, 0);
}

inline int GoCore::place_stone_(int color, size_t row, size_t column,
                                uint64_t specified_uid) {
  // 基本检查。
  if (color != 1 && color != 2)
    return -1;
  if (const auto state = this->state_of_position(row, column); state < 0) {
    return -1;
  } else if (state != 0) {
    return -2;
  }
  if (specified_uid != 0 &&
      this->recorder_.find(specified_uid) != this->recorder_.end())
    return -1;

  // 检查当前落子记录中的next_records，若其中某一落子记录的颜色和坐标与参数一致，则直接使用
  // forward_进行记录重放。当棋盘位于虚拟根节点时，直接检查root_records_中的首手分支。
  // 执行重放后结束落子处理。
  const auto position = static_cast<uint16_t>(flat_position_(row, column));
  if (specified_uid == 0 && this->current_uid_ == 0) {
    for (const auto uid : this->root_records_) {
      const auto record_it = this->recorder_.find(uid);
      if (record_it == this->recorder_.end())
        continue;

      const auto &record = record_it->second;
      if (record.last_uid == 0 && record.color == color &&
          record.position == position) {
        this->forward_(record.uid);
        return 0;
      }
    }
  } else if (specified_uid == 0) {
    if (const auto current_it = this->recorder_.find(this->current_uid_);
        current_it != this->recorder_.end()) {
      for (auto next_uid : current_it->second.next_records) {
        if (const auto next_it = this->recorder_.find(next_uid);
            next_it != this->recorder_.end()) {
          const auto &record = next_it->second;
          if (record.color == color && record.position == position) {
            this->forward_(record.uid);
            return 0;
          }
        }
      }
    }
  }

  // 此核心类中不会进行全局的局面一致性检查，对于打劫仅采用如下逻辑：检查上一个落子记录，
  // 当本次落子与上次落子异色，并且上次落子提取了单个棋子，则将该提子作为本次落子的禁入点。
  if (this->current_uid_ != 0) {
    if (const auto last_it = this->recorder_.find(this->current_uid_);
        last_it != this->recorder_.end()) {
      const auto &last_record = last_it->second;
      if (last_record.color != color && last_record.captured.size() == 1 &&
          last_record.captured.front() == position) {
        return -4;
      }
    }
  }

  // 首先无条件的放置棋子。
  auto old_state = this->set_state_of_position_(color, row, column);
  // 对放置的棋子数气。
  auto liberty = this->liberty_of_stone_(row, column);
  // 进一步检查是否触发了提子。
  auto captured = this->capture_stones_(row, column);
  // 若因没有气而无法落子，恢复棋盘状态后返回错误值。
  if (liberty <= 0 && captured.empty()) {
    this->set_state_of_position_(old_state, row, column);
    return -3;
  }

  // 清理棋盘上的提子，生成落子记录到recorder_，更新当前棋盘状态对应的current_uid_。
  // 生成落子记录时注意更新当前节点的next_records和新节点的last_uid，以保持recorder_的
  // 树形结构。
  for (auto p : captured) {
    this->set_state_at_flat_(p, 0);
  }

  GoCoreRecord record{};
  record.uid = specified_uid == 0 ? this->next_uid_() : specified_uid;
  record.last_uid = this->current_uid_;
  record.color = static_cast<uint16_t>(color);
  record.position = static_cast<uint16_t>(flat_position_(row, column));
  record.captured = std::move(captured);

  const auto uid = record.uid;
  const bool inserted =
      this->recorder_.try_emplace(uid, std::move(record)).second;
  assert(inserted);
  (void)inserted;

  if (specified_uid != 0)
    this->uid_counter_ = std::max(this->uid_counter_, specified_uid);
  if (this->current_uid_ != 0) {
    this->recorder_.at(this->current_uid_).next_records.push_back(uid);
  } else {
    this->root_records_.push_back(uid);
  }

  this->current_uid_ = uid;
  return 0;
}

inline std::vector<GoCoreRecord> GoCore::takeback() {
  std::vector<GoCoreRecord> removed{};
  if (this->current_uid_ == 0)
    return removed;

  auto current_it = this->recorder_.find(this->current_uid_);
  if (current_it == this->recorder_.end()) {
    this->current_uid_ = 0;
    return removed;
  }

  removed.push_back(std::move(current_it->second));
  const auto &current = removed.front();
  const auto current_last_uid = current.last_uid;

  if (current.color == 0) {
    for (const auto &stone : current.preset_recovery)
      this->set_state_of_position_(stone.color, stone.row, stone.column);
  } else {
    this->set_state_at_flat_(current.position, 0);
    const auto captured_color = current.color == 1 ? 2 : 1;
    for (auto position : current.captured)
      this->set_state_at_flat_(position, captured_color);
  }

  if (current.last_uid != 0) {
    if (const auto parent_it = this->recorder_.find(current.last_uid);
        parent_it != this->recorder_.end()) {
      auto &siblings = parent_it->second.next_records;
      siblings.erase(std::remove(siblings.begin(), siblings.end(), current.uid),
                     siblings.end());
    }
  } else {
    this->root_records_.erase(std::remove(this->root_records_.begin(),
                                          this->root_records_.end(),
                                          current.uid),
                              this->root_records_.end());
  }

  // Remove child branches; removed[0] is always the takeback record.
  this->takeback_pending_.clear();
  this->takeback_pending_.insert(this->takeback_pending_.end(),
                                 current.next_records.begin(),
                                 current.next_records.end());
  while (!this->takeback_pending_.empty()) {
    const auto uid = this->takeback_pending_.back();
    this->takeback_pending_.pop_back();

    auto child_it = this->recorder_.find(uid);
    if (child_it == this->recorder_.end())
      continue;

    auto child = std::move(child_it->second);
    this->takeback_pending_.insert(this->takeback_pending_.end(),
                                   child.next_records.begin(),
                                   child.next_records.end());
    removed.push_back(std::move(child));
    this->recorder_.erase(child_it);
  }

  this->recorder_.erase(current_it);
  this->current_uid_ = current_last_uid;
  return removed;
}

inline int
GoCore::takeback_recovery(const std::vector<GoCoreRecord> &takeback_records) {
  if (takeback_records.empty())
    return -2;

  this->takeback_record_indexes_.clear();
  this->takeback_record_indexes_.reserve(takeback_records.size());
  for (size_t index = 0; index < takeback_records.size(); ++index) {
    const auto &record = takeback_records[index];
    if (record.uid == 0 || record.uid > this->uid_counter_ ||
        record.color > 2) {
      return -2;
    }

    if (record.color == 0) {
      if (record.position != 0 || !record.captured.empty() ||
          record.preset_stones.empty() ||
          record.preset_stones.size() != record.preset_recovery.size()) {
        return -2;
      }

      this->capture_checked_.clear();
      for (size_t preset_index = 0; preset_index < record.preset_stones.size();
           ++preset_index) {
        const auto &stone = record.preset_stones[preset_index];
        const auto &recovery = record.preset_recovery[preset_index];
        if (stone.color > 2 || recovery.color > 2 ||
            stone.row != recovery.row || stone.column != recovery.column ||
            stone.color == recovery.color ||
            !this->is_position_in_range_(stone.row, stone.column)) {
          return -2;
        }
        const auto position = static_cast<uint16_t>(
            this->flat_position_(stone.row, stone.column));
        if (std::find(this->capture_checked_.begin(),
                      this->capture_checked_.end(),
                      position) != this->capture_checked_.end()) {
          return -2;
        }
        this->capture_checked_.push_back(position);
      }
    } else {
      if (!record.preset_stones.empty() || !record.preset_recovery.empty()) {
        return -2;
      }
      const auto row = record.position / board_width_;
      const auto column = record.position % board_width_;
      if (!this->is_position_in_range_(row, column))
        return -2;

      this->capture_checked_.clear();
      this->capture_checked_.reserve(record.captured.size());
      for (const auto position : record.captured) {
        const auto captured_row = position / board_width_;
        const auto captured_column = position % board_width_;
        if (position == record.position ||
            !this->is_position_in_range_(captured_row, captured_column) ||
            std::find(this->capture_checked_.begin(),
                      this->capture_checked_.end(),
                      position) != this->capture_checked_.end()) {
          return -2;
        }
        this->capture_checked_.push_back(position);
      }
    }

    if (!this->takeback_record_indexes_.try_emplace(record.uid, index).second)
      return -2;
  }
  this->takeback_pending_.clear();
  this->takeback_pending_.push_back(takeback_records.front().uid);
  while (!this->takeback_pending_.empty()) {
    const auto uid = this->takeback_pending_.back();
    this->takeback_pending_.pop_back();
    const auto index_it = this->takeback_record_indexes_.find(uid);
    if (index_it == this->takeback_record_indexes_.end())
      return -2;

    const auto record_index = index_it->second;
    this->takeback_record_indexes_.erase(index_it);
    const auto &record = takeback_records[record_index];
    for (const auto child_uid : record.next_records) {
      const auto child_it = this->takeback_record_indexes_.find(child_uid);
      if (child_it == this->takeback_record_indexes_.end() ||
          takeback_records[child_it->second].last_uid != record.uid) {
        return -2;
      }
      this->takeback_pending_.push_back(child_uid);
    }
  }
  if (!this->takeback_record_indexes_.empty())
    return -2;

  const auto &target = takeback_records.front();
  if (target.last_uid != this->current_uid_)
    return -1;
  for (const auto &record : takeback_records) {
    if (this->recorder_.find(record.uid) != this->recorder_.end())
      return -1;
  }

  const std::vector<uint64_t> *siblings = &this->root_records_;
  if (this->current_uid_ != 0) {
    const auto parent_it = this->recorder_.find(this->current_uid_);
    if (parent_it == this->recorder_.end())
      return -1;
    siblings = &parent_it->second.next_records;
  }
  if (target.color != 0) {
    for (const auto sibling_uid : *siblings) {
      if (const auto sibling_it = this->recorder_.find(sibling_uid);
          sibling_it != this->recorder_.end() &&
          sibling_it->second.color == target.color &&
          sibling_it->second.position == target.position) {
        return -1;
      }
    }
  } else if (this->matching_preset_branch_uid_(this->current_uid_,
                                               target.preset_stones, 0) != 0) {
    return -1;
  }

  this->recorder_.reserve(this->recorder_.size() + takeback_records.size());
  for (const auto &record : takeback_records)
    this->recorder_.emplace(record.uid, record);
  if (this->current_uid_ == 0) {
    this->root_records_.push_back(target.uid);
  } else {
    this->recorder_.at(this->current_uid_).next_records.push_back(target.uid);
  }

  if (this->roaming_to(target.uid) == 0 &&
      (target.color != 0 || this->has_valid_liberties_())) {
    return 0;
  }
  if (this->current_uid_ == target.uid)
    this->backward_();

  if (target.last_uid == 0) {
    this->root_records_.pop_back();
  } else {
    this->recorder_.at(target.last_uid).next_records.pop_back();
  }
  for (const auto &record : takeback_records)
    this->recorder_.erase(record.uid);
  return -1;
}

inline int GoCore::roaming_to(uint64_t uid) {
  if (uid == this->current_uid_)
    return 0;
  if (uid != 0 && this->recorder_.find(uid) == this->recorder_.end())
    return -1;
  if (this->current_uid_ != 0 &&
      this->recorder_.find(this->current_uid_) == this->recorder_.end())
    return -1;

  this->roaming_current_path_.clear();
  auto cursor = this->current_uid_;
  while (cursor != 0) {
    if (const auto it = this->recorder_.find(cursor);
        it != this->recorder_.end()) {
      this->roaming_current_path_.push_back(cursor);
      cursor = it->second.last_uid;
    } else {
      return -1;
    }
  }
  this->roaming_current_path_.push_back(0);

  this->roaming_target_path_.clear();
  cursor = uid;
  while (cursor != 0) {
    if (const auto it = this->recorder_.find(cursor);
        it != this->recorder_.end()) {
      this->roaming_target_path_.push_back(cursor);
      cursor = it->second.last_uid;
    } else {
      return -1;
    }
  }
  this->roaming_target_path_.push_back(0);

  size_t current_index = this->roaming_current_path_.size();
  size_t target_index = this->roaming_target_path_.size();
  uint64_t common_uid = 0;
  while (current_index > 0 && target_index > 0 &&
         this->roaming_current_path_[current_index - 1] ==
             this->roaming_target_path_[target_index - 1]) {
    common_uid = this->roaming_current_path_[--current_index];
    --target_index;
  }

  while (this->current_uid_ != common_uid) {
    this->backward_();
  }

  for (size_t index = target_index; index > 0; --index) {
    this->forward_(this->roaming_target_path_[index - 1]);
  }
  return 0;
}

inline std::vector<int> GoCore::position_states_at(uint64_t uid) const {
  if (uid != 0 && this->recorder_.find(uid) == this->recorder_.end())
    return {};
  if (this->current_uid_ != 0 &&
      this->recorder_.find(this->current_uid_) == this->recorder_.end())
    return {};

  std::vector<uint64_t> current_path{};
  auto cursor = this->current_uid_;
  while (cursor != 0) {
    const auto record_it = this->recorder_.find(cursor);
    if (record_it == this->recorder_.end())
      return {};
    current_path.push_back(cursor);
    cursor = record_it->second.last_uid;
  }
  current_path.push_back(0);

  std::vector<uint64_t> target_path{};
  cursor = uid;
  while (cursor != 0) {
    const auto record_it = this->recorder_.find(cursor);
    if (record_it == this->recorder_.end())
      return {};
    target_path.push_back(cursor);
    cursor = record_it->second.last_uid;
  }
  target_path.push_back(0);

  size_t current_index = current_path.size();
  size_t target_index = target_path.size();
  uint64_t common_uid = 0;
  while (current_index > 0 && target_index > 0 &&
         current_path[current_index - 1] == target_path[target_index - 1]) {
    common_uid = current_path[--current_index];
    --target_index;
  }

  GoCore snapshot{this->ngrids_};
  snapshot.grids_ = this->grids_;
  snapshot.current_uid_ = this->current_uid_;
  while (snapshot.current_uid_ != common_uid) {
    const auto &record = this->recorder_.at(snapshot.current_uid_);
    if (record.color == 0) {
      for (const auto &stone : record.preset_recovery)
        snapshot.set_state_of_position_(stone.color, stone.row, stone.column);
    } else {
      snapshot.set_state_at_flat_(record.position, 0);
      const auto captured_color = record.color == 1 ? 2 : 1;
      for (const auto position : record.captured)
        snapshot.set_state_at_flat_(position, captured_color);
    }
    snapshot.current_uid_ = record.last_uid;
  }
  for (size_t index = target_index; index > 0; --index) {
    const auto &record = this->recorder_.at(target_path[index - 1]);
    if (record.color == 0) {
      for (const auto &stone : record.preset_stones)
        snapshot.set_state_of_position_(stone.color, stone.row, stone.column);
    } else {
      snapshot.set_state_at_flat_(record.position, record.color);
      for (const auto position : record.captured)
        snapshot.set_state_at_flat_(position, 0);
    }
    snapshot.current_uid_ = record.uid;
  }

  std::vector<int> states{};
  states.reserve(static_cast<size_t>(this->ngrids_) *
                 static_cast<size_t>(this->ngrids_));
  for (int row = 1; row <= this->ngrids_; ++row) {
    for (int column = 1; column <= this->ngrids_; ++column)
      states.push_back(snapshot.state_of_position(row, column));
  }
  return states;
}

inline int
GoCore::load_record_tree(const GoCoreRecordTreeNode &tree,
                         const std::vector<GoCorePresetStone> &preset_stones,
                         uint64_t *failed_uid) {
  if (failed_uid != nullptr)
    *failed_uid = 0;
  std::unordered_set<uint64_t> uids{};
  if (tree.uid != 0 || tree.color != 0 || tree.row != 0 || tree.column != 0 ||
      !tree.preset_stones.empty() ||
      !this->validate_record_tree_children_(tree.children, uids)) {
    return -1;
  }

  uint64_t legacy_preset_uid = 0;
  if (!preset_stones.empty()) {
    legacy_preset_uid = 1;
    while (uids.find(legacy_preset_uid) != uids.end()) {
      if (legacy_preset_uid == std::numeric_limits<uint64_t>::max() - 1) {
        return -1;
      }
      ++legacy_preset_uid;
    }
  }

  const auto backup_grids = this->grids_;
  const auto backup_recorder = this->recorder_;
  const auto backup_root_records = this->root_records_;
  const auto backup_uid_counter = this->uid_counter_;
  const auto backup_current_uid = this->current_uid_;

  this->clear_grids_();
  this->recorder_.clear();
  this->root_records_.clear();
  this->uid_counter_ = 0;
  this->current_uid_ = 0;

  bool loaded = true;
  if (!preset_stones.empty() &&
      this->preset_stones_(preset_stones, legacy_preset_uid, false) != 0) {
    if (failed_uid != nullptr)
      *failed_uid = legacy_preset_uid;
    loaded = false;
  }
  if (loaded && !this->load_record_tree_children_(tree.children, failed_uid))
    loaded = false;
  if (loaded && this->roaming_to(0) != 0)
    loaded = false;

  if (!loaded) {
    this->grids_ = backup_grids;
    this->recorder_ = backup_recorder;
    this->root_records_ = backup_root_records;
    this->uid_counter_ = backup_uid_counter;
    this->current_uid_ = backup_current_uid;
    return -1;
  }

  return 0;
}
inline void GoCore::text_output(std::ostream &os) const {
  static constexpr const char *Columns = "ABCDEFGHJKLMNOPQRST";
  static constexpr const char *kSgfColumns =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const auto *columns = this->ngrids_ <= 19 ? Columns : kSgfColumns;

  auto is_star = [this](size_t row, size_t column) {
    if (this->ngrids_ != 19) {
      return false;
    } else {
      const bool star_row = row == 4 || row == 10 || row == 16;
      const bool star_column = column == 4 || column == 10 || column == 16;
      return star_row && star_column;
    }
  };

  os << "      ";
  for (int column = 0; column < ngrids_; ++column)
    os << columns[column] << ' ';
  os << '\n';

  for (size_t row = 0; row < board_width_; ++row) {
    if (row >= 1 && row <= ngrids_) {
      os << std::setw(2) << row << "  ";
    } else {
      os << "    ";
    }

    for (size_t column = 0; column < board_width_; ++column) {
      const auto state = this->state_at_flat_(flat_position_(row, column));
      char token = '?';
      if (state == 0)
        token = is_star(row, column) ? '+' : '.';
      if (state == 1)
        token = 'x';
      if (state == 2)
        token = 'o';
      if (state == 3)
        token = '#';
      os << token;
      if (column + 1 < board_width_)
        os << ' ';
    }

    if (row >= 1 && row <= ngrids_) {
      os << "  " << std::setw(2) << row;
    }
    os << '\n';
  }

  os << "      ";
  for (int column = 0; column < ngrids_; ++column)
    os << columns[column] << ' ';
  os << '\n';
}

inline void GoCore::clear_grids_() {
  const size_t kLastRow = this->board_width_ - 1;
  const size_t kLastColumn = this->board_width_ - 1;

  std::memset(this->grids_.data(), 0xff, bytes_per_row_);
  std::memset(this->grids_.data() + kLastRow * bytes_per_row_, 0xff,
              bytes_per_row_);

  auto *second_row = this->grids_.data() + bytes_per_row_;
  std::memset(second_row, 0, bytes_per_row_);
  second_row[0] |= 0x03;
  second_row[kLastColumn / 4] |=
      static_cast<uint8_t>(0x03 << ((kLastColumn % 4) * 2));

  for (size_t row = 2; row < kLastRow; ++row) {
    std::memcpy(this->grids_.data() + row * bytes_per_row_, second_row,
                bytes_per_row_);
  }
}

inline int GoCore::set_state_at_flat_(size_t position, int state) {
  const auto old_state = this->state_at_flat_(position);
  const size_t row = position / board_width_;
  const size_t column = position % board_width_;
  const size_t byte_index = row * bytes_per_row_ + column / 4;
  const size_t shift = (column % 4) * 2;
  this->grids_[byte_index] &= static_cast<uint8_t>(~(0x03 << shift));
  this->grids_[byte_index] |= static_cast<uint8_t>((state & 0x03) << shift);
  return old_state;
}

inline int GoCore::liberty_of_stone_(size_t row, size_t column) {
  const auto start = flat_position_(row, column);
  const auto color = this->state_at_flat_(start);
  assert(color == 1 || color == 2);

  this->traversal_queue_.clear();
  this->traversal_visited_.clear();
  this->liberty_positions_.clear();

  this->traversal_queue_.push_back(static_cast<uint16_t>(start));
  this->traversal_visited_.push_back(static_cast<uint16_t>(start));

  for (size_t index = 0; index < this->traversal_queue_.size(); ++index) {
    const auto position = this->traversal_queue_[index];
    const size_t neighbors[] = {
        static_cast<size_t>(position) - board_width_,
        static_cast<size_t>(position) + board_width_,
        static_cast<size_t>(position) - 1,
        static_cast<size_t>(position) + 1,
    };

    for (auto neighbor : neighbors) {
      const auto state = this->state_at_flat_(neighbor);
      if (state == 0) {
        auto liberty = static_cast<uint16_t>(neighbor);
        if (std::find(this->liberty_positions_.begin(),
                      this->liberty_positions_.end(),
                      liberty) == this->liberty_positions_.end()) {
          this->liberty_positions_.push_back(liberty);
        }
      } else if (state == color) {
        auto same_color = static_cast<uint16_t>(neighbor);
        if (std::find(this->traversal_visited_.begin(),
                      this->traversal_visited_.end(),
                      same_color) == this->traversal_visited_.end()) {
          this->traversal_visited_.push_back(same_color);
          this->traversal_queue_.push_back(same_color);
        }
      }
    }
  }

  return static_cast<int>(this->liberty_positions_.size());
}

inline std::vector<uint16_t> GoCore::capture_stones_(size_t row,
                                                     size_t column) {
  std::vector<uint16_t> captured{};
  this->capture_checked_.clear();
  const auto position = flat_position_(row, column);
  const auto color = this->state_at_flat_(position);
  const auto opponent = color == 1 ? 2 : 1;

  const size_t neighbors[] = {
      position - board_width_,
      position + board_width_,
      position - 1,
      position + 1,
  };

  for (auto neighbor : neighbors) {
    const auto neighbor_state = this->state_at_flat_(neighbor);
    const auto neighbor_position = static_cast<uint16_t>(neighbor);
    if (neighbor_state != opponent ||
        std::find(this->capture_checked_.begin(), this->capture_checked_.end(),
                  neighbor_position) != this->capture_checked_.end()) {
      continue;
    }

    const auto liberty = this->liberty_of_stone_(neighbor / board_width_,
                                                 neighbor % board_width_);
    this->capture_checked_.insert(this->capture_checked_.end(),
                                  this->traversal_visited_.begin(),
                                  this->traversal_visited_.end());
    if (liberty > 0)
      continue;

    for (auto captured_position : this->traversal_visited_) {
      if (std::find(captured.begin(), captured.end(), captured_position) ==
          captured.end()) {
        captured.push_back(captured_position);
      }
    }
  }

  return captured;
}

inline void
GoCore::build_record_tree_(uint64_t uid,
                           std::vector<GoCoreRecordTreeNode> &children) const {
  const std::vector<uint64_t> *child_uids = &this->root_records_;
  if (uid != 0) {
    const auto record_it = this->recorder_.find(uid);
    if (record_it == this->recorder_.end())
      return;
    child_uids = &record_it->second.next_records;
  }

  children.reserve(child_uids->size());
  for (const auto child_uid : *child_uids) {
    const auto child_it = this->recorder_.find(child_uid);
    if (child_it == this->recorder_.end())
      continue;

    const auto &record = child_it->second;
    GoCoreRecordTreeNode child{};
    child.uid = child_uid;
    child.color = record.color;
    child.row = static_cast<uint16_t>(record.position / board_width_);
    child.column = static_cast<uint16_t>(record.position % board_width_);
    child.preset_stones = record.preset_stones;
    this->build_record_tree_(child_uid, child.children);
    children.push_back(std::move(child));
  }
}

inline GoCoreRecordTreeNode *
GoCore::find_record_tree_node_(GoCoreRecordTreeNode &node, uint64_t uid) {
  if (node.uid == uid)
    return &node;
  for (auto &child : node.children) {
    if (auto *result = find_record_tree_node_(child, uid); result != nullptr)
      return result;
  }
  return nullptr;
}

inline int
GoCore::reorder_next_records(uint64_t parent_uid,
                             const std::vector<uint64_t> &ordered_uids) {
  std::vector<uint64_t> *children = &this->root_records_;
  if (parent_uid != 0) {
    const auto parent_it = this->recorder_.find(parent_uid);
    if (parent_it == this->recorder_.end())
      return 0;
    children = &parent_it->second.next_records;
  }

  std::unordered_set<uint64_t> existing{children->begin(), children->end()};
  std::unordered_set<uint64_t> appended{};
  std::vector<uint64_t> reordered{};
  reordered.reserve(children->size());
  for (const auto uid : ordered_uids) {
    if (existing.find(uid) != existing.end() && appended.insert(uid).second)
      reordered.push_back(uid);
  }
  for (const auto uid : *children) {
    if (appended.insert(uid).second)
      reordered.push_back(uid);
  }
  *children = std::move(reordered);
  return 0;
}

inline bool GoCore::load_record_tree_children_(
    const std::vector<GoCoreRecordTreeNode> &children, uint64_t *failed_uid) {
  const auto parent_uid = this->current_uid_;
  for (const auto &child : children) {
    if (this->roaming_to(parent_uid) != 0)
      return false;
    const auto result =
        child.color == 0
            ? this->preset_stones_(child.preset_stones, child.uid, false)
            : this->place_stone_(child.color, child.row, child.column,
                                 child.uid);
    if (result != 0) {
      if (failed_uid != nullptr)
        *failed_uid = child.uid;
      return false;
    }

    // SGF允许写出对当前局面没有实际影响的setup属性。它不应成为GoCore节点，
    // 但其子节点仍需直接接到当前父节点上。
    if (child.color == 0 && this->current_uid_ == parent_uid) {
      if (!this->load_record_tree_children_(child.children, failed_uid))
        return false;
      continue;
    }
    if (this->current_uid_ != child.uid)
      return false;

    if (!this->load_record_tree_children_(child.children, failed_uid))
      return false;
  }

  return this->roaming_to(parent_uid) == 0;
}

inline bool GoCore::validate_record_tree_children_(
    const std::vector<GoCoreRecordTreeNode> &children,
    std::unordered_set<uint64_t> &uids) const {
  std::unordered_set<uint64_t> sibling_moves{};
  for (const auto &child : children) {
    if (child.uid == 0 || child.uid == std::numeric_limits<uint64_t>::max() ||
        !uids.insert(child.uid).second) {
      return false;
    }

    if (child.color == 0) {
      if (child.row != 0 || child.column != 0 || child.preset_stones.empty()) {
        return false;
      }
      std::unordered_set<uint16_t> positions{};
      for (const auto &stone : child.preset_stones) {
        if (stone.color > 2 ||
            !this->is_position_in_range_(stone.row, stone.column) ||
            !positions
                 .insert(static_cast<uint16_t>(
                     this->flat_position_(stone.row, stone.column)))
                 .second) {
          return false;
        }
      }
    } else {
      if ((child.color != 1 && child.color != 2) ||
          !child.preset_stones.empty() ||
          !this->is_position_in_range_(child.row, child.column)) {
        return false;
      }
      const uint64_t move = (static_cast<uint64_t>(child.color) << 32U) |
                            (static_cast<uint64_t>(child.row) << 16U) |
                            static_cast<uint64_t>(child.column);
      if (!sibling_moves.insert(move).second)
        return false;
    }

    if (!this->validate_record_tree_children_(child.children, uids))
      return false;
  }
  return true;
}
inline void GoCore::forward_(uint64_t uid) {
  auto record_it = this->recorder_.find(uid);
  if (record_it == this->recorder_.end())
    return;

  const auto &record = record_it->second;
  if (this->current_uid_ == 0) {
    if (record.last_uid != 0)
      return;
  } else {
    auto current_it = this->recorder_.find(this->current_uid_);
    if (current_it == this->recorder_.end())
      return;

    const auto &next_records = current_it->second.next_records;
    if (record.last_uid != this->current_uid_ ||
        std::find(next_records.begin(), next_records.end(), uid) ==
            next_records.end()) {
      return;
    }
  }

  if (record.color == 0) {
    for (const auto &stone : record.preset_stones)
      this->set_state_of_position_(stone.color, stone.row, stone.column);
  } else {
    this->set_state_at_flat_(record.position, record.color);
    for (auto position : record.captured)
      this->set_state_at_flat_(position, 0);
  }
  this->current_uid_ = uid;
}

inline void GoCore::backward_() {
  if (this->current_uid_ == 0)
    return;

  auto record_it = this->recorder_.find(this->current_uid_);
  if (record_it == this->recorder_.end()) {
    this->current_uid_ = 0;
    return;
  }

  const auto &record = record_it->second;
  if (record.color == 0) {
    for (const auto &stone : record.preset_recovery)
      this->set_state_of_position_(stone.color, stone.row, stone.column);
  } else {
    this->set_state_at_flat_(record.position, 0);
    const auto captured_color = record.color == 1 ? 2 : 1;
    for (auto position : record.captured)
      this->set_state_at_flat_(position, captured_color);
  }
  this->current_uid_ = record.last_uid;
}
} // namespace nd::go

#endif // GOBAN_GO_CORE_HPP
