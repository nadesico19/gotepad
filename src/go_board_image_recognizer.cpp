#include "go_board_image_recognizer.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#ifdef GOTEPAD_HAS_OPENCV
#include <opencv2/core.hpp>
#include <opencv2/core/utils/logger.hpp>
#include <opencv2/imgproc.hpp>
#endif

namespace nd::go::gdext {
namespace {

constexpr int kMaximumWorkingDimension = 1800;

godot::Dictionary error_result_(const char *message) {
  godot::Dictionary result{};
  result["ok"] = false;
  result["message"] = message;
  return result;
}

#ifdef GOTEPAD_HAS_OPENCV
std::array<cv::Point2f, 4>
order_corners_(const std::vector<cv::Point2f> &points) {
  std::array<cv::Point2f, 4> result{};
  auto minimum_sum = std::numeric_limits<float>::max();
  auto maximum_sum = std::numeric_limits<float>::lowest();
  auto minimum_difference = std::numeric_limits<float>::max();
  auto maximum_difference = std::numeric_limits<float>::lowest();
  for (const auto &point : points) {
    const auto sum = point.x + point.y;
    const auto difference = point.x - point.y;
    if (sum < minimum_sum) {
      minimum_sum = sum;
      result[0] = point;
    }
    if (difference > maximum_difference) {
      maximum_difference = difference;
      result[1] = point;
    }
    if (sum > maximum_sum) {
      maximum_sum = sum;
      result[2] = point;
    }
    if (difference < minimum_difference) {
      minimum_difference = difference;
      result[3] = point;
    }
  }
  return result;
}

std::array<cv::Point2f, 4> default_grid_corners_(const cv::Size size,
                                                  const int board_size) {
  const auto short_side = static_cast<float>(std::min(size.width, size.height));
  const auto margin = std::max(4.0F, short_side / (board_size + 1.0F));
  return {{{margin, margin},
           {static_cast<float>(size.width - 1) - margin, margin},
           {static_cast<float>(size.width - 1) - margin,
            static_cast<float>(size.height - 1) - margin},
           {margin, static_cast<float>(size.height - 1) - margin}}};
}

struct AxisLineCandidate {
  float position{};
  float slope{};
  float length{};
};

struct AxisSequence {
  float first{};
  float last{};
  float first_slope{};
  float last_slope{};
};

std::optional<AxisSequence>
find_regular_axis_sequence_(const std::vector<AxisLineCandidate> &candidates,
                            const int coordinate_extent,
                            const int spacing_reference,
                            const int board_size) {
  if (candidates.size() < 5)
    return std::nullopt;
  const auto minimum_spacing =
      static_cast<float>(spacing_reference) /
      static_cast<float>(board_size + 12);
  const auto maximum_spacing =
      static_cast<float>(spacing_reference) /
      static_cast<float>(board_size - 4);
  float best_score = std::numeric_limits<float>::lowest();
  float best_first = 0.0F;
  float best_spacing = 0.0F;
  int best_support = 0;
  for (auto spacing = minimum_spacing; spacing <= maximum_spacing;
       spacing += 0.25F) {
    const auto maximum_first =
        static_cast<float>(coordinate_extent - 1) -
        spacing * (board_size - 1);
    for (auto first = 0.0F; first <= maximum_first; first += 0.5F) {
      const auto tolerance = std::max(2.5F, spacing * 0.12F);
      float score = 0.0F;
      int support = 0;
      for (int index = 0; index < board_size; ++index) {
        const auto expected = first + spacing * index;
        float nearest_distance = tolerance;
        float nearest_length = 0.0F;
        float best_candidate_quality = 0.0F;
        for (const auto &candidate : candidates) {
          const auto distance = std::abs(candidate.position - expected);
          if (distance > tolerance)
            continue;
          const auto quality =
              (1.0F - distance / tolerance) * 2.0F +
              std::min(candidate.length / spacing_reference, 1.0F) * 6.0F;
          if (quality > best_candidate_quality) {
            best_candidate_quality = quality;
            nearest_distance = distance;
            nearest_length = candidate.length;
          }
        }
        if (nearest_length <= 0.0F)
          continue;
        ++support;
        score += 8.0F - nearest_distance / tolerance * 2.0F +
                 std::min(nearest_length / spacing_reference, 1.0F) * 8.0F;
      }
      const auto expected_spacing =
          static_cast<float>(spacing_reference) /
          static_cast<float>(board_size + 2);
      score -= std::abs(spacing - expected_spacing) * 0.35F;
      if (support >= std::max(6, board_size / 3) && score > best_score) {
        best_support = support;
        best_score = score;
        best_first = first;
        best_spacing = spacing;
      }
    }
  }
  if (best_support < std::max(6, board_size / 3))
    return std::nullopt;

  const auto tolerance = std::max(3.0F, best_spacing * 0.14F);
  const auto slope_at = [&candidates, tolerance](const float position) {
    float weighted_slope = 0.0F;
    float total_length = 0.0F;
    for (const auto &candidate : candidates) {
      if (std::abs(candidate.position - position) > tolerance)
        continue;
      weighted_slope += candidate.slope * candidate.length;
      total_length += candidate.length;
    }
    return total_length > 0.0F ? weighted_slope / total_length : 0.0F;
  };
  const auto last =
      best_first + best_spacing * static_cast<float>(board_size - 1);
  return AxisSequence{
      best_first,
      last,
      slope_at(best_first),
      slope_at(last),
  };
}

cv::Point2f intersect_axis_lines_(const float horizontal_position,
                                  const float horizontal_slope,
                                  const float vertical_position,
                                  const float vertical_slope,
                                  const cv::Size size) {
  const auto center_x = static_cast<float>(size.width - 1) * 0.5F;
  const auto center_y = static_cast<float>(size.height - 1) * 0.5F;
  const auto vertical_constant =
      vertical_position - vertical_slope * center_y;
  const auto horizontal_constant =
      horizontal_position - horizontal_slope * center_x;
  const auto denominator = 1.0F - vertical_slope * horizontal_slope;
  const auto x = (vertical_constant +
                  vertical_slope * horizontal_constant) /
                 denominator;
  return {x, horizontal_slope * x + horizontal_constant};
}

std::optional<std::array<cv::Point2f, 4>>
detect_regular_grid_(const cv::Mat &edges, const int board_size) {
  std::vector<cv::Vec4i> lines{};
  const auto short_side = std::min(edges.cols, edges.rows);
  cv::HoughLinesP(edges, lines, 1.0, CV_PI / 360.0, 45,
                  short_side * 0.16, short_side * 0.055);
  std::vector<AxisLineCandidate> horizontal_candidates{};
  std::vector<AxisLineCandidate> vertical_candidates{};
  const auto center_x = static_cast<float>(edges.cols - 1) * 0.5F;
  const auto center_y = static_cast<float>(edges.rows - 1) * 0.5F;
  for (const auto &line : lines) {
    const auto dx = static_cast<float>(line[2] - line[0]);
    const auto dy = static_cast<float>(line[3] - line[1]);
    const auto length = std::hypot(dx, dy);
    if (std::abs(dx) > std::abs(dy) * 3.0F) {
      const auto slope = dy / dx;
      const auto position =
          static_cast<float>(line[1]) + slope * (center_x - line[0]);
      horizontal_candidates.push_back({position, slope, length});
    } else if (std::abs(dy) > std::abs(dx) * 3.0F) {
      const auto slope = dx / dy;
      const auto position =
          static_cast<float>(line[0]) + slope * (center_y - line[1]);
      vertical_candidates.push_back({position, slope, length});
    }
  }
  const auto horizontal = find_regular_axis_sequence_(
      horizontal_candidates, edges.rows, short_side, board_size);
  const auto vertical = find_regular_axis_sequence_(
      vertical_candidates, edges.cols, short_side, board_size);
  if (!horizontal || !vertical)
    return std::nullopt;
  return std::array<cv::Point2f, 4>{
      intersect_axis_lines_(horizontal->first, horizontal->first_slope,
                            vertical->first, vertical->first_slope,
                            edges.size()),
      intersect_axis_lines_(horizontal->first, horizontal->first_slope,
                            vertical->last, vertical->last_slope,
                            edges.size()),
      intersect_axis_lines_(horizontal->last, horizontal->last_slope,
                            vertical->last, vertical->last_slope,
                            edges.size()),
      intersect_axis_lines_(horizontal->last, horizontal->last_slope,
                            vertical->first, vertical->first_slope,
                            edges.size()),
  };
}

std::optional<cv::Mat>
fit_homography_(const std::vector<cv::Point2f> &grid_points,
                const std::vector<cv::Point2f> &image_points) {
  if (grid_points.size() != image_points.size() || grid_points.size() < 4)
    return std::nullopt;
  cv::Mat matrix(static_cast<int>(grid_points.size() * 2), 8, CV_64F);
  cv::Mat values(static_cast<int>(grid_points.size() * 2), 1, CV_64F);
  for (size_t index = 0; index < grid_points.size(); ++index) {
    const auto x = static_cast<double>(grid_points[index].x);
    const auto y = static_cast<double>(grid_points[index].y);
    const auto u = static_cast<double>(image_points[index].x);
    const auto v = static_cast<double>(image_points[index].y);
    auto *first = matrix.ptr<double>(static_cast<int>(index * 2));
    auto *second = matrix.ptr<double>(static_cast<int>(index * 2 + 1));
    first[0] = x;
    first[1] = y;
    first[2] = 1.0;
    first[3] = 0.0;
    first[4] = 0.0;
    first[5] = 0.0;
    first[6] = -u * x;
    first[7] = -u * y;
    second[0] = 0.0;
    second[1] = 0.0;
    second[2] = 0.0;
    second[3] = x;
    second[4] = y;
    second[5] = 1.0;
    second[6] = -v * x;
    second[7] = -v * y;
    values.at<double>(static_cast<int>(index * 2)) = u;
    values.at<double>(static_cast<int>(index * 2 + 1)) = v;
  }
  cv::Mat solution{};
  if (!cv::solve(matrix, values, solution, cv::DECOMP_SVD))
    return std::nullopt;
  cv::Mat homography = (cv::Mat_<double>(3, 3) <<
      solution.at<double>(0), solution.at<double>(1), solution.at<double>(2),
      solution.at<double>(3), solution.at<double>(4), solution.at<double>(5),
      solution.at<double>(6), solution.at<double>(7), 1.0);
  return homography;
}

cv::Point2f project_grid_point_(const cv::Mat &homography,
                                const cv::Point2f point) {
  const auto denominator = homography.at<double>(2, 0) * point.x +
                           homography.at<double>(2, 1) * point.y +
                           homography.at<double>(2, 2);
  return {
      static_cast<float>((homography.at<double>(0, 0) * point.x +
                          homography.at<double>(0, 1) * point.y +
                          homography.at<double>(0, 2)) /
                         denominator),
      static_cast<float>((homography.at<double>(1, 0) * point.x +
                          homography.at<double>(1, 1) * point.y +
                          homography.at<double>(1, 2)) /
                         denominator),
  };
}

std::optional<std::array<cv::Point2f, 4>>
detect_stone_center_grid_(const cv::Mat &gray, const int board_size) {
  cv::Mat smoothed{};
  cv::medianBlur(gray, smoothed, 5);
  const auto short_side = std::min(gray.cols, gray.rows);
  const auto expected_spacing =
      static_cast<float>(short_side) / static_cast<float>(board_size + 2);
  std::vector<cv::Vec3f> circles{};
  cv::HoughCircles(smoothed, circles, cv::HOUGH_GRADIENT, 1.2,
                   expected_spacing * 0.62, 110.0, 19.0,
                   static_cast<int>(expected_spacing * 0.28),
                   static_cast<int>(expected_spacing * 0.64));
  if (circles.size() < static_cast<size_t>(board_size))
    return std::nullopt;

  std::vector<AxisLineCandidate> horizontal_candidates{};
  std::vector<AxisLineCandidate> vertical_candidates{};
  horizontal_candidates.reserve(circles.size());
  vertical_candidates.reserve(circles.size());
  const auto evidence_length = static_cast<float>(short_side) * 0.45F;
  for (const auto &circle : circles) {
    horizontal_candidates.push_back({circle[1], 0.0F, evidence_length});
    vertical_candidates.push_back({circle[0], 0.0F, evidence_length});
  }
  const auto horizontal = find_regular_axis_sequence_(
      horizontal_candidates, gray.rows, short_side, board_size);
  const auto vertical = find_regular_axis_sequence_(
      vertical_candidates, gray.cols, short_side, board_size);
  if (!horizontal || !vertical)
    return std::nullopt;
  const auto horizontal_spacing =
      (horizontal->last - horizontal->first) / (board_size - 1.0F);
  const auto vertical_spacing =
      (vertical->last - vertical->first) / (board_size - 1.0F);
  std::vector<cv::Point2f> grid_points{};
  std::vector<cv::Point2f> image_points{};
  for (const auto &circle : circles) {
    const auto column = static_cast<int>(std::lround(
        (circle[0] - vertical->first) / vertical_spacing));
    const auto row = static_cast<int>(std::lround(
        (circle[1] - horizontal->first) / horizontal_spacing));
    if (column < 0 || row < 0 || column >= board_size || row >= board_size)
      continue;
    const auto expected_x = vertical->first + column * vertical_spacing;
    const auto expected_y = horizontal->first + row * horizontal_spacing;
    if (std::abs(circle[0] - expected_x) > vertical_spacing * 0.38F ||
        std::abs(circle[1] - expected_y) > horizontal_spacing * 0.38F)
      continue;
    grid_points.emplace_back(static_cast<float>(column),
                             static_cast<float>(row));
    image_points.emplace_back(circle[0], circle[1]);
  }
  auto homography = fit_homography_(grid_points, image_points);
  if (!homography)
    return std::nullopt;

  const auto match_distance =
      std::max(horizontal_spacing, vertical_spacing) * 0.48F;
  for (int iteration = 0; iteration < 3; ++iteration) {
    std::vector<float> best_distances(
        static_cast<size_t>(board_size * board_size),
        std::numeric_limits<float>::max());
    std::vector<cv::Point2f> best_images(
        static_cast<size_t>(board_size * board_size));
    for (const auto &circle : circles) {
      float nearest_distance = match_distance;
      int nearest_index = -1;
      for (int row = 0; row < board_size; ++row) {
        for (int column = 0; column < board_size; ++column) {
          const auto projected = project_grid_point_(
              *homography, {static_cast<float>(column),
                            static_cast<float>(row)});
          const auto distance =
              std::hypot(projected.x - circle[0], projected.y - circle[1]);
          if (distance >= nearest_distance)
            continue;
          nearest_distance = distance;
          nearest_index = row * board_size + column;
        }
      }
      if (nearest_index < 0 ||
          nearest_distance >= best_distances[static_cast<size_t>(nearest_index)])
        continue;
      best_distances[static_cast<size_t>(nearest_index)] = nearest_distance;
      best_images[static_cast<size_t>(nearest_index)] =
          {circle[0], circle[1]};
    }
    grid_points.clear();
    image_points.clear();
    for (int index = 0; index < board_size * board_size; ++index) {
      if (best_distances[static_cast<size_t>(index)] >= match_distance)
        continue;
      grid_points.emplace_back(static_cast<float>(index % board_size),
                               static_cast<float>(index / board_size));
      image_points.push_back(best_images[static_cast<size_t>(index)]);
    }
    const auto refined = fit_homography_(grid_points, image_points);
    if (!refined)
      break;
    homography = refined;
  }
  const auto last = static_cast<float>(board_size - 1);
  return std::array<cv::Point2f, 4>{
      project_grid_point_(*homography, {0.0F, 0.0F}),
      project_grid_point_(*homography, {last, 0.0F}),
      project_grid_point_(*homography, {last, last}),
      project_grid_point_(*homography, {0.0F, last}),
  };
}

std::optional<std::array<cv::Point2f, 4>> refine_grid_from_nearby_lines_(
    const cv::Mat &edges, const std::array<cv::Point2f, 4> &initial,
    const int board_size) {
  std::vector<cv::Vec4i> lines{};
  const auto short_side = std::min(edges.cols, edges.rows);
  cv::HoughLinesP(edges, lines, 1.0, CV_PI / 360.0, 34,
                  short_side * 0.09, short_side * 0.075);
  std::vector<AxisLineCandidate> horizontal_candidates{};
  std::vector<AxisLineCandidate> vertical_candidates{};
  const auto center_x = static_cast<float>(edges.cols - 1) * 0.5F;
  const auto center_y = static_cast<float>(edges.rows - 1) * 0.5F;
  for (const auto &line : lines) {
    const auto dx = static_cast<float>(line[2] - line[0]);
    const auto dy = static_cast<float>(line[3] - line[1]);
    const auto length = std::hypot(dx, dy);
    if (std::abs(dx) > std::abs(dy) * 3.0F) {
      const auto slope = dy / dx;
      horizontal_candidates.push_back(
          {line[1] + slope * (center_x - line[0]), slope, length});
    } else if (std::abs(dy) > std::abs(dx) * 3.0F) {
      const auto slope = dx / dy;
      vertical_candidates.push_back(
          {line[0] + slope * (center_y - line[1]), slope, length});
    }
  }
  const auto horizontal_position = [center_x](const cv::Point2f first,
                                               const cv::Point2f second) {
    if (std::abs(second.x - first.x) < 1.0F)
      return (first.y + second.y) * 0.5F;
    const auto slope = (second.y - first.y) / (second.x - first.x);
    return first.y + slope * (center_x - first.x);
  };
  const auto vertical_position = [center_y](const cv::Point2f first,
                                             const cv::Point2f second) {
    if (std::abs(second.y - first.y) < 1.0F)
      return (first.x + second.x) * 0.5F;
    const auto slope = (second.x - first.x) / (second.y - first.y);
    return first.x + slope * (center_y - first.y);
  };
  const auto expected_top = horizontal_position(initial[0], initial[1]);
  const auto expected_bottom = horizontal_position(initial[3], initial[2]);
  const auto expected_left = vertical_position(initial[0], initial[3]);
  const auto expected_right = vertical_position(initial[1], initial[2]);
  const auto horizontal_spacing =
      std::abs(expected_bottom - expected_top) / (board_size - 1.0F);
  const auto vertical_spacing =
      std::abs(expected_right - expected_left) / (board_size - 1.0F);
  const auto select = [short_side](
                          const std::vector<AxisLineCandidate> &candidates,
                          const float expected, const float expected_slope,
                          const float spacing)
      -> std::optional<AxisLineCandidate> {
    auto best_quality = std::numeric_limits<float>::lowest();
    std::optional<AxisLineCandidate> best{};
    for (const auto &candidate : candidates) {
      const auto distance = std::abs(candidate.position - expected);
      const auto slope_difference =
          std::abs(candidate.slope - expected_slope);
      if (distance > spacing * 1.65F || slope_difference > 0.18F)
        continue;
      const auto quality = candidate.length / short_side * 12.0F -
                           distance / std::max(spacing, 1.0F) * 1.2F -
                           slope_difference * 8.0F;
      if (quality <= best_quality)
        continue;
      best_quality = quality;
      best = candidate;
    }
    return best;
  };
  const auto top_slope =
      (initial[1].y - initial[0].y) /
      std::max(std::abs(initial[1].x - initial[0].x), 1.0F);
  const auto bottom_slope =
      (initial[2].y - initial[3].y) /
      std::max(std::abs(initial[2].x - initial[3].x), 1.0F);
  const auto left_slope =
      (initial[3].x - initial[0].x) /
      std::max(std::abs(initial[3].y - initial[0].y), 1.0F);
  const auto right_slope =
      (initial[2].x - initial[1].x) /
      std::max(std::abs(initial[2].y - initial[1].y), 1.0F);
  const auto top = select(horizontal_candidates, expected_top, top_slope,
                          horizontal_spacing);
  const auto bottom = select(horizontal_candidates, expected_bottom,
                             bottom_slope,
                             horizontal_spacing);
  const auto left = select(vertical_candidates, expected_left, left_slope,
                           vertical_spacing);
  const auto right = select(vertical_candidates, expected_right, right_slope,
                            vertical_spacing);
  if (!top || !bottom || !left || !right)
    return std::nullopt;
  if (bottom->position - top->position < horizontal_spacing * 15.0F ||
      right->position - left->position < vertical_spacing * 15.0F)
    return std::nullopt;
  return std::array<cv::Point2f, 4>{
      intersect_axis_lines_(top->position, top->slope, left->position,
                            left->slope, edges.size()),
      intersect_axis_lines_(top->position, top->slope, right->position,
                            right->slope, edges.size()),
      intersect_axis_lines_(bottom->position, bottom->slope, right->position,
                            right->slope, edges.size()),
      intersect_axis_lines_(bottom->position, bottom->slope, left->position,
                            left->slope, edges.size()),
  };
}

std::array<cv::Point2f, 4>
inset_corners_(const std::array<cv::Point2f, 4> &corners,
               const float inset) {
  const auto top_left = corners[0];
  const auto top_right = corners[1];
  const auto bottom_right = corners[2];
  const auto bottom_left = corners[3];
  return {{
      top_left + (top_right - top_left) * inset +
          (bottom_left - top_left) * inset,
      top_right + (top_left - top_right) * inset +
          (bottom_right - top_right) * inset,
      bottom_right + (bottom_left - bottom_right) * inset +
          (top_right - bottom_right) * inset,
      bottom_left + (bottom_right - bottom_left) * inset +
          (top_left - bottom_left) * inset,
  }};
}

void append_one_cell_expansions_(
    const std::array<cv::Point2f, 4> &corners, const int board_size,
    std::vector<std::array<cv::Point2f, 4>> &candidates) {
  const auto divisor = static_cast<float>(board_size - 1);
  auto top = corners;
  top[0] -= (corners[3] - corners[0]) / divisor;
  top[1] -= (corners[2] - corners[1]) / divisor;
  candidates.push_back(top);
  auto right = corners;
  right[1] += (corners[1] - corners[0]) / divisor;
  right[2] += (corners[2] - corners[3]) / divisor;
  candidates.push_back(right);
  auto bottom = corners;
  bottom[2] += (corners[2] - corners[1]) / divisor;
  bottom[3] += (corners[3] - corners[0]) / divisor;
  candidates.push_back(bottom);
  auto left = corners;
  left[0] -= (corners[1] - corners[0]) / divisor;
  left[3] -= (corners[2] - corners[3]) / divisor;
  candidates.push_back(left);
}

float bilinear_luma_(const cv::Mat &gray, float x, float y);
float median_(std::vector<float> values);

float board_margin_quality_(const cv::Mat &gray,
                            const std::array<cv::Point2f, 4> &corners,
                            const int board_size) {
  const auto center =
      (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25F;
  float quality = 0.0F;
  for (int edge_index = 0; edge_index < 4; ++edge_index) {
    const auto first = corners[static_cast<size_t>(edge_index)];
    const auto second = corners[static_cast<size_t>((edge_index + 1) % 4)];
    const auto edge_middle = (first + second) * 0.5F;
    auto inward = center - edge_middle;
    const auto inward_length = cv::norm(inward);
    if (inward_length < 1.0)
      continue;
    inward *= 1.0F / static_cast<float>(inward_length);
    const auto opposite_middle =
        (corners[static_cast<size_t>((edge_index + 2) % 4)] +
         corners[static_cast<size_t>((edge_index + 3) % 4)]) *
        0.5F;
    const auto spacing =
        cv::norm(opposite_middle - edge_middle) / (board_size - 1.0F);
    std::vector<float> differences{};
    differences.reserve(11);
    for (int sample_index = 1; sample_index <= 11; ++sample_index) {
      const auto amount = static_cast<float>(sample_index) / 12.0F;
      const auto edge_point = first + (second - first) * amount;
      const auto inside = bilinear_luma_(
          gray, edge_point.x + inward.x * spacing * 0.55F,
          edge_point.y + inward.y * spacing * 0.55F);
      const auto outside = bilinear_luma_(
          gray, edge_point.x - inward.x * spacing * 0.55F,
          edge_point.y - inward.y * spacing * 0.55F);
      differences.push_back(std::abs(inside - outside));
    }
    const auto edge_difference = median_(differences);
    quality += std::clamp(1.0F - edge_difference / 68.0F, 0.0F, 1.0F);
  }
  return quality * 0.25F;
}

float grid_periodicity_score_(const cv::Mat &gray,
                              const std::array<cv::Point2f, 4> &corners,
                              const int board_size) {
  std::vector<cv::Point2f> polygon(corners.begin(), corners.end());
  const auto area = std::abs(cv::contourArea(polygon));
  if (area < gray.total() * 0.08 || area > gray.total() * 1.15)
    return std::numeric_limits<float>::lowest();
  for (const auto &corner : corners) {
    if (corner.x < -gray.cols * 0.12F || corner.y < -gray.rows * 0.12F ||
        corner.x > gray.cols * 1.12F || corner.y > gray.rows * 1.12F)
      return std::numeric_limits<float>::lowest();
  }

  // 盘面经过透视投影后，对边长度可以不同，但不应出现只有某一条边
  // 突然大幅缩短的扭曲四边形。此约束用于过滤把棋子阴影或盘框局部
  // 误当成最外盘线的候选，同时仍给斜拍棋盘保留足够的透视余量。
  const auto top_length = cv::norm(corners[1] - corners[0]);
  const auto right_length = cv::norm(corners[2] - corners[1]);
  const auto bottom_length = cv::norm(corners[2] - corners[3]);
  const auto left_length = cv::norm(corners[3] - corners[0]);
  const auto opposite_ratio = [](const double first, const double second) {
    return static_cast<float>(std::min(first, second) /
                              std::max(first, second));
  };
  const auto horizontal_ratio = opposite_ratio(top_length, bottom_length);
  const auto vertical_ratio = opposite_ratio(left_length, right_length);
  if (horizontal_ratio < 0.68F || vertical_ratio < 0.82F)
    return std::numeric_limits<float>::lowest();

  constexpr int kScoreSize = 760;
  constexpr float kScoreMargin = 28.0F;
  const std::array<cv::Point2f, 4> destination{{
      {kScoreMargin, kScoreMargin},
      {kScoreSize - kScoreMargin, kScoreMargin},
      {kScoreSize - kScoreMargin, kScoreSize - kScoreMargin},
      {kScoreMargin, kScoreSize - kScoreMargin},
  }};
  const auto transform =
      cv::getPerspectiveTransform(corners.data(), destination.data());
  cv::Mat rectified{};
  cv::warpPerspective(gray, rectified, transform,
                      cv::Size(kScoreSize, kScoreSize), cv::INTER_LINEAR,
                      cv::BORDER_REPLICATE);
  const auto spacing =
      (kScoreSize - kScoreMargin * 2.0F) / (board_size - 1.0F);
  const auto side_offset = std::max(3, static_cast<int>(spacing * 0.13F));
  const auto begin = static_cast<int>(kScoreMargin + spacing * 0.35F);
  const auto end = static_cast<int>(kScoreSize - kScoreMargin -
                                    spacing * 0.35F);
  float score = 0.0F;
  int sample_count = 0;
  const auto dark_line_score = [](const float center, const float side_a,
                                  const float side_b) {
    const auto contrast = (side_a + side_b) * 0.5F - center;
    return std::clamp((contrast - 1.5F) / 18.0F, 0.0F, 1.0F);
  };
  for (int index = 0; index < board_size; ++index) {
    const auto position = static_cast<int>(std::lround(
        kScoreMargin + static_cast<float>(index) * spacing));
    for (int coordinate = begin; coordinate <= end; coordinate += 3) {
      const auto horizontal_center = std::min(
          {rectified.at<uint8_t>(position - 1, coordinate),
           rectified.at<uint8_t>(position, coordinate),
           rectified.at<uint8_t>(position + 1, coordinate)});
      score += dark_line_score(
          horizontal_center,
          rectified.at<uint8_t>(position - side_offset, coordinate),
          rectified.at<uint8_t>(position + side_offset, coordinate));
      const auto vertical_center = std::min(
          {rectified.at<uint8_t>(coordinate, position - 1),
           rectified.at<uint8_t>(coordinate, position),
           rectified.at<uint8_t>(coordinate, position + 1)});
      score += dark_line_score(
          vertical_center,
          rectified.at<uint8_t>(coordinate, position - side_offset),
          rectified.at<uint8_t>(coordinate, position + side_offset));
      sample_count += 2;
    }
  }
  if (sample_count == 0)
    return std::numeric_limits<float>::lowest();
  float stone_alignment = 0.0F;
  int stone_sample_count = 0;
  constexpr int kCircleSamples = 12;
  for (int row = 0; row < board_size; ++row) {
    for (int column = 0; column < board_size; ++column) {
      const auto center_x =
          kScoreMargin + static_cast<float>(column) * spacing;
      const auto center_y =
          kScoreMargin + static_cast<float>(row) * spacing;
      float inner_sum = 0.0F;
      float outer_sum = 0.0F;
      for (int index = 0; index < kCircleSamples; ++index) {
        const auto angle = static_cast<float>(index) *
                           static_cast<float>(CV_2PI / kCircleSamples);
        const auto cosine = std::cos(angle);
        const auto sine = std::sin(angle);
        inner_sum += bilinear_luma_(
            rectified, center_x + cosine * spacing * 0.20F,
            center_y + sine * spacing * 0.20F);
        outer_sum += bilinear_luma_(
            rectified, center_x + cosine * spacing * 0.52F,
            center_y + sine * spacing * 0.52F);
      }
      const auto disk_contrast =
          std::abs(inner_sum - outer_sum) / kCircleSamples;
      stone_alignment +=
          std::clamp((disk_contrast - 7.0F) / 42.0F, 0.0F, 1.0F);
      ++stone_sample_count;
    }
  }
  const auto line_score = score / sample_count;
  const auto stone_score =
      stone_sample_count > 0 ? stone_alignment / stone_sample_count : 0.0F;
  const auto geometry_quality =
      std::sqrt(horizontal_ratio * vertical_ratio);
  const auto margin_quality = board_margin_quality_(gray, corners, board_size);
  return (line_score * 0.58F + stone_score * 0.42F) *
         (0.82F + geometry_quality * 0.18F) *
         (0.72F + margin_quality * 0.28F);
}

void append_color_board_candidates_(
    const cv::Mat &rgba, const int board_size,
    std::vector<std::array<cv::Point2f, 4>> &candidates) {
  cv::Mat rgb{};
  cv::cvtColor(rgba, rgb, cv::COLOR_RGBA2RGB);
  cv::Mat hsv{};
  cv::cvtColor(rgb, hsv, cv::COLOR_RGB2HSV);
  cv::Mat mask{};
  // 黄色教学棋盘与常见棕色桌面的色相接近，但饱和度和亮度明显更高。
  // 使用较窄的黄色范围生成候选，避免把整张桌面当成棋盘；其他木色
  // 棋盘仍由盘线、棋子圆心和轮廓候选覆盖。
  cv::inRange(hsv, cv::Scalar(18, 125, 135),
              cv::Scalar(36, 255, 255), mask);
  const auto short_side = std::min(mask.cols, mask.rows);
  auto close_size = std::max(9, short_side / 32);
  if (close_size % 2 == 0)
    ++close_size;
  cv::morphologyEx(
      mask, mask, cv::MORPH_CLOSE,
      cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                cv::Size(close_size, close_size)));
  cv::morphologyEx(
      mask, mask, cv::MORPH_OPEN,
      cv::getStructuringElement(cv::MORPH_RECT, cv::Size(5, 5)));
  // 棋子会把黄色棋盘分割成多个互不相连的色块。不能只依赖最大连通
  // 区域，否则密集局面往往只能得到半块棋盘；先合并全部黄色像素，
  // 再由整体凸包生成一个候选四边形。
  std::vector<cv::Point> all_colored_points{};
  cv::findNonZero(mask, all_colored_points);
  if (all_colored_points.size() > rgba.total() * 0.06 &&
      all_colored_points.size() < rgba.total() * 0.75) {
    std::vector<cv::Point> all_hull{};
    cv::convexHull(all_colored_points, all_hull);
    const auto all_perimeter = cv::arcLength(all_hull, true);
    std::vector<cv::Point> all_approximate{};
    cv::approxPolyDP(all_hull, all_approximate, all_perimeter * 0.025,
                     true);
    std::vector<cv::Point2f> all_points{};
    if (all_approximate.size() == 4) {
      for (const auto &point : all_approximate)
        all_points.emplace_back(static_cast<float>(point.x),
                                static_cast<float>(point.y));
    } else {
      std::array<cv::Point2f, 4> box{};
      cv::minAreaRect(all_hull).points(box.data());
      all_points.assign(box.begin(), box.end());
    }
    const auto ordered = order_corners_(all_points);
    candidates.push_back(ordered);
    candidates.push_back(
        inset_corners_(ordered, 0.5F / static_cast<float>(board_size + 1)));
    candidates.push_back(
        inset_corners_(ordered, 1.0F / static_cast<float>(board_size + 1)));
  }
  std::vector<std::vector<cv::Point>> contours{};
  cv::findContours(mask, contours, cv::RETR_EXTERNAL,
                   cv::CHAIN_APPROX_SIMPLE);
  std::sort(contours.begin(), contours.end(),
            [](const auto &left, const auto &right) {
              return std::abs(cv::contourArea(left)) >
                     std::abs(cv::contourArea(right));
            });
  const auto minimum_area = rgba.total() * 0.08;
  for (size_t index = 0; index < std::min<size_t>(contours.size(), 8);
       ++index) {
    const auto &contour = contours[index];
    if (std::abs(cv::contourArea(contour)) < minimum_area)
      continue;
    std::vector<cv::Point> hull{};
    cv::convexHull(contour, hull);
    const auto perimeter = cv::arcLength(hull, true);
    std::vector<cv::Point> approximate{};
    cv::approxPolyDP(hull, approximate, perimeter * 0.035, true);
    std::vector<cv::Point2f> points{};
    if (approximate.size() == 4) {
      for (const auto &point : approximate)
        points.emplace_back(static_cast<float>(point.x),
                            static_cast<float>(point.y));
    } else {
      std::array<cv::Point2f, 4> box{};
      cv::minAreaRect(hull).points(box.data());
      points.assign(box.begin(), box.end());
    }
    const auto ordered = order_corners_(points);
    candidates.push_back(ordered);
    candidates.push_back(
        inset_corners_(ordered, 0.5F / static_cast<float>(board_size + 1)));
    candidates.push_back(
        inset_corners_(ordered, 1.0F / static_cast<float>(board_size + 1)));
  }
}

std::array<cv::Point2f, 4> detect_grid_corners_(const cv::Mat &gray,
                                                const cv::Mat &rgba,
                                                const int board_size) {
  cv::Mat blurred{};
  cv::GaussianBlur(gray, blurred, cv::Size(5, 5), 0.0);
  cv::Mat edges{};
  cv::Canny(blurred, edges, 45.0, 135.0);
  cv::morphologyEx(edges, edges, cv::MORPH_CLOSE,
                   cv::getStructuringElement(cv::MORPH_RECT, cv::Size(7, 7)));

  std::vector<std::array<cv::Point2f, 4>> candidates{};
  if (const auto regular_grid = detect_regular_grid_(edges, board_size))
    candidates.push_back(*regular_grid);
  if (const auto stone_grid = detect_stone_center_grid_(gray, board_size))
  {
    candidates.push_back(*stone_grid);
    append_one_cell_expansions_(*stone_grid, board_size, candidates);
    if (const auto refined =
            refine_grid_from_nearby_lines_(edges, *stone_grid, board_size)) {
      candidates.push_back(*refined);
      append_one_cell_expansions_(*refined, board_size, candidates);
    }
  }
  append_color_board_candidates_(rgba, board_size, candidates);

  std::vector<std::vector<cv::Point>> contours{};
  cv::findContours(edges, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
  const auto minimum_area = gray.total() * 0.08;
  for (const auto &contour : contours) {
    const auto perimeter = cv::arcLength(contour, true);
    std::vector<cv::Point> approximate{};
    cv::approxPolyDP(contour, approximate, perimeter * 0.02, true);
    if (approximate.size() != 4 || !cv::isContourConvex(approximate))
      continue;
    const auto area = std::abs(cv::contourArea(approximate));
    if (area < minimum_area)
      continue;
    std::vector<cv::Point2f> points{};
    points.reserve(4);
    for (const auto &point : approximate)
      points.emplace_back(static_cast<float>(point.x),
                          static_cast<float>(point.y));
    const auto ordered = order_corners_(points);
    candidates.push_back(ordered);
    candidates.push_back(
        inset_corners_(ordered, 0.5F / static_cast<float>(board_size + 1)));
    candidates.push_back(
        inset_corners_(ordered, 1.0F / static_cast<float>(board_size + 1)));
    if (candidates.size() >= 42)
      break;
  }

  candidates.push_back(default_grid_corners_(gray.size(), board_size));
  auto best = candidates.front();
  auto best_score = std::numeric_limits<float>::lowest();
  for (const auto &candidate : candidates) {
    const auto score = grid_periodicity_score_(gray, candidate, board_size);
    if (score <= best_score)
      continue;
    best = candidate;
    best_score = score;
  }
  return best;
}

float bilinear_luma_(const cv::Mat &gray, const float x, const float y) {
  const auto x0 = std::clamp(static_cast<int>(std::floor(x)), 0, gray.cols - 1);
  const auto y0 = std::clamp(static_cast<int>(std::floor(y)), 0, gray.rows - 1);
  const auto x1 = std::min(x0 + 1, gray.cols - 1);
  const auto y1 = std::min(y0 + 1, gray.rows - 1);
  const auto tx = x - std::floor(x);
  const auto ty = y - std::floor(y);
  const auto top = gray.at<uint8_t>(y0, x0) * (1.0F - tx) +
                   gray.at<uint8_t>(y0, x1) * tx;
  const auto bottom = gray.at<uint8_t>(y1, x0) * (1.0F - tx) +
                      gray.at<uint8_t>(y1, x1) * tx;
  return top * (1.0F - ty) + bottom * ty;
}

cv::Vec3f bilinear_lab_(const cv::Mat &lab, const float x, const float y) {
  const auto x_floor = std::floor(x);
  const auto y_floor = std::floor(y);
  const auto x0 = std::clamp(static_cast<int>(x_floor), 0, lab.cols - 1);
  const auto y0 = std::clamp(static_cast<int>(y_floor), 0, lab.rows - 1);
  const auto x1 = std::min(x0 + 1, lab.cols - 1);
  const auto y1 = std::min(y0 + 1, lab.rows - 1);
  const auto tx = x - x_floor;
  const auto ty = y - y_floor;
  const auto top = cv::Vec3f{lab.at<cv::Vec3b>(y0, x0)} * (1.0F - tx) +
                   cv::Vec3f{lab.at<cv::Vec3b>(y0, x1)} * tx;
  const auto bottom = cv::Vec3f{lab.at<cv::Vec3b>(y1, x0)} * (1.0F - tx) +
                      cv::Vec3f{lab.at<cv::Vec3b>(y1, x1)} * tx;
  return top * (1.0F - ty) + bottom * ty;
}

float median_(std::vector<float> values) {
  if (values.empty())
    return 128.0F;
  const auto middle = values.begin() + static_cast<std::ptrdiff_t>(values.size() / 2);
  std::nth_element(values.begin(), middle, values.end());
  return *middle;
}

float percentile_(std::vector<float> values, const float ratio) {
  if (values.empty())
    return 128.0F;
  const auto index = static_cast<size_t>(std::lround(
      static_cast<float>(values.size() - 1) *
      std::clamp(ratio, 0.0F, 1.0F)));
  const auto selected = values.begin() + static_cast<std::ptrdiff_t>(index);
  std::nth_element(values.begin(), selected, values.end());
  return *selected;
}

struct CellClassification {
  int color{};
  float confidence{};
};

CellClassification classify_cell_(const cv::Mat &gray, const cv::Mat &lab,
                                  const cv::Point2f center,
                                  const float spacing, const float board_luma,
                                  const float black_board_luma,
                                  const float board_chroma,
                                  const bool circle_support) {
  const auto inner_radius = spacing * 0.32F;
  const auto outer_radius = spacing * 0.46F;
  const auto sample_radius = static_cast<int>(std::ceil(outer_radius));
  float inner_sum = 0.0F;
  float inner_dark = 0.0F;
  float inner_a_sum = 0.0F;
  float inner_b_sum = 0.0F;
  std::vector<float> inner_luma_samples{};
  int inner_neutral_count = 0;
  std::array<int, 4> inner_quadrant_count{};
  std::array<int, 4> inner_quadrant_dark{};
  int inner_count = 0;
  for (int dy = -sample_radius; dy <= sample_radius; ++dy) {
    for (int dx = -sample_radius; dx <= sample_radius; ++dx) {
      const auto distance = std::sqrt(static_cast<float>(dx * dx + dy * dy));
      if (distance > inner_radius)
        continue;
      // 棋盘线会在空交叉点形成很暗的十字。颜色采样避开十字的窄带，
      // 只统计各象限中的圆盘区域，防止把木色交叉点识别成黑棋。
      const auto grid_line_half_width = spacing * 0.045F;
      if (std::abs(static_cast<float>(dx)) <= grid_line_half_width ||
          std::abs(static_cast<float>(dy)) <= grid_line_half_width)
        continue;
      const auto value = bilinear_luma_(gray, center.x + dx, center.y + dy);
      const auto color = bilinear_lab_(lab, center.x + dx, center.y + dy);
      const auto pixel_chroma =
          std::hypot(color[1] - 128.0F, color[2] - 128.0F);
      const auto is_dark = value < black_board_luma - 28.0F;
      const auto quadrant = static_cast<size_t>((dy >= 0 ? 2 : 0) +
                                                (dx >= 0 ? 1 : 0));
      inner_sum += value;
      inner_dark += is_dark ? 1.0F : 0.0F;
      inner_a_sum += color[1];
      inner_b_sum += color[2];
      inner_luma_samples.push_back(value);
      inner_neutral_count += pixel_chroma < 18.0F ? 1 : 0;
      ++inner_quadrant_count[quadrant];
      inner_quadrant_dark[quadrant] += is_dark ? 1 : 0;
      ++inner_count;
    }
  }
  if (inner_count == 0)
    return {};
  const auto inner_mean = inner_sum / inner_count;
  // 镜面高光会明显抬高黑棋的平均亮度，但无法同时照亮整个圆盘。
  // 取内部较暗部分的分位值，为高光黑棋保留稳定的暗度证据。
  const auto inner_dark_luma = percentile_(inner_luma_samples, 0.32F);
  const auto dark_fraction = inner_dark / inner_count;
  const auto inner_a = inner_a_sum / inner_count;
  const auto inner_b = inner_b_sum / inner_count;
  const auto inner_chroma =
      std::hypot(inner_a - 128.0F, inner_b - 128.0F);
  const auto neutral_fraction =
      static_cast<float>(inner_neutral_count) / inner_count;
  int dark_quadrant_count = 0;
  for (size_t quadrant = 0; quadrant < inner_quadrant_count.size();
       ++quadrant) {
    if (inner_quadrant_count[quadrant] == 0)
      continue;
    const auto quadrant_dark_fraction =
        static_cast<float>(inner_quadrant_dark[quadrant]) /
        inner_quadrant_count[quadrant];
    if (quadrant_dark_fraction > 0.35F)
      ++dark_quadrant_count;
  }

  int boundary_hits = 0;
  std::array<bool, 12> boundary_sectors{};
  float boundary_difference = 0.0F;
  constexpr int kAngles = 48;
  for (int index = 0; index < kAngles; ++index) {
    const auto angle = static_cast<float>(index) *
                       static_cast<float>(CV_2PI / kAngles);
    const auto cosine = std::cos(angle);
    const auto sine = std::sin(angle);
    const auto inside = bilinear_luma_(gray, center.x + cosine * inner_radius,
                                       center.y + sine * inner_radius);
    const auto outside = bilinear_luma_(gray, center.x + cosine * outer_radius,
                                        center.y + sine * outer_radius);
    const auto difference = std::abs(inside - outside);
    boundary_difference += difference;
    if (difference > 24.0F) {
      ++boundary_hits;
      boundary_sectors[static_cast<size_t>(index) *
                       boundary_sectors.size() / kAngles] = true;
    }
  }
  const auto boundary_fraction = static_cast<float>(boundary_hits) / kAngles;
  const auto boundary_mean = boundary_difference / kAngles;

  const auto black_strength = std::max(
      {(black_board_luma - inner_mean) / 72.0F,
       (dark_fraction - 0.30F) / 0.55F,
       (black_board_luma - inner_dark_luma - 18.0F) / 68.0F});
  const auto circular_strength =
      std::max(boundary_fraction, boundary_mean / 55.0F);
  // 木纹即使落入阴影，通常仍保留明显的黄褐色色度；黑白棋子则更接近
  // 中性色。相对棋盘底色计算阈值，可以兼顾不同色温下拍摄的照片。
  const auto neutral_chroma_limit = std::max(18.0F, board_chroma * 0.72F);
  const auto neutral_disk = inner_chroma < neutral_chroma_limit;
  const auto edge_limit = spacing * 1.5F;
  const auto on_board_edge = center.x < edge_limit || center.y < edge_limit ||
                             center.x > gray.cols - edge_limit ||
                             center.y > gray.rows - edge_limit;
  const auto white_brightness = (inner_mean - board_luma + 26.0F) / 52.0F;
  const auto white_strength = circular_strength * 0.70F +
                              std::clamp(white_brightness, 0.0F, 1.0F) * 0.30F;
  const auto bright_white_disk =
      inner_mean > board_luma + 28.0F && dark_fraction < 0.16F;
  const auto boundary_sector_count = static_cast<int>(std::count(
      boundary_sectors.begin(), boundary_sectors.end(), true));
  const auto distributed_boundary = boundary_sector_count >= 7;
  // 围棋软件截图中的白棋通常是高度一致的中性色圆盘，但白棋与浅色
  // 棋盘之间的亮度差较小，Hough 圆和完整圆周边界都可能只命中其中
  // 一部分。以内部中性色像素比例和相对木色色度差作为第二条证据，
  // 仍要求存在弱圆周边界，避免把普通的浅色木纹识别成白棋。
  const auto board_has_useful_chroma = board_chroma > 12.0F;
  const auto white_chroma_separation =
      board_has_useful_chroma
          ? (board_chroma - inner_chroma) / board_chroma
          : 0.0F;
  const auto rendered_white_interior =
      board_has_useful_chroma && neutral_fraction > 0.56F &&
      white_chroma_separation > 0.30F &&
      inner_mean > board_luma - 22.0F && dark_fraction < 0.34F;
  const auto regular_rendered_white_disk =
      rendered_white_interior &&
      (circle_support || boundary_mean > 9.0F ||
       (distributed_boundary && boundary_mean > 6.5F) || on_board_edge);
  const auto circle_white_interior =
      board_has_useful_chroma && circle_support &&
      white_chroma_separation > 0.35F &&
      inner_mean > board_luma - 28.0F && dark_fraction < 0.36F;
  // 黑棋表面的镜面高光可能很亮，但圆盘的大部分区域仍明显暗于棋盘。
  // 在白棋判定之前处理这种强黑棋，防止高光把黑棋误分为白棋。
  const auto strong_black_interior =
      neutral_disk && dark_quadrant_count >= 3 &&
      ((inner_mean < black_board_luma - 34.0F && dark_fraction > 0.68F) ||
       (inner_dark_luma < black_board_luma - 48.0F &&
        dark_fraction > 0.38F));
  const auto closed_black_boundary =
      boundary_sector_count >= 3 && circular_strength > 0.12F &&
      neutral_fraction > 0.60F;
  const auto strong_black_disk =
      (circle_support && neutral_disk && dark_quadrant_count >= 3 &&
       inner_mean < board_luma - 10.0F && dark_fraction > 0.42F) ||
      (strong_black_interior &&
       (!on_board_edge || circle_support || closed_black_boundary));
  if (strong_black_disk) {
    return {1, std::clamp(0.56F + black_strength * 0.42F, 0.0F, 1.0F)};
  }
  const auto white_shape = circle_support || regular_rendered_white_disk ||
                           (distributed_boundary &&
                            circular_strength > 0.27F);
  // 浅色木纹以及两颗黑子之间的亮色间隙，偶尔也会被 HoughCircles
  // 当成圆。彩色棋盘上不能仅凭圆周证据判白，还必须在圆盘内部找到
  // 亮度或中性色证据；灰度棋谱图则继续以形状为主。
  const auto white_interior_evidence =
      !board_has_useful_chroma || rendered_white_interior ||
      circle_white_interior ||
      neutral_fraction > 0.42F || inner_mean > board_luma + 7.0F;
  // 先识别白棋，避免白棋深色边缘先满足黑棋的暗像素比例条件。
  if (white_shape && white_interior_evidence &&
      ((white_strength > 0.34F && inner_mean > board_luma - 32.0F &&
        dark_fraction < 0.48F) ||
       bright_white_disk || regular_rendered_white_disk ||
       circle_white_interior)) {
    const auto rendered_confidence = regular_rendered_white_disk
                                         ? 0.50F + neutral_fraction * 0.42F
                                         : 0.0F;
    return {2, std::clamp(std::max(0.42F + white_strength * 0.50F,
                                  rendered_confidence),
                          0.0F, 1.0F)};
  }

  // 黑棋必须同时满足暗度、中性色和圆形边界三个条件。连续渐变的投影
  // 不再能够仅凭“比局部木色暗”被识别成黑棋。
  const auto black_shape = circle_support ||
                           (distributed_boundary &&
                            circular_strength > 0.20F);
  if (neutral_disk && dark_quadrant_count >= 3 && black_shape &&
      (!on_board_edge || circle_support) && black_strength > 0.38F &&
      dark_fraction > 0.46F) {
    return {1, std::clamp(0.48F + black_strength * 0.48F, 0.0F, 1.0F)};
  }

  const auto uncertainty = std::max(black_strength, white_strength);
  return {0, std::clamp(0.88F - uncertainty * 0.55F, 0.20F, 0.98F)};
}
#endif

} // namespace

void GoBoardImageRecognizer::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("is_available"),
                              &GoBoardImageRecognizer::is_available);
  godot::ClassDB::bind_method(
      godot::D_METHOD("recognize", "rgba", "width", "height", "board_size",
                      "grid_corners"),
      &GoBoardImageRecognizer::recognize,
      DEFVAL(godot::PackedVector2Array{}));
}

