// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT
// Vibe coding with GPT.

#include "../src/go_notes.hpp"

#include <miniz.h>

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace {
using Notes = nd::go::GoNotes;

void expect_true(bool condition, const char *message) {
  if (!condition) {
    std::cerr << message << '\n';
    assert(condition);
  }
}

std::filesystem::path find_template() {
  const std::vector<std::filesystem::path> candidates{
      "gotepad-gd/assets/publication/go_book_b5_landscape_template.pptx",
      "../gotepad-gd/assets/publication/go_book_b5_landscape_template.pptx",
      "../../gotepad-gd/assets/publication/go_book_b5_landscape_template.pptx"};
  for (const auto &candidate : candidates) {
    if (std::filesystem::exists(candidate))
      return candidate;
  }
  return {};
}

std::string zip_entry(const std::filesystem::path &path,
                      const std::string &name) {
  std::ifstream input{path, std::ios::binary};
  std::vector<unsigned char> bytes{std::istreambuf_iterator<char>{input},
                                   std::istreambuf_iterator<char>{}};
  mz_zip_archive archive{};
  if (bytes.empty() ||
      !mz_zip_reader_init_mem(&archive, bytes.data(), bytes.size(), 0))
    return {};
  const auto index = mz_zip_reader_locate_file(&archive, name.c_str(), nullptr,
                                               MZ_ZIP_FLAG_CASE_SENSITIVE);
  if (index < 0) {
    mz_zip_reader_end(&archive);
    return {};
  }
  size_t size = 0;
  void *data = mz_zip_reader_extract_to_heap(
      &archive, static_cast<mz_uint>(index), &size, 0);
  std::string result{};
  if (data != nullptr)
    result.assign(static_cast<const char *>(data), size);
  mz_free(data);
  mz_zip_reader_end(&archive);
  return result;
}

void place(Notes &notes, int color, int row, int column) {
  const auto command = "PLACESTONE," + std::to_string(color) + "," +
                       std::to_string(row) + "," + std::to_string(column) + ";";
  const auto result = notes.execute(command);
  if (result != 0)
    std::cerr << "Failed command: " << command
              << " message: " << notes.message() << '\n';
  expect_true(result == 0, "PPTX test move should succeed");
}

void append_note(Notes &notes, std::string title, std::string comment,
                 uint8_t numbering) {
  expect_true(notes.execute(std::make_unique<Notes::AppendNote>()) == 0,
              "PPTX test note should be appended");
  const auto note_index = notes.notes_at(notes.current_uid()).size() - 1;
  expect_true(notes.execute(std::make_unique<Notes::UpdateNoteText>(
                  note_index, std::move(title), std::move(comment))) == 0,
              "PPTX test note text should be updated");
  expect_true(notes.execute(std::make_unique<Notes::UpdateNoteNumbering>(
                  note_index, numbering)) == 0,
              "PPTX test numbering should be updated");
}

void test_pptx_export() {
  const auto template_path = find_template();
  expect_true(!template_path.empty(), "PPTX template should exist");

  Notes notes{5};
  place(notes, 1, 2, 2);
  place(notes, 2, 1, 2);
  place(notes, 1, 5, 5);
  append_note(notes, "前一对象节点", "这是编号锚点。", 0);

  place(notes, 2, 2, 1);
  place(notes, 1, 5, 4);
  place(notes, 2, 2, 3);
  place(notes, 1, 4, 5);
  place(notes, 2, 3, 2);
  place(notes, 2, 2, 2);

  std::string long_comment{};
  for (int index = 0; index < 130; ++index)
    long_comment += "这是一段用于验证自动续页和黑白棋盘排版的测试文字。";
  append_note(notes, "重复落子与标记", long_comment, 2);
  expect_true(
      notes.execute(std::make_unique<Notes::ReplaceSequentialMarks>(
          0, std::vector<std::pair<uint16_t, uint16_t>>{{1, 1}, {5, 1}})) == 0,
      "Sequential marks should be recorded");
  expect_true(
      notes.execute(std::make_unique<Notes::ReplaceSymbolMarks>(
          0,
          std::vector<std::tuple<uint16_t, uint16_t, std::string>>{
              {1, 5, "TR"}, {3, 3, "SQ"}, {4, 4, "CR"}, {5, 2, "MA"}})) == 0,
      "Symbol marks should be recorded");
  append_note(notes, "第二层笔记", "同一局面的第二层笔记。", 3);

  std::filesystem::create_directories(".tmp");
  const auto output = std::filesystem::path{".tmp/test_go_notes_export.pptx"};
  std::string error{};
  const bool exported = notes.export_pptx_file(output.u8string(),
                                               template_path.u8string(), error);
  if (!exported)
    std::cerr << "PPTX export error: " << error << '\n';
  expect_true(exported, "PPTX export should succeed");
  expect_true(std::filesystem::file_size(output) > 10000,
              "Exported PPTX should contain a complete package");

  const auto presentation = zip_entry(output, "ppt/presentation.xml");
  const auto slide1 = zip_entry(output, "ppt/slides/slide1.xml");
  const auto slide2 = zip_entry(output, "ppt/slides/slide2.xml");
  const auto board2 = zip_entry(output, "ppt/media/board2.svg");
  expect_true(presentation.find("rIdSlide4") != std::string::npos,
              "Long comment and multiple notes should create multiple pages");
  expect_true(slide1.find("前一对象节点") != std::string::npos,
              "The first object title should be exported");
  expect_true(slide2.find("重复落子与标记") != std::string::npos,
              "The second object title should be exported");
  expect_true(slide2.find("1=9") != std::string::npos,
              "Repeated move positions should be explained below the board");
  expect_true(board2.find("<path") != std::string::npos &&
                  board2.find(">A</text>") != std::string::npos,
              "Vector symbols and sequential marks should be rendered");
}

void test_leaf_nodes_are_exported_without_notes() {
  const auto template_path = find_template();
  expect_true(!template_path.empty(), "PPTX template should exist");

  Notes notes{5};
  place(notes, 1, 3, 3);
  const auto branch_uid = notes.current_uid();
  append_note(notes, "分支起点", "这个节点有笔记。", 3);

  place(notes, 2, 2, 2);
  expect_true(
      notes.execute(std::make_unique<Notes::RoamingCommand>(branch_uid)) == 0,
      "PPTX test should roam to the branch point");
  place(notes, 2, 4, 4);

  const auto output =
      std::filesystem::path{".tmp/test_go_notes_leaf_export.pptx"};
  std::string error{};
  const bool exported = notes.export_pptx_file(output.u8string(),
                                               template_path.u8string(), error);
  if (!exported)
    std::cerr << "PPTX leaf export error: " << error << '\n';
  expect_true(exported, "PPTX leaf export should succeed");

  const auto presentation = zip_entry(output, "ppt/presentation.xml");
  const auto slide2 = zip_entry(output, "ppt/slides/slide2.xml");
  const auto slide3 = zip_entry(output, "ppt/slides/slide3.xml");
  expect_true(presentation.find("rIdSlide3") != std::string::npos &&
                  presentation.find("rIdSlide4") == std::string::npos,
              "One noted branch point and two unnoted leaves should export");
  expect_true(slide2.find("第2图") != std::string::npos &&
                  slide3.find("第3图") != std::string::npos,
              "Unnoted leaf pages should use generated figure titles");
}

void test_png_board_images() {
  const auto template_path = find_template();
  expect_true(!template_path.empty(), "PPTX template should exist");

  Notes notes{5};
  place(notes, 1, 3, 3);
  append_note(notes, "PNG棋盘", "验证兼容图片导出。", 3);

  const auto output =
      std::filesystem::path{".tmp/test_go_notes_png_export.pptx"};
  std::string error{};
  const bool exported = notes.export_pptx_file(
      output.u8string(), template_path.u8string(), error,
      Notes::PptxImageFormat::Png);
  if (!exported)
    std::cerr << "PPTX PNG export error: " << error << '\n';
  expect_true(exported, "PPTX PNG export should succeed");

  const auto content_types = zip_entry(output, "[Content_Types].xml");
  const auto relationships =
      zip_entry(output, "ppt/slides/_rels/slide1.xml.rels");
  const auto board = zip_entry(output, "ppt/media/board1.png");
  const std::string png_signature{"\x89PNG\r\n\x1a\n", 8};
  expect_true(content_types.find("image/png") != std::string::npos,
              "PPTX should declare PNG board image content");
  expect_true(relationships.find("board1.png") != std::string::npos,
              "Slide should reference the PNG board image");
  expect_true(board.size() > 24 && board.compare(0, 8, png_signature) == 0,
              "Board image should be a valid PNG stream");
  const auto dimension = [](const std::string &png, size_t offset) {
    return (static_cast<uint32_t>(static_cast<uint8_t>(png[offset])) << 24U) |
           (static_cast<uint32_t>(static_cast<uint8_t>(png[offset + 1]))
            << 16U) |
           (static_cast<uint32_t>(static_cast<uint8_t>(png[offset + 2]))
            << 8U) |
           static_cast<uint32_t>(static_cast<uint8_t>(png[offset + 3]));
  };
  expect_true(dimension(board, 16) == 1600 && dimension(board, 20) == 1600,
              "PNG board image should use the print resolution");
}
} // namespace

int main() {
  test_pptx_export();
  test_leaf_nodes_are_exported_without_notes();
  test_png_board_images();
  std::cout << "PPTX export tests passed.\n";
  return 0;
}
