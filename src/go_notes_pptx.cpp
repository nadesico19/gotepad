// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.
//
// 将笔记导出到.pptx文件的实现。

#include "go_notes.hpp"

#include <lunasvg.h>
#include <miniz.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nd::go {
namespace {
constexpr char kNoNotesMessage[] = "[GNE0025] no notes to export";
constexpr char kTemplateReadMessage[] = "[GNE0026] cannot read PPTX template";
constexpr char kTemplateInvalidMessage[] = "[GNE0027] invalid PPTX template";
constexpr char kPptxWriteMessage[] = "[GNE0028] cannot write PPTX file";
constexpr char kPptxRasterizeMessage[] =
    "[GNE0034] cannot rasterize board image";
constexpr double kCommentPageUnits = 500.0;
constexpr int kPngBoardSize = 1600;

struct ExportPage {
  uint64_t uid{};
  uint64_t anchor_uid{};
  size_t figure_index{};
  size_t continuation_index{};
  GoNotesRecord note{};
  std::string comment{};
};

struct NumberedMove {
  uint64_t uid{};
  uint16_t color{};
  uint16_t row{};
  uint16_t column{};
  int absolute_number{};
  size_t path_index{};
};

struct BoardDiagram {
  std::string svg{};
  std::string repeated_numbers{};
};

struct PngWriteContext {
  std::vector<uint8_t> *bytes{};
  bool valid{true};
};

void append_png_bytes_(void *closure, void *data, int size) noexcept {
  auto *context = static_cast<PngWriteContext *>(closure);
  if (context == nullptr || context->bytes == nullptr || data == nullptr ||
      size <= 0 || !context->valid)
    return;
  try {
    const auto *begin = static_cast<const uint8_t *>(data);
    context->bytes->insert(context->bytes->end(), begin, begin + size);
  } catch (...) {
    context->valid = false;
  }
}

bool svg_to_png_(const std::string &svg, std::vector<uint8_t> &png) {
  png.clear();
  try {
    auto document = lunasvg::Document::loadFromData(svg);
    if (!document)
      return false;
    auto bitmap =
        document->renderToBitmap(kPngBoardSize, kPngBoardSize, 0xFFFFFFFF);
    if (bitmap.isNull())
      return false;
    PngWriteContext context{&png, true};
    return bitmap.writeToPng(append_png_bytes_, &context) && context.valid &&
           !png.empty();
  } catch (...) {
    png.clear();
    return false;
  }
}

std::filesystem::path utf8_path_(const std::string &path) {
  return std::filesystem::u8path(path);
}

bool read_file_(const std::string &path, std::vector<uint8_t> &bytes) {
  std::ifstream input{utf8_path_(path), std::ios::binary};
  if (!input)
    return false;
  input.seekg(0, std::ios::end);
  const auto size = input.tellg();
  if (size < 0)
    return false;
  input.seekg(0, std::ios::beg);
  bytes.resize(static_cast<size_t>(size));
  if (!bytes.empty())
    input.read(reinterpret_cast<char *>(bytes.data()), size);
  return static_cast<bool>(input) || bytes.empty();
}

bool write_file_(const std::string &path, const void *data, size_t size) {
  const auto output_path = utf8_path_(path);
  std::error_code error{};
  if (output_path.has_parent_path())
    std::filesystem::create_directories(output_path.parent_path(), error);
  if (error)
    return false;
  std::ofstream output{output_path, std::ios::binary | std::ios::trunc};
  if (!output)
    return false;
  output.write(static_cast<const char *>(data),
               static_cast<std::streamsize>(size));
  return static_cast<bool>(output);
}

std::vector<uint8_t> bytes_(std::string value) {
  return {value.begin(), value.end()};
}

std::string text_(const std::vector<uint8_t> &bytes) {
  return {bytes.begin(), bytes.end()};
}

std::string xml_escape_(std::string_view value) {
  std::string result{};
  result.reserve(value.size());
  for (const char character : value) {
    switch (character) {
    case '&':
      result += "&amp;";
      break;
    case '<':
      result += "&lt;";
      break;
    case '>':
      result += "&gt;";
      break;
    case '"':
      result += "&quot;";
      break;
    case '\'':
      result += "&apos;";
      break;
    default:
      result.push_back(character);
      break;
    }
  }
  return result;
}

size_t utf8_character_size_(unsigned char first) {
  if ((first & 0x80U) == 0)
    return 1;
  if ((first & 0xE0U) == 0xC0U)
    return 2;
  if ((first & 0xF0U) == 0xE0U)
    return 3;
  if ((first & 0xF8U) == 0xF0U)
    return 4;
  return 1;
}

double text_units_(std::string_view text) {
  double units = 0.0;
  for (size_t offset = 0; offset < text.size();) {
    const auto length =
        std::min(utf8_character_size_(static_cast<unsigned char>(text[offset])),
                 text.size() - offset);
    if (text[offset] == '\n')
      units += 18.0;
    else
      units += length == 1 ? 0.55 : 1.0;
    offset += length;
  }
  return units;
}

bool is_break_character_(std::string_view character) {
  return character == "\n" || character == "。" || character == "！" ||
         character == "？" || character == "；" || character == "，" ||
         character == "." || character == "!" || character == "?" ||
         character == ";";
}

std::vector<std::string> split_comment_(const std::string &comment) {
  if (comment.empty())
    return {{}};

  std::vector<std::string> pages{};
  size_t page_begin = 0;
  size_t offset = 0;
  size_t last_break = std::string::npos;
  double units = 0.0;
  while (offset < comment.size()) {
    const auto length = std::min(
        utf8_character_size_(static_cast<unsigned char>(comment[offset])),
        comment.size() - offset);
    const std::string_view character{comment.data() + offset, length};
    const double character_units =
        character == "\n" ? 18.0 : (length == 1 ? 0.55 : 1.0);
    if (units + character_units > kCommentPageUnits && offset > page_begin) {
      size_t page_end = offset;
      if (last_break != std::string::npos &&
          last_break > page_begin + (offset - page_begin) * 2 / 3) {
        page_end = last_break;
      }
      pages.emplace_back(comment.substr(page_begin, page_end - page_begin));
      page_begin = page_end;
      while (page_begin < comment.size() &&
             (comment[page_begin] == '\n' || comment[page_begin] == '\r'))
        ++page_begin;
      offset = page_begin;
      last_break = std::string::npos;
      units = 0.0;
      continue;
    }
    units += character_units;
    offset += length;
    if (is_break_character_(character))
      last_break = offset;
  }
  pages.emplace_back(comment.substr(page_begin));
  return pages;
}

void collect_pages_(const GoNotes &notes, const GoCoreRecordTreeNode &node,
                    uint64_t ancestor_object_uid, size_t &figure_index,
                    std::vector<ExportPage> &pages) {
  const auto records = notes.notes_at(node.uid);
  if (!records.empty() || node.children.empty()) {
    ++figure_index;
    if (records.empty()) {
      pages.push_back({node.uid, ancestor_object_uid, figure_index, 0, {}, {}});
    } else {
      for (const auto &record : records) {
        const auto comments = split_comment_(record.comment);
        for (size_t continuation = 0; continuation < comments.size();
             ++continuation) {
          pages.push_back({node.uid, ancestor_object_uid, figure_index,
                           continuation, record, comments[continuation]});
        }
      }
    }
    ancestor_object_uid = node.uid;
  }
  for (const auto &child : node.children)
    collect_pages_(notes, child, ancestor_object_uid, figure_index, pages);
}

bool find_path_(const GoCoreRecordTreeNode &node, uint64_t target_uid,
                std::vector<GoCoreRecordTreeNode> &path) {
  path.push_back(node);
  if (node.uid == target_uid)
    return true;
  for (const auto &child : node.children) {
    if (find_path_(child, target_uid, path))
      return true;
  }
  path.pop_back();
  return false;
}

std::vector<NumberedMove>
numbered_moves_(const std::vector<GoCoreRecordTreeNode> &path) {
  std::vector<NumberedMove> moves{};
  int absolute_number = 0;
  for (size_t path_index = 0; path_index < path.size(); ++path_index) {
    const auto &node = path[path_index];
    if (node.color != 1 && node.color != 2)
      continue;
    moves.push_back({node.uid, node.color, node.row, node.column,
                     ++absolute_number, path_index});
  }
  return moves;
}

std::string svg_number_(double value) {
  std::ostringstream stream{};
  stream << std::fixed << std::setprecision(2) << value;
  auto result = stream.str();
  while (result.size() > 1 && result.back() == '0')
    result.pop_back();
  if (!result.empty() && result.back() == '.')
    result.pop_back();
  return result;
}

std::vector<int> star_coordinates_(int board_size) {
  if (board_size == 9)
    return {3, 5, 7};
  if (board_size == 11)
    return {3, 6, 9};
  if (board_size == 13)
    return {4, 7, 10};
  if (board_size == 15)
    return {4, 8, 12};
  if (board_size == 19)
    return {4, 10, 16};
  if (board_size >= 7 && board_size % 2 == 1)
    return {4, (board_size + 1) / 2, board_size - 3};
  return {};
}

std::string sequential_label_(size_t index) {
  if (index < 26)
    return std::string(1, static_cast<char>('A' + index));
  if (index < 52)
    return std::string(1, static_cast<char>('a' + index - 26));
  return {};
}

std::string text_svg_(double x, double y, const std::string &value,
                      const std::string &color, double font_size,
                      bool bold = true) {
  std::ostringstream svg{};
  svg << "<text x=\"" << svg_number_(x) << "\" y=\"" << svg_number_(y)
      << "\" text-anchor=\"middle\" dominant-baseline=\"alphabetic\" "
         "dy=\"0.34em\" "
         "font-family=\"Arial,sans-serif\" font-size=\""
      << svg_number_(font_size) << "\" font-weight=\"" << (bold ? "700" : "400")
      << "\" fill=\"" << color << "\">" << xml_escape_(value) << "</text>";
  return svg.str();
}

std::string symbol_svg_(const std::string &symbol, double x, double y,
                        double size, const std::string &color,
                        double stroke_width) {
  std::ostringstream svg{};
  const auto number = [](double value) { return svg_number_(value); };
  if (symbol == "TR") {
    svg << "<path d=\"M " << number(x) << ' ' << number(y - size) << " L "
        << number(x - size * 0.87) << ' ' << number(y + size * 0.5) << " L "
        << number(x + size * 0.87) << ' ' << number(y + size * 0.5)
        << " Z\" fill=\"none\" stroke=\"" << color << "\" stroke-width=\""
        << number(stroke_width) << "\" stroke-linejoin=\"round\"/>";
  } else if (symbol == "SQ") {
    svg << "<rect x=\"" << number(x - size * 0.75) << "\" y=\""
        << number(y - size * 0.75) << "\" width=\"" << number(size * 1.5)
        << "\" height=\"" << number(size * 1.5) << "\" fill=\"none\" stroke=\""
        << color << "\" stroke-width=\"" << number(stroke_width) << "\"/>";
  } else if (symbol == "CR") {
    svg << "<circle cx=\"" << number(x) << "\" cy=\"" << number(y) << "\" r=\""
        << number(size * 0.78) << "\" fill=\"none\" stroke=\"" << color
        << "\" stroke-width=\"" << number(stroke_width) << "\"/>";
  } else if (symbol == "MA") {
    svg << "<path d=\"M " << number(x - size * 0.7) << ' '
        << number(y - size * 0.7) << " L " << number(x + size * 0.7) << ' '
        << number(y + size * 0.7) << " M " << number(x + size * 0.7) << ' '
        << number(y - size * 0.7) << " L " << number(x - size * 0.7) << ' '
        << number(y + size * 0.7) << "\" fill=\"none\" stroke=\"" << color
        << "\" stroke-width=\"" << number(stroke_width)
        << "\" stroke-linecap=\"round\"/>";
  }
  return svg.str();
}

BoardDiagram render_board_(const GoNotes &notes, const ExportPage &page,
                           const GoCoreRecordTreeNode &root) {
  BoardDiagram result{};
  std::vector<GoCoreRecordTreeNode> path{};
  if (!find_path_(root, page.uid, path))
    return result;

  const int board_size = notes.board_size();
  const auto states = notes.position_states_at(page.uid);
  if (states.size() !=
      static_cast<size_t>(board_size) * static_cast<size_t>(board_size))
    return result;

  const auto moves = numbered_moves_(path);
  size_t first_move = 0;
  if (page.note.numbering == 0 || page.note.numbering == 1) {
    const auto anchor =
        std::find_if(path.begin(), path.end(), [&](const auto &node) {
          return node.uid == page.anchor_uid;
        });
    const size_t anchor_path_index =
        anchor == path.end()
            ? 0
            : static_cast<size_t>(std::distance(path.begin(), anchor));
    first_move = static_cast<size_t>(std::distance(
        moves.begin(),
        std::find_if(moves.begin(), moves.end(), [&](const auto &move) {
          return move.path_index > anchor_path_index;
        })));
  }

  std::map<std::pair<uint16_t, uint16_t>, std::vector<int>> labels{};
  if (page.note.numbering != 3) {
    const size_t begin = page.note.numbering == 2 ? 0 : first_move;
    int relative_number = 0;
    for (size_t index = begin; index < moves.size(); ++index) {
      ++relative_number;
      const int label = page.note.numbering == 0 ? relative_number
                                                 : moves[index].absolute_number;
      labels[{moves[index].row, moves[index].column}].push_back(label);
    }
  }

  std::vector<std::string> repetitions{};
  for (const auto &[position, numbers] : labels) {
    if (numbers.size() < 2)
      continue;
    std::ostringstream entry{};
    for (size_t index = 0; index < numbers.size(); ++index) {
      if (index != 0)
        entry << '=';
      entry << numbers[index];
    }
    repetitions.push_back(entry.str());
  }
  for (size_t index = 0; index < repetitions.size(); ++index) {
    if (index != 0)
      result.repeated_numbers += "，";
    result.repeated_numbers += repetitions[index];
  }

  constexpr double canvas = 800.0;
  constexpr double margin = 42.0;
  const double span = canvas - margin * 2.0;
  const double cell = board_size > 1 ? span / (board_size - 1) : span;
  const double stone_radius = std::min(cell * 0.47, 25.0);
  const double mark_size = stone_radius * 0.7;
  const double mark_stroke = std::max(2.2, cell * 0.075);
  const auto coordinate = [&](int value) {
    return board_size > 1 ? margin + (value - 1) * cell : canvas / 2.0;
  };

  std::ostringstream svg{};
  svg << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" "
         "height=\"800\" viewBox=\"0 0 800 800\">"
         "<rect width=\"800\" height=\"800\" fill=\"#ffffff\"/>";
  if (board_size > 1) {
    for (int index = 1; index <= board_size; ++index) {
      const double value = coordinate(index);
      const bool outer = index == 1 || index == board_size;
      svg << "<line x1=\"" << svg_number_(coordinate(1)) << "\" y1=\""
          << svg_number_(value) << "\" x2=\""
          << svg_number_(coordinate(board_size)) << "\" y2=\""
          << svg_number_(value) << "\" stroke=\"#161616\" stroke-width=\""
          << (outer ? "2.4" : "1.2") << "\"/>"
          << "<line x1=\"" << svg_number_(value) << "\" y1=\""
          << svg_number_(coordinate(1)) << "\" x2=\"" << svg_number_(value)
          << "\" y2=\"" << svg_number_(coordinate(board_size))
          << "\" stroke=\"#161616\" stroke-width=\"" << (outer ? "2.4" : "1.2")
          << "\"/>";
    }
  }
  const auto stars = star_coordinates_(board_size);
  for (const auto row : stars) {
    for (const auto column : stars) {
      svg << "<circle cx=\"" << svg_number_(coordinate(column)) << "\" cy=\""
          << svg_number_(coordinate(row)) << "\" r=\""
          << svg_number_(std::max(2.8, cell * 0.09)) << "\" fill=\"#111111\"/>";
    }
  }

  for (int row = 1; row <= board_size; ++row) {
    for (int column = 1; column <= board_size; ++column) {
      const auto state =
          states[static_cast<size_t>(row - 1) * board_size + column - 1];
      const double x = coordinate(column);
      const double y = coordinate(row);
      if (state == 1) {
        svg << "<circle cx=\"" << svg_number_(x) << "\" cy=\"" << svg_number_(y)
            << "\" r=\"" << svg_number_(stone_radius)
            << "\" fill=\"#111111\" stroke=\"#000000\" stroke-width=\"1.4\"/>";
      } else if (state == 2) {
        svg << "<circle cx=\"" << svg_number_(x) << "\" cy=\"" << svg_number_(y)
            << "\" r=\"" << svg_number_(stone_radius)
            << "\" fill=\"#ffffff\" stroke=\"#111111\" stroke-width=\"1.6\"/>";
      }
    }
  }

  for (const auto &[position, numbers] : labels) {
    if (numbers.empty())
      continue;
    const int row = position.first;
    const int column = position.second;
    const auto state =
        states[static_cast<size_t>(row - 1) * board_size + column - 1];
    const double x = coordinate(column);
    const double y = coordinate(row);
    if (state == 0) {
      svg << "<circle cx=\"" << svg_number_(x) << "\" cy=\"" << svg_number_(y)
          << "\" r=\"" << svg_number_(stone_radius * 0.58)
          << "\" fill=\"#ffffff\"/>";
    }
    const std::string value = std::to_string(numbers.front());
    const double font_size =
        value.size() >= 3 ? stone_radius * 0.78 : stone_radius * 1.02;
    svg << text_svg_(x, y, value, state == 1 ? "#ffffff" : "#000000",
                     font_size);
  }

  for (size_t index = 0; index < page.note.sequential_marks.size(); ++index) {
    const auto &[row, column] = page.note.sequential_marks[index];
    if (row < 1 || row > board_size || column < 1 || column > board_size)
      continue;
    const auto state =
        states[static_cast<size_t>(row - 1) * board_size + column - 1];
    svg << text_svg_(coordinate(column), coordinate(row),
                     sequential_label_(index),
                     state == 1 ? "#ffffff" : "#000000", stone_radius * 1.08);
  }

  for (const auto &[row, column, symbol] : page.note.symbol_marks) {
    if (row < 1 || row > board_size || column < 1 || column > board_size)
      continue;
    const auto state =
        states[static_cast<size_t>(row - 1) * board_size + column - 1];
    svg << symbol_svg_(symbol, coordinate(column), coordinate(row), mark_size,
                       state == 1 ? "#ffffff" : "#000000", mark_stroke);
  }

  svg << "</svg>";
  result.svg = svg.str();
  return result;
}

std::optional<std::pair<size_t, size_t>> shape_range_(const std::string &xml,
                                                      const std::string &name) {
  const auto name_position = xml.find("name=\"" + name + "\"");
  if (name_position == std::string::npos)
    return std::nullopt;
  const auto begin = xml.rfind("<p:sp>", name_position);
  const auto end_tag = xml.find("</p:sp>", name_position);
  if (begin == std::string::npos || end_tag == std::string::npos)
    return std::nullopt;
  return std::make_pair(begin, end_tag + std::strlen("</p:sp>"));
}

std::string text_body_(const std::string &value, int font_size, bool bold,
                       const std::string &color, const std::string &typeface,
                       const std::string &alignment,
                       int line_spacing = 138000) {
  std::ostringstream body{};
  body << "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" "
          "rIns=\"0\" bIns=\"0\" anchor=\"t\" "
          "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
          "<a:normAutofit fontScale=\"100000\"/></a:bodyPr>"
          "<a:lstStyle xmlns:a=\"http://schemas.openxmlformats.org/drawingml/"
          "2006/main\"/>";
  size_t begin = 0;
  do {
    const auto line_end = value.find('\n', begin);
    auto line =
        value.substr(begin, line_end == std::string::npos ? std::string::npos
                                                          : line_end - begin);
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    body << "<a:p xmlns:a=\"http://schemas.openxmlformats.org/drawingml/"
            "2006/main\"><a:pPr algn=\""
         << alignment << "\"><a:lnSpc><a:spcPct val=\"" << line_spacing
         << "\"/></a:lnSpc><a:buNone/><a:defRPr sz=\"" << font_size << "\" b=\""
         << (bold ? 1 : 0) << "\"><a:solidFill><a:srgbClr val=\"" << color
         << "\"/></a:solidFill><a:latin typeface=\"" << typeface
         << "\"/><a:ea typeface=\"" << typeface << "\"/><a:cs typeface=\""
         << typeface << "\"/></a:defRPr></a:pPr>";
    if (line.empty()) {
      body << "<a:endParaRPr sz=\"" << font_size << "\"/>";
    } else {
      body << "<a:r><a:rPr sz=\"" << font_size << "\" b=\"" << (bold ? 1 : 0)
           << "\"><a:solidFill><a:srgbClr val=\"" << color
           << "\"/></a:solidFill><a:latin typeface=\"" << typeface
           << "\"/><a:ea typeface=\"" << typeface << "\"/><a:cs typeface=\""
           << typeface << "\"/></a:rPr><a:t xml:space=\"preserve\">"
           << xml_escape_(line) << "</a:t></a:r>";
    }
    body << "</a:p>";
    if (line_end == std::string::npos)
      break;
    begin = line_end + 1;
  } while (begin <= value.size());
  body << "</p:txBody>";
  return body.str();
}

bool replace_shape_text_(std::string &xml, const std::string &name,
                         const std::string &value, int font_size, bool bold,
                         const std::string &color, const std::string &typeface,
                         const std::string &alignment = "l",
                         int line_spacing = 138000) {
  const auto shape = shape_range_(xml, name);
  if (!shape)
    return false;
  const auto body_begin = xml.find("<p:txBody>", shape->first);
  const auto body_end_tag = xml.find("</p:txBody>", body_begin);
  if (body_begin == std::string::npos || body_end_tag == std::string::npos ||
      body_end_tag >= shape->second)
    return false;
  const auto replacement = text_body_(value, font_size, bold, color, typeface,
                                      alignment, line_spacing);
  xml.replace(body_begin,
              body_end_tag + std::strlen("</p:txBody>") - body_begin,
              replacement);
  return true;
}

bool remove_shape_(std::string &xml, const std::string &name) {
  const auto range = shape_range_(xml, name);
  if (!range)
    return false;
  xml.erase(range->first, range->second - range->first);
  return true;
}

std::string picture_xml_(const std::string &relationship_id) {
  return "<p:pic><p:nvPicPr><p:cNvPr id=\"6\" name=\"BOARD_IMAGE\"/>"
         "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\" "
         "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"/>"
         "</p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill>"
         "<a:blip xmlns:a=\"http://schemas.openxmlformats.org/drawingml/"
         "2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships\" r:embed=\"" +
         relationship_id +
         "\"/><a:stretch xmlns:a=\"http://schemas.openxmlformats.org/"
         "drawingml/2006/main\"><a:fillRect/></a:stretch></p:blipFill>"
         "<p:spPr><a:xfrm xmlns:a=\"http://schemas.openxmlformats.org/"
         "drawingml/2006/main\"><a:off x=\"647700\" y=\"647700\"/>"
         "<a:ext cx=\"4648200\" cy=\"4648200\"/></a:xfrm>"
         "<a:prstGeom prst=\"rect\" xmlns:a=\"http://schemas.openxmlformats."
         "org/drawingml/2006/main\"><a:avLst/></a:prstGeom>"
         "<a:ln xmlns:a=\"http://schemas.openxmlformats.org/drawingml/"
         "2006/main\"><a:noFill/></a:ln></p:spPr></p:pic>";
}

bool replace_board_shape_(std::string &xml) {
  const auto range = shape_range_(xml, "BOARD_IMAGE_SLOT");
  if (!range)
    return false;
  xml.replace(range->first, range->second - range->first,
              picture_xml_("rIdBoard"));
  return remove_shape_(xml, "BOARD_SLOT_LABEL");
}

std::string page_title_(const ExportPage &page) {
  std::string title = page.note.title.empty()
                          ? "第" + std::to_string(page.figure_index) + "图"
                          : page.note.title;
  if (page.continuation_index > 0)
    title += "（续）";
  return title;
}

std::string header_(const GoNotesSgfMetadata &metadata) {
  return metadata.game_name.empty() ? "围棋笔记" : metadata.game_name;
}

std::string footer_(const GoNotesSgfMetadata &metadata) {
  if (!metadata.black_name.empty() || !metadata.white_name.empty())
    return "黑：" + (metadata.black_name.empty() ? "—" : metadata.black_name) +
           "　白：" + (metadata.white_name.empty() ? "—" : metadata.white_name);
  if (!metadata.source.empty())
    return metadata.source;
  return "Gotepad";
}

int comment_font_size_(const std::string &comment) {
  const auto units = text_units_(comment);
  if (units <= 280.0)
    return 1350;
  if (units <= 380.0)
    return 1200;
  return 1000;
}

std::string build_slide_xml_(const std::string &template_xml,
                             const GoNotesSgfMetadata &metadata,
                             const ExportPage &page,
                             const BoardDiagram &diagram, size_t page_number) {
  std::string xml = template_xml;
  if (!replace_shape_text_(xml, "PAGE_HEADER", header_(metadata), 825, true,
                           "1E1D1A", "Noto Sans CJK SC") ||
      !replace_shape_text_(xml, "LAYOUT_CODE", "GOTEPAD", 675, false, "B7B2A9",
                           "Noto Sans CJK SC", "r") ||
      !replace_shape_text_(xml, "FOOTER_TEXT", footer_(metadata), 675, false,
                           "B7B2A9", "Noto Sans CJK SC") ||
      !replace_shape_text_(xml, "PAGE_NUMBER", std::to_string(page_number), 750,
                           false, "77736B", "Noto Sans CJK SC", "r") ||
      !replace_shape_text_(xml, "FIGURE_CAPTION",
                           "第" + std::to_string(page.figure_index) + "图", 900,
                           true, "1E1D1A", "Noto Sans CJK SC", "ctr") ||
      !replace_shape_text_(xml, "NODE_TITLE", page_title_(page), 2025, true,
                           "1E1D1A", "Noto Serif CJK SC") ||
      !replace_shape_text_(xml, "COMMENT", page.comment,
                           comment_font_size_(page.comment), false, "1E1D1A",
                           "Noto Serif CJK SC") ||
      !replace_shape_text_(xml, "BOARD_NOTE", diagram.repeated_numbers, 1000,
                           false, "77736B", "Noto Serif CJK SC") ||
      !replace_board_shape_(xml)) {
    return {};
  }
  return xml;
}

std::string content_types_(size_t slide_count,
                           GoNotes::PptxImageFormat image_format) {
  std::ostringstream xml{};
  xml << "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
         "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/"
         "content-types\">"
         "<Default Extension=\"xml\" ContentType=\"application/vnd."
         "openxmlformats-package.core-properties+xml\"/>"
         "<Default Extension=\"rels\" ContentType=\"application/vnd."
         "openxmlformats-package.relationships+xml\"/>"
         "<Default Extension=\""
      << (image_format == GoNotes::PptxImageFormat::Png ? "png" : "svg")
      << "\" ContentType=\""
      << (image_format == GoNotes::PptxImageFormat::Png ? "image/png"
                                                        : "image/svg+xml")
      << "\"/>"
         "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/"
         "vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
         "<Override PartName=\"/ppt/presentation.xml\" ContentType=\""
         "application/vnd.openxmlformats-officedocument.presentationml."
         "presentation.main+xml\"/>"
         "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\""
         "application/vnd.openxmlformats-officedocument.theme+xml\"/>"
         "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" "
         "ContentType=\"application/vnd.openxmlformats-officedocument."
         "presentationml.slideMaster+xml\"/>"
         "<Override PartName=\"/ppt/slideMasters/theme/theme2.xml\" "
         "ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml"
         "\"/><Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" "
         "ContentType=\"application/vnd.openxmlformats-officedocument."
         "presentationml.slideLayout+xml\"/>"
         "<Override PartName=\"/ppt/presProps.xml\" ContentType=\"application/"
         "vnd.openxmlformats-officedocument.presentationml.presProps+xml\"/>"
         "<Override PartName=\"/ppt/tableStyles.xml\" ContentType=\""
         "application/vnd.openxmlformats-officedocument.presentationml."
         "tableStyles+xml\"/>";
  for (size_t index = 1; index <= slide_count; ++index)
    xml << "<Override PartName=\"/ppt/slides/slide" << index
        << ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument."
           "presentationml.slide+xml\"/>";
  xml << "</Types>";
  return xml.str();
}

std::string presentation_xml_(size_t slide_count) {
  std::ostringstream xml{};
  xml << "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
         "<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/"
         "presentationml/2006/main\"><p:sldMasterIdLst>"
         "<p:sldMasterId id=\"2147483648\" r:id=\"rIdMaster\" "
         "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/"
         "relationships\"/></p:sldMasterIdLst><p:sldIdLst>";
  for (size_t index = 1; index <= slide_count; ++index)
    xml << "<p:sldId id=\"" << (255 + index) << "\" r:id=\"rIdSlide" << index
        << "\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/"
           "2006/relationships\"/>";
  xml << "</p:sldIdLst><p:sldSz cx=\"9001125\" cy=\"6334125\"/>"
         "<p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>";
  return xml.str();
}

std::string presentation_relationships_(size_t slide_count) {
  std::ostringstream xml{};
  xml << "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
         "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/"
         "2006/relationships\">"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/theme\" Target=\"/ppt/theme/"
         "theme1.xml\" Id=\"rIdTheme\"/>"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/slideMaster\" Target=\"/ppt/"
         "slideMasters/slideMaster1.xml\" Id=\"rIdMaster\"/>"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/presProps\" Target=\"/ppt/"
         "presProps.xml\" Id=\"rIdPresProps\"/>"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/tableStyles\" Target=\"/ppt/"
         "tableStyles.xml\" Id=\"rIdTableStyles\"/>";
  for (size_t index = 1; index <= slide_count; ++index)
    xml << "<Relationship Type=\"http://schemas.openxmlformats.org/"
           "officeDocument/2006/relationships/slide\" Target=\"/ppt/slides/"
           "slide"
        << index << ".xml\" Id=\"rIdSlide" << index << "\"/>";
  xml << "</Relationships>";
  return xml.str();
}

std::string slide_relationships_(size_t index,
                                 GoNotes::PptxImageFormat image_format) {
  std::ostringstream xml{};
  xml << "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
         "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/"
         "2006/relationships\">"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/slideLayout\" Target=\"/ppt/"
         "slideLayouts/slideLayout1.xml\" Id=\"rIdLayout\"/>"
         "<Relationship Type=\"http://schemas.openxmlformats.org/"
         "officeDocument/2006/relationships/image\" Target=\"/ppt/media/board"
      << index
      << (image_format == GoNotes::PptxImageFormat::Png ? ".png" : ".svg")
      << "\" Id=\"rIdBoard\"/></Relationships>";
  return xml.str();
}

bool skip_template_part_(const std::string &name) {
  return name == "[Content_Types].xml" || name == "ppt/presentation.xml" ||
         name == "ppt/_rels/presentation.xml.rels" ||
         name.rfind("ppt/slides/", 0) == 0 ||
         name.rfind("ppt/notesSlides/", 0) == 0 ||
         name.rfind("ppt/notesMasters/", 0) == 0 ||
         name.rfind("ppt/media/", 0) == 0;
}

bool read_template_(const std::vector<uint8_t> &archive_bytes,
                    std::map<std::string, std::vector<uint8_t>> &parts,
                    std::string &slide_template) {
  mz_zip_archive archive{};
  if (!mz_zip_reader_init_mem(&archive, archive_bytes.data(),
                              archive_bytes.size(), 0))
    return false;

  bool valid = true;
  const auto file_count = mz_zip_reader_get_num_files(&archive);
  for (mz_uint index = 0; index < file_count; ++index) {
    mz_zip_archive_file_stat stat{};
    if (!mz_zip_reader_file_stat(&archive, index, &stat)) {
      valid = false;
      break;
    }
    const std::string name = stat.m_filename;
    if (stat.m_is_directory)
      continue;
    size_t size = 0;
    void *data = mz_zip_reader_extract_to_heap(&archive, index, &size, 0);
    if (data == nullptr && size != 0) {
      valid = false;
      break;
    }
    std::vector<uint8_t> content(size);
    if (size != 0)
      std::memcpy(content.data(), data, size);
    mz_free(data);
    if (name == "ppt/slides/slide4.xml")
      slide_template = text_(content);
    if (!skip_template_part_(name))
      parts.emplace(name, std::move(content));
  }
  mz_zip_reader_end(&archive);
  return valid && !slide_template.empty() &&
         parts.find("ppt/slideLayouts/slideLayout1.xml") != parts.end() &&
         parts.find("ppt/slideMasters/slideMaster1.xml") != parts.end();
}

bool write_package_(const std::string &path,
                    const std::map<std::string, std::vector<uint8_t>> &parts) {
  mz_zip_archive archive{};
  if (!mz_zip_writer_init_heap(&archive, 0, 256 * 1024))
    return false;
  bool valid = true;
  for (const auto &[name, data] : parts) {
    if (!mz_zip_writer_add_mem(&archive, name.c_str(), data.data(), data.size(),
                               MZ_BEST_SPEED)) {
      valid = false;
      break;
    }
  }
  void *output = nullptr;
  size_t output_size = 0;
  if (valid)
    valid = mz_zip_writer_finalize_heap_archive(&archive, &output,
                                                &output_size) != 0;
  mz_zip_writer_end(&archive);
  if (!valid) {
    mz_free(output);
    return false;
  }
  valid = write_file_(path, output, output_size);
  mz_free(output);
  return valid;
}
} // namespace