bool GoBoardImageRecognizer::is_available() const noexcept {
#ifdef GOTEPAD_HAS_OPENCV
  return true;
#else
  return false;
#endif
}

godot::Dictionary GoBoardImageRecognizer::recognize(
    const godot::PackedByteArray &rgba, const int64_t width,
    const int64_t height, const int64_t board_size,
    const godot::PackedVector2Array &grid_corners) const {
#ifndef GOTEPAD_HAS_OPENCV
  return error_result_("[GNE0037] board image recognition is unavailable");
#else
  cv::utils::logging::setLogLevel(cv::utils::logging::LOG_LEVEL_WARNING);
  if (width < 32 || height < 32 || width > std::numeric_limits<int>::max() ||
      height > std::numeric_limits<int>::max() || board_size < 5 ||
      board_size > 25 || rgba.size() != width * height * 4) {
    return error_result_("[GNE0038] invalid board image data");
  }
  if (!grid_corners.is_empty() && grid_corners.size() != 4)
    return error_result_("[GNE0039] invalid board image corners");

  try {
    cv::Mat source_rgba(static_cast<int>(height), static_cast<int>(width),
                        CV_8UC4,
                        const_cast<uint8_t *>(rgba.ptr()));
    cv::Mat working_rgba{};
    const auto maximum_dimension = std::max(width, height);
    const auto scale = maximum_dimension > kMaximumWorkingDimension
                           ? static_cast<double>(kMaximumWorkingDimension) /
                                 maximum_dimension
                           : 1.0;
    if (scale < 1.0)
      cv::resize(source_rgba, working_rgba, cv::Size{}, scale, scale,
                 cv::INTER_AREA);
    else
      working_rgba = source_rgba;

    cv::Mat gray{};
    cv::cvtColor(working_rgba, gray, cv::COLOR_RGBA2GRAY);
    std::array<cv::Point2f, 4> corners{};
    if (grid_corners.is_empty()) {
      corners = detect_grid_corners_(gray, working_rgba,
                                     static_cast<int>(board_size));
    } else {
      std::vector<cv::Point2f> supplied{};
      supplied.reserve(4);
      for (const auto &point : grid_corners)
        supplied.emplace_back(static_cast<float>(point.x * scale),
                              static_cast<float>(point.y * scale));
      corners = order_corners_(supplied);
    }

    constexpr int kRectifiedSize = 1200;
    constexpr float kRectifiedMargin = 54.0F;
    const std::array<cv::Point2f, 4> destination{{
        {kRectifiedMargin, kRectifiedMargin},
        {kRectifiedSize - kRectifiedMargin, kRectifiedMargin},
        {kRectifiedSize - kRectifiedMargin,
         kRectifiedSize - kRectifiedMargin},
        {kRectifiedMargin, kRectifiedSize - kRectifiedMargin},
    }};
    const auto transform = cv::getPerspectiveTransform(corners.data(),
                                                       destination.data());
    cv::Mat rectified{};
    cv::warpPerspective(gray, rectified, transform,
                        cv::Size(kRectifiedSize, kRectifiedSize),
                        cv::INTER_LINEAR, cv::BORDER_REPLICATE);
    cv::Mat rectified_rgba{};
    cv::warpPerspective(working_rgba, rectified_rgba, transform,
                        cv::Size(kRectifiedSize, kRectifiedSize),
                        cv::INTER_LINEAR, cv::BORDER_REPLICATE);
    cv::Mat rectified_rgb{};
    cv::cvtColor(rectified_rgba, rectified_rgb, cv::COLOR_RGBA2RGB);
    cv::Mat rectified_lab{};
    cv::cvtColor(rectified_rgb, rectified_lab, cv::COLOR_RGB2Lab);

    const auto spacing =
        (kRectifiedSize - kRectifiedMargin * 2.0F) / (board_size - 1.0F);
    cv::Mat circle_source{};
    cv::GaussianBlur(rectified, circle_source, cv::Size(5, 5), 1.4);
    std::vector<cv::Vec3f> detected_circles{};
    cv::HoughCircles(circle_source, detected_circles, cv::HOUGH_GRADIENT,
                     1.2, spacing * 0.55F, 90.0, 22.0,
                     static_cast<int>(spacing * 0.25F),
                     static_cast<int>(spacing * 0.55F));
    std::vector<float> background_samples{};
    std::vector<float> square_luma{};
    std::vector<float> square_chroma{};
    square_luma.resize(static_cast<size_t>((board_size - 1) *
                                           (board_size - 1)));
    square_chroma.resize(static_cast<size_t>((board_size - 1) *
                                             (board_size - 1)));
    for (int row = 0; row + 1 < board_size; ++row) {
      for (int column = 0; column + 1 < board_size; ++column) {
        const auto sample = bilinear_luma_(
            rectified, kRectifiedMargin + (column + 0.5F) * spacing,
            kRectifiedMargin + (row + 0.5F) * spacing);
        const auto color = bilinear_lab_(
            rectified_lab, kRectifiedMargin + (column + 0.5F) * spacing,
            kRectifiedMargin + (row + 0.5F) * spacing);
        const auto chroma =
            std::hypot(color[1] - 128.0F, color[2] - 128.0F);
        background_samples.push_back(sample);
        const auto square_index =
            static_cast<size_t>(row * (board_size - 1) + column);
        square_luma[square_index] = sample;
        square_chroma[square_index] = chroma;
      }
    }
    const auto board_luma = median_(background_samples);
    // 密集局面中，格子中心容易被相邻棋子的投影覆盖。仅为黑棋
    // 分类保留一个较亮的底色参考，避免同时改变白棋的亮度标准。
    const auto black_board_luma = percentile_(background_samples, 0.68F);
    const auto board_chroma = median_(square_chroma);

    godot::PackedInt32Array cells{};
    godot::PackedFloat32Array confidence{};
    godot::PackedVector2Array grid_points{};
    cells.resize(board_size * board_size);
    confidence.resize(board_size * board_size);
    grid_points.resize(board_size * board_size);
    const cv::Mat inverse_transform = transform.inv();
    for (int row = 0; row < board_size; ++row) {
      for (int column = 0; column < board_size; ++column) {
        const cv::Point2f center{
            kRectifiedMargin + column * spacing,
            kRectifiedMargin + row * spacing,
        };
        std::vector<float> local_background{};
        std::vector<float> local_chroma{};
        local_background.reserve(4);
        local_chroma.reserve(4);
        for (int square_row = row - 1; square_row <= row; ++square_row) {
          for (int square_column = column - 1; square_column <= column;
               ++square_column) {
            if (square_row < 0 || square_column < 0 ||
                square_row >= board_size - 1 ||
                square_column >= board_size - 1)
              continue;
            const auto square_index = static_cast<size_t>(
                square_row * (board_size - 1) + square_column);
            local_background.push_back(square_luma[square_index]);
            local_chroma.push_back(square_chroma[square_index]);
          }
        }
        const auto local_board_luma =
            local_background.empty() ? board_luma
                                     : median_(local_background);
        const auto local_black_board_luma =
            std::max(local_board_luma, black_board_luma - 14.0F);
        const auto local_board_chroma =
            local_chroma.empty() ? board_chroma : median_(local_chroma);
        const auto edge_circle_support =
            std::any_of(detected_circles.begin(), detected_circles.end(),
                        [&center, spacing](const cv::Vec3f &circle) {
                          return std::hypot(circle[0] - center.x,
                                            circle[1] - center.y) <
                                 spacing * 0.30F;
                        });
        const auto classified = classify_cell_(
            rectified, rectified_lab, center, spacing, local_board_luma,
            local_black_board_luma, local_board_chroma,
            edge_circle_support);
        const auto index = row * board_size + column;
        cells.set(index, classified.color);
        confidence.set(index, classified.confidence);
        const auto denominator = inverse_transform.at<double>(2, 0) * center.x +
                                 inverse_transform.at<double>(2, 1) * center.y +
                                 inverse_transform.at<double>(2, 2);
        const auto image_x =
            (inverse_transform.at<double>(0, 0) * center.x +
             inverse_transform.at<double>(0, 1) * center.y +
             inverse_transform.at<double>(0, 2)) /
            denominator;
        const auto image_y =
            (inverse_transform.at<double>(1, 0) * center.x +
             inverse_transform.at<double>(1, 1) * center.y +
             inverse_transform.at<double>(1, 2)) /
            denominator;
        grid_points.set(
            index,
            {static_cast<godot::real_t>(image_x / scale),
             static_cast<godot::real_t>(image_y / scale)});
      }
    }

    godot::PackedVector2Array returned_corners{};
    for (const auto &corner : corners)
      returned_corners.push_back(
          {static_cast<godot::real_t>(corner.x / scale),
           static_cast<godot::real_t>(corner.y / scale)});

    godot::Dictionary result{};
    result["ok"] = true;
    result["message"] = godot::String{};
    result["board_size"] = board_size;
    result["corners"] = returned_corners;
    result["cells"] = cells;
    result["confidence"] = confidence;
    result["grid_points"] = grid_points;
    return result;
  } catch (const cv::Exception &error) {
    auto result = error_result_("[GNE0040] board image recognition failed");
    result["detail"] = godot::String::utf8(error.what());
    return result;
  }
#endif
}

} // namespace nd::go::gdext
