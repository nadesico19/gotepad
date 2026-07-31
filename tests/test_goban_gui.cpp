#include "../src/go_core.hpp"

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace {
using Board = nd::go::GoCore;
using TreeNode = nd::go::GoCoreRecordTreeNode;

constexpr int BoardSize = 19;
constexpr int Black = 1;
constexpr int White = 2;
constexpr const char *Columns = "ABCDEFGHJKLMNOPQRST";

Board g_board{BoardSize};
int g_next_color = White;
int g_last_result = 0;
uint64_t g_current_uid = 0;

struct MoveInfo {
  uint64_t parent_uid{};
  int color{};
  size_t row{};
  size_t column{};
};

struct ChildMove {
  uint64_t uid{};
  int color{};
  size_t row{};
  size_t column{};
};

std::map<uint64_t, MoveInfo> g_moves;

struct Layout {
  int cell{};
  int origin_x{};
  int origin_y{};
  int stone_radius{};
};

Layout make_layout(const RECT &client) {
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  const int margin = 58;
  const int usable = std::max(1, std::min(width, height) - margin * 2);
  const int cell = std::max(18, usable / (BoardSize - 1));
  const int board_px = cell * (BoardSize - 1);

  Layout layout{};
  layout.cell = cell;
  layout.origin_x = (width - board_px) / 2;
  layout.origin_y = (height - board_px) / 2;
  layout.stone_radius = std::max(7, cell / 2 - 3);
  return layout;
}

COLORREF board_color() { return RGB(219, 178, 111); }

std::string status_text() {
  std::string side = g_next_color == Black ? "Black" : "White";
  std::string status = "Next: " + side +
                       "    Left: place/roam stone    Right: takeback    "
                       "Arrows: roam    Esc: initial board";
  if (g_last_result == -1)
    status += "    Last: out of board / invalid color";
  if (g_last_result == -2)
    status += "    Last: occupied";
  if (g_last_result == -3)
    status += "    Last: suicide";
  if (g_last_result == -4)
    status += "    Last: ko forbidden";
  return status;
}

uint64_t max_uid(const TreeNode &node) {
  uint64_t result = node.uid;
  for (const auto &child : node.children) {
    result = std::max(result, max_uid(child));
  }
  return result;
}

const TreeNode *find_tree_node(const TreeNode &node, uint64_t uid) {
  if (node.uid == uid)
    return &node;
  for (const auto &child : node.children) {
    const TreeNode *found = find_tree_node(child, uid);
    if (found)
      return found;
  }
  return nullptr;
}

std::vector<ChildMove> current_child_moves() {
  std::vector<ChildMove> result;
  const auto tree = g_board.record_tree();
  const TreeNode *node = find_tree_node(tree, g_current_uid);
  if (!node)
    return result;

  result.reserve(node->children.size());
  for (const auto &child : node->children) {
    result.push_back(ChildMove{child.uid, child.color, child.row, child.column});
  }
  return result;
}

uint64_t find_child_move(int color, size_t row, size_t column,
                         const std::vector<ChildMove> &children) {
  for (const auto &move : children) {
    if (move.color == color && move.row == row && move.column == column) {
      return move.uid;
    }
  }
  return 0;
}

uint64_t find_current_path_move(size_t row, size_t column, int color) {
  uint64_t cursor = g_current_uid;
  while (cursor != 0) {
    const auto it = g_moves.find(cursor);
    if (it == g_moves.end())
      return 0;

    const auto &move = it->second;
    if (move.color == color && move.row == row && move.column == column) {
      return cursor;
    }
    cursor = move.parent_uid;
  }
  return 0;
}

void set_current_uid(uint64_t uid) {
  g_current_uid = uid;
  if (uid == 0) {
    g_next_color = White;
    return;
  }

  const auto it = g_moves.find(uid);
  if (it != g_moves.end()) {
    g_next_color = it->second.color == Black ? White : Black;
  }
}

void roam_to_uid(uint64_t uid) {
  g_board.roaming_to(uid);
  set_current_uid(uid);
  g_last_result = 0;
}
void draw_centered_text(HDC hdc, int x, int y, const std::string &text) {
  SIZE size{};
  GetTextExtentPoint32A(hdc, text.c_str(), static_cast<int>(text.size()),
                        &size);
  TextOutA(hdc, x - size.cx / 2, y - size.cy / 2, text.c_str(),
           static_cast<int>(text.size()));
}

void draw_board(HDC hdc, const RECT &client) {
  const Layout layout = make_layout(client);
  const int board_px = layout.cell * (BoardSize - 1);
  const int left = layout.origin_x;
  const int top = layout.origin_y;
  const int right = left + board_px;
  const int bottom = top + board_px;

  HBRUSH board_brush = CreateSolidBrush(board_color());
  FillRect(hdc, &client, board_brush);
  DeleteObject(board_brush);

  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, RGB(24, 24, 24));

  HPEN line_pen = CreatePen(PS_SOLID, 1, RGB(40, 30, 20));
  HGDIOBJ old_pen = SelectObject(hdc, line_pen);

  for (int index = 0; index < BoardSize; ++index) {
    const int x = left + index * layout.cell;
    const int y = top + index * layout.cell;

    MoveToEx(hdc, left, y, nullptr);
    LineTo(hdc, right, y);
    MoveToEx(hdc, x, top, nullptr);
    LineTo(hdc, x, bottom);
  }

  SelectObject(hdc, old_pen);
  DeleteObject(line_pen);

  HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  HGDIOBJ old_font = SelectObject(hdc, font);

  for (int index = 0; index < BoardSize; ++index) {
    const int x = left + index * layout.cell;
    const int y = top + index * layout.cell;
    const std::string column(1, Columns[index]);
    const std::string row = std::to_string(index + 1);

    draw_centered_text(hdc, x, top - 26, column);
    draw_centered_text(hdc, x, bottom + 28, column);
    draw_centered_text(hdc, left - 30, y, row);
    draw_centered_text(hdc, right + 30, y, row);
  }

  HBRUSH star_brush = CreateSolidBrush(RGB(35, 25, 15));
  HGDIOBJ old_brush = SelectObject(hdc, star_brush);
  const int stars[] = {4, 10, 16};
  for (int row : stars) {
    for (int column : stars) {
      const int x = left + (column - 1) * layout.cell;
      const int y = top + (row - 1) * layout.cell;
      Ellipse(hdc, x - 4, y - 4, x + 5, y + 5);
    }
  }
  SelectObject(hdc, old_brush);
  DeleteObject(star_brush);

  for (int row = 1; row <= BoardSize; ++row) {
    for (int column = 1; column <= BoardSize; ++column) {
      const int state = g_board.state_of_position(row, column);
      if (state != Black && state != White)
        continue;

      const int x = left + (column - 1) * layout.cell;
      const int y = top + (row - 1) * layout.cell;
      HBRUSH stone_brush = CreateSolidBrush(
          state == Black ? RGB(16, 16, 16) : RGB(242, 242, 236));
      HPEN stone_pen = CreatePen(PS_SOLID, 1, RGB(20, 20, 20));
      HGDIOBJ old_stone_brush = SelectObject(hdc, stone_brush);
      HGDIOBJ old_stone_pen = SelectObject(hdc, stone_pen);

      Ellipse(hdc, x - layout.stone_radius, y - layout.stone_radius,
              x + layout.stone_radius, y + layout.stone_radius);

      SelectObject(hdc, old_stone_pen);
      SelectObject(hdc, old_stone_brush);
      DeleteObject(stone_pen);
      DeleteObject(stone_brush);
    }
  }

  const auto children = current_child_moves();
  if (children.size() > 1) {
    HPEN marker_pen = CreatePen(PS_SOLID, 1, RGB(140, 20, 20));
    HBRUSH marker_brush = CreateSolidBrush(RGB(255, 238, 130));
    HGDIOBJ old_marker_pen = SelectObject(hdc, marker_pen);
    HGDIOBJ old_marker_brush = SelectObject(hdc, marker_brush);
    SetTextColor(hdc, RGB(120, 20, 20));

    const size_t marker_count = std::min<size_t>(children.size(), 26);
    for (size_t index = 0; index < marker_count; ++index) {
      const auto &move = children[index];
      const int x = left + (static_cast<int>(move.column) - 1) * layout.cell;
      const int y = top + (static_cast<int>(move.row) - 1) * layout.cell;
      const int radius = std::max(8, layout.cell / 4);
      Ellipse(hdc, x - radius, y - radius, x + radius + 1, y + radius + 1);

      const std::string letter(1, static_cast<char>('A' + index));
      draw_centered_text(hdc, x, y, letter);
    }

    SelectObject(hdc, old_marker_brush);
    SelectObject(hdc, old_marker_pen);
    DeleteObject(marker_brush);
    DeleteObject(marker_pen);
    SetTextColor(hdc, RGB(24, 24, 24));
  }
  const std::string status = status_text();
  TextOutA(hdc, 16, 14, status.c_str(), static_cast<int>(status.size()));
  SelectObject(hdc, old_font);
}