bool GoNotes::export_pptx_file(const std::string &path,
                               const std::string &template_path,
                               std::string &error_message,
                               PptxImageFormat image_format) const {
  std::vector<uint8_t> template_data{};
  if (!read_file_(template_path, template_data)) {
    error_message = kTemplateReadMessage;
    return false;
  }
  return export_pptx_file(path, template_data, error_message, image_format);
}

bool GoNotes::export_pptx_file(const std::string &path,
                               const std::vector<uint8_t> &template_data,
                               std::string &error_message,
                               PptxImageFormat image_format) const {
  error_message.clear();
  const auto root = go_core_.record_tree();

  std::vector<ExportPage> pages{};
  size_t figure_index = 0;
  collect_pages_(*this, root, 0, figure_index, pages);
  if (pages.empty()) {
    error_message = kNoNotesMessage;
    return false;
  }

  std::map<std::string, std::vector<uint8_t>> parts{};
  std::string slide_template{};
  if (!read_template_(template_data, parts, slide_template)) {
    error_message = kTemplateInvalidMessage;
    return false;
  }

  parts["[Content_Types].xml"] =
      bytes_(content_types_(pages.size(), image_format));
  parts["ppt/presentation.xml"] = bytes_(presentation_xml_(pages.size()));
  parts["ppt/_rels/presentation.xml.rels"] =
      bytes_(presentation_relationships_(pages.size()));

  auto app_it = parts.find("docProps/app.xml");
  if (app_it != parts.end()) {
    auto app = text_(app_it->second);
    const auto slides_begin = app.find("<Slides>");
    const auto slides_end = app.find("</Slides>", slides_begin);
    if (slides_begin != std::string::npos && slides_end != std::string::npos) {
      app.replace(slides_begin,
                  slides_end + std::strlen("</Slides>") - slides_begin,
                  "<Slides>" + std::to_string(pages.size()) + "</Slides>");
      app_it->second = bytes_(std::move(app));
    }
  }

  for (size_t index = 0; index < pages.size(); ++index) {
    const auto diagram = render_board_(*this, pages[index], root);
    if (diagram.svg.empty()) {
      error_message = kTemplateInvalidMessage;
      return false;
    }
    const auto slide = build_slide_xml_(slide_template, sgf_metadata_,
                                        pages[index], diagram, index + 1);
    if (slide.empty()) {
      error_message = kTemplateInvalidMessage;
      return false;
    }
    const auto number = std::to_string(index + 1);
    parts["ppt/slides/slide" + number + ".xml"] = bytes_(slide);
    parts["ppt/slides/_rels/slide" + number + ".xml.rels"] =
        bytes_(slide_relationships_(index + 1, image_format));
    if (image_format == PptxImageFormat::Png) {
      std::vector<uint8_t> png{};
      if (!svg_to_png_(diagram.svg, png)) {
        error_message = kPptxRasterizeMessage;
        return false;
      }
      parts["ppt/media/board" + number + ".png"] = std::move(png);
    } else {
      parts["ppt/media/board" + number + ".svg"] = bytes_(diagram.svg);
    }
  }

  if (!write_package_(path, parts)) {
    error_message = kPptxWriteMessage;
    return false;
  }
  return true;
}
} // namespace nd::go