bool point_to_board(HWND hwnd, int x, int y, size_t &row, size_t &column) {
  RECT client{};
  GetClientRect(hwnd, &client);
  const Layout layout = make_layout(client);

  const int rel_x = x - layout.origin_x;
  const int rel_y = y - layout.origin_y;
  const int board_px = layout.cell * (BoardSize - 1);
  const int tolerance = layout.cell / 2;

  if (rel_x < -tolerance || rel_y < -tolerance ||
      rel_x > board_px + tolerance || rel_y > board_px + tolerance) {
    return false;
  }

  const int c = (rel_x + layout.cell / 2) / layout.cell;
  const int r = (rel_y + layout.cell / 2) / layout.cell;
  if (r < 0 || r >= BoardSize || c < 0 || c >= BoardSize)
    return false;

  row = static_cast<size_t>(r + 1);
  column = static_cast<size_t>(c + 1);
  return true;
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  switch (message) {
  case WM_LBUTTONDOWN: {
    SetFocus(hwnd);

    size_t row{};
    size_t column{};
    if (point_to_board(hwnd, GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam), row,
                       column)) {
      const int state = g_board.state_of_position(row, column);
      if (state == Black || state == White) {
        const auto uid = find_current_path_move(row, column, state);
        if (uid != 0) {
          roam_to_uid(uid);
          InvalidateRect(hwnd, nullptr, TRUE);
        }
        return 0;
      }

      const auto old_current_uid = g_current_uid;
      const auto children = current_child_moves();
      const auto existing_child_uid =
          find_child_move(g_next_color, row, column, children);

      g_last_result = g_board.place_stone(g_next_color, row, column);
      if (g_last_result == 0) {
        if (existing_child_uid != 0) {
          set_current_uid(existing_child_uid);
        } else {
          const auto uid = max_uid(g_board.record_tree());
          g_moves[uid] = MoveInfo{old_current_uid, g_next_color, row, column};
          set_current_uid(uid);
        }
      }
      InvalidateRect(hwnd, nullptr, TRUE);
    }
    return 0;
  }
  case WM_RBUTTONDOWN: {
    auto removed = g_board.takeback();
    if (!removed.empty()) {
      const auto next_uid = removed.front().last_uid;
      for (const auto &record : removed) {
        g_moves.erase(record.uid);
      }
      g_current_uid = next_uid;
      g_next_color = removed.front().color;
      g_last_result = 0;
      InvalidateRect(hwnd, nullptr, TRUE);
    }
    return 0;
  }
  case WM_KEYDOWN: {
    if (wparam == VK_ESCAPE) {
      roam_to_uid(0);
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    }

    if (wparam == VK_LEFT) {
      if (g_current_uid != 0) {
        const auto it = g_moves.find(g_current_uid);
        if (it != g_moves.end()) {
          roam_to_uid(it->second.parent_uid);
          InvalidateRect(hwnd, nullptr, TRUE);
        }
      }
      return 0;
    }

    if (wparam == VK_RIGHT) {
      const auto children = current_child_moves();
      if (children.size() == 1) {
        roam_to_uid(children.front().uid);
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    }
    return DefWindowProcA(hwnd, message, wparam, lparam);
  }
  case WM_PAINT: {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT client{};
    GetClientRect(hwnd, &client);
    draw_board(hdc, client);
    EndPaint(hwnd, &ps);
    return 0;
  }
  case WM_SIZE:
    InvalidateRect(hwnd, nullptr, TRUE);
    return 0;
  case WM_DESTROY:
    PostQuitMessage(0);
    return 0;
  default:
    return DefWindowProcA(hwnd, message, wparam, lparam);
  }
}
} // namespace

int WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR, int show_command) {
  if (g_board.preset_stone(Black, 4, 16) != 0 ||
      g_board.preset_stone(Black, 16, 4) != 0) {
    return 1;
  }

  const char class_name[] = "GobanGuiTestWindow";

  WNDCLASSA wc{};
  wc.lpfnWndProc = window_proc;
  wc.hInstance = instance;
  wc.lpszClassName = class_name;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);

  if (!RegisterClassA(&wc))
    return 1;

  HWND hwnd = CreateWindowExA(0, class_name, "Goban GUI Test",
                              WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                              900, 940, nullptr, nullptr, instance, nullptr);

  if (!hwnd)
    return 1;

  ShowWindow(hwnd, show_command);
  UpdateWindow(hwnd);
  SetFocus(hwnd);

  MSG message{};
  while (GetMessageA(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageA(&message);
  }

  return static_cast<int>(message.wParam);
}
