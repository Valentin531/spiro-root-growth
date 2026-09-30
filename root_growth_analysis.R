# ==============================================================================
#  Root Growth Analysis — Y coordinate (Max_1)
#  Max_1 = bottom edge of bounding box = how far the root has grown downward
# ==============================================================================

library(tidyverse)
library(patchwork)
library(scales)


# ── 1. Settings ──────────────────────────────────────────────────────────────

EXCLUDE_MOCK2 <- c("Label 3", "Label 4")
EXCLUDE_TOR1 <- c("Label 7")
EXCLUDE_TOR2 <- c("Label 6", "Label 2")

T_START       <- 0
T_END         <- 165
MAX_Y_JUMP    <- 10    # max realistic Y change per hour (px)

px_per_cm <- 192
px_per_mm <- 19.2

output_dir <- "trajectory_output"
dir.create(output_dir, showWarnings = FALSE)

plate_colours <- c(tor1 = "#F87171", tor2 = "#FCA5A5",
                   mock1 =  "#60A5FA", mock2 = "#93C5FD")
plate_labels  <- c(tor1 = "Plate 1 — tor1",   tor2 = "Plate 2 — tor2",
                   mock1 = "Plate 3 — mock1", mock2 = "Plate 4 — mock2")




# ── 2. Load data ─────────────────────────────────────────────────────────────

raw_p1 <- read_csv("measurement_results/Plate1_combined_table.csv",
                   show_col_types = FALSE) %>%
  mutate(plate = "tor1", plate_group = "tor") %>%
  filter(!`Predicted Class` %in% EXCLUDE_TOR1)


raw_p2 <- read_csv("measurement_results/Plate2_combined_table.csv",
                   show_col_types = FALSE) %>%
  mutate(plate = "tor2", plate_group = "tor") %>%
  filter(!`Predicted Class` %in% EXCLUDE_TOR2)

raw_p3 <- read_csv("measurement_results/Plate3_combined_table.csv",
                   show_col_types = FALSE) %>%
  mutate(plate = "mock1", plate_group = "mock")

raw_p4 <- read_csv("measurement_results/Plate4_combined_table.csv",
                   show_col_types = FALSE) %>%
  mutate(plate = "mock2", plate_group = "mock") %>%
  filter(!`Predicted Class` %in% EXCLUDE_MOCK2)

raw <- bind_rows(raw_p1, raw_p2, raw_p3, raw_p4)

cat("Loaded", nrow(raw), "rows across", n_distinct(raw$plate), "plates\n")


# ── 3. Prepare per-root Y coordinates ────────────────────────────────────────
#
# Max_1 = bottom edge of bounding box = how far root tip has reached
# When a root has multiple fragments, keep the largest one.
# Filter out unrealistic Y jumps (> MAX_Y_JUMP per hour).
#Roots cannot go into negative, maximal stay at 0

coords <- raw %>%
  rename(root = `Predicted Class`,
         max0 = `Bounding Box Maximum_0`,
         max1 = `Bounding Box Maximum_1`,
         size = `Size in pixels`) %>%
  group_by(plate, plate_group, timestep, root) %>%
  slice_max(size, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  filter(timestep >= T_START, timestep <= T_END) %>%
  arrange(plate, root, timestep) %>%
  group_by(plate, root) %>%
  mutate(
    dy       = max1 - lag(max1),
    is_jump  = !is.na(dy) & abs(dy) > MAX_Y_JUMP,    # check on RAW dy
    y_growth = max1 - first(max1)
  ) %>%
  filter(!is_jump) %>%                                 # remove jumps first
  mutate(
    dy = max1 - lag(max1))   %>%                             # recalculate after removal                                   # THEN clamp to 0
  ungroup()

coords <- coords %>%
  group_by(plate, root) %>%
  mutate(fixed_x = first(max0)) %>%
  ungroup()

##### Convert it into mm
coords_mm <- coords %>%
  mutate(max1 = max1 / px_per_mm,
         y_growth = y_growth / px_per_mm,
         dy = dy / px_per_mm,
         max0 = max0/px_per_mm,
         fixed_x = fixed_x/px_per_mm)

# ── 4. Single root example ──────────────────────────────────────────────────

TARGET_PLATE <- "mock1"
TARGET_ROOT  <- "Label 1"

target <- coords_mm  %>%
  filter(plate == TARGET_PLATE, root == TARGET_ROOT)

# 4.1 Raw Max_1 over time
target %>%
  ggplot(aes(x = timestep, y = max1)) +
  geom_line(colour = "#1D9E75", linewidth = 0.8) +
  scale_y_reverse() +
  labs(title    = paste0("Root tip Y position — ", TARGET_PLATE, " ", TARGET_ROOT),
       subtitle = "Max_1 increases as root grows downward",
       x = "Timepoint (hours)", y = "Max_1 (px) — growth ↓") +
  theme_classic(base_size = 13)

ggsave(file.path("figures/root_length_growth/downwards_growth_per_h_mock1_root1.png"), width = 12,
       height = 10, dpi= 150)

# 4.2 Growth from start
target %>%
  ggplot(aes(x = timestep, y = y_growth)) +
  geom_line(colour = "#1D9E75", linewidth = 0.8) +
  labs(title    = paste0("Root elongation — ", TARGET_PLATE, " ", TARGET_ROOT),
       subtitle = "Growth = Max_1(t) − Max_1(t=0)",
       x = "Timepoint (hours)", y = "Growth from start (px)") +
  theme_classic(base_size = 13)

ggsave(file.path("figures/root_length_growth/upwards_growth_per_h_mock1_root1.png"), width = 12,
       height = 10, dpi= 150)

# 4.3 Hourly growth rate dy can go maximum to 0
target %>%
  filter(!is.na(dy)) %>%
  ggplot(aes(x = timestep, y = dy)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_line(colour = "#1D9E75", linewidth = 0.5) +
  geom_point(colour = "#1D9E75", size = 1, alpha = 0.5) +
  labs(title    = paste0("Hourly growth rate — ", TARGET_PLATE, " ", TARGET_ROOT),
       subtitle = "ΔY per hour (px)",
       x = "Timepoint (hours)", y = "ΔY (px/hr)") +
  theme_classic(base_size = 13)

ggsave(file.path("figures/root_length_growth/hourly_growth_rate_mock1_root1.png"), width = 12,
       height = 10, dpi= 150)

# 4.4 Root tip trajectory (X vs Y)
target %>%
  mutate(fixed_x = first(max0)) %>%
  ggplot(aes(x = fixed_x, y = max1, colour = timestep)) +
  geom_path(linewidth = 0.3, alpha = 0.4, colour = "grey50") +
  geom_point(size = 2.4, alpha = 0.9) +
  scale_y_reverse() +
  scale_colour_viridis_c(option = "plasma", end = 0.92, name = "Timepoint") +
  labs(title    = paste0("Root tip trajectory — ", TARGET_PLATE, " ", TARGET_ROOT),
       subtitle = "X = fixed at first Max_0  |  Y = root tip growing downward",
       x = "X position (px)",
       y = "Y position (Max_1) — growth direction ↓") +
  theme_classic(base_size = 13)

ggsave(file.path("figures/root_length_growth/hourly_trajectory_mock1_root1.png"), width = 12,
       height = 10, dpi= 150)



# ── 5. All root trajectories per plate ──────────────────────────────────────
#
# X = original horizontal position (max0)
# Y = root tip position (max1)
# Unrealistic Y jumps already removed above


## Fixed Y

all_roots_trajectory <- coords_mm %>%
  group_by(plate, root) %>%
  mutate(
    y_aligned = max1 - first(max1)
  ) %>%
  ungroup() %>%
  ggplot(aes(x = fixed_x,   
             y = y_aligned,             # all start at Y = 0
             colour = plate,
             group = interaction(plate, root))) +
  geom_path(linewidth = 0.5, alpha = 0.45) +
  geom_point(size = 1.2, alpha = 0.7) +
  scale_y_reverse() +
  scale_colour_manual(values = plate_colours, labels = plate_labels) +
  facet_wrap(~ plate,
             ncol = 2,
             labeller = labeller(plate = plate_labels)) +
  labs(
    x = "X (fixed at 0)",
    y = "ΔY from start (mm) — growth direction ↓"
  ) +
  theme_classic(base_size = 11) +
  theme(
    strip.background = element_blank(),
    strip.text = element_text(face = "bold", size = 11),
    legend.position = "top", legend.text = element_text(size = 10)
  )

print(all_roots_trajectory)

ggsave("figures/root_length_growth/fig_all_root_trajectories.png", plot = all_roots_trajectory, 
  width = 12,
  height = 10, dpi= 150
)



#All roots, colored by the phase


CYCLE_ORIGIN <- 0

all_roots_trajectory_colored <- coords_mm %>%
  group_by(plate, root) %>%
  mutate(
    y_aligned = max1 - first(max1)
  ) %>%
  ungroup() %>%
  mutate(
    cycle = (timestep - CYCLE_ORIGIN) %/% 24
  ) %>%
  ggplot(aes(x = fixed_x,   
             y = y_aligned,
             colour = factor(cycle),
             group = interaction(plate, root))) +
  geom_path(linewidth = 0.5, alpha = 0.3, colour = "grey70") +
  geom_point(size = 1.4, alpha = 0.85) +
  scale_y_reverse() +
  scale_colour_manual(
    values = c(
      "0" = "#E8A838",
      "1" = "#E06530",
      "2" = "#C23B3B",
      "3" = "#8B3A8B",
      "4" = "#2B7BBB",
      "5" = "#1B3260",
      "6" = "#2B6B5B"
    ),
    name   = "Day",
    labels = c(
      "0" = "Day 1",
      "1" = "Day 2",
      "2" = "Day 3",
      "3" = "Day 4",
      "4" = "Day 5",
      "5" = "Day 6",
      "6" = "Day 7"
    )
  ) +
  facet_wrap(~ plate,
             ncol = 2,
             labeller = labeller(plate = plate_labels)) +
  labs(
    title    = "Root growth from origin — coloured by day",
    subtitle = paste0("Each colour = one 24h cycle  |  Y jumps > ",
                      MAX_Y_JUMP, " px/hr removed"),
    x = "X position",
    y = "ΔY from start (px) — growth direction ↓"
  ) +
  theme_classic(base_size = 11) +
  theme(
    strip.background = element_blank(),
    strip.text = element_text(face = "bold", size = 11),
    legend.position = "right"
  )

all_roots_trajectory_colored

ggsave("figures/root_length_growth/fig_all_root_trajectories_colored.png", plot = all_roots_trajectory_colored, 
       width = 12,
       height = 10, dpi= 150
)





############################################################
# Daily growth segments — side by side per root
# Each day = one colored bar showing how much the root
# grew during that 24h cycle. Roots stacked vertically,
# plates in 2x2 grid.
############################################################

CYCLE_ORIGIN <- 0

# Calculate growth per day per root
daily_growth <- coords_mm %>%
  mutate(cycle = (timestep - CYCLE_ORIGIN) %/% 24) %>%
  group_by(plate, plate_group, root, cycle) %>%
  summarise(
    y_start = min(max1),
    y_end   = max(max1),
    growth  = max(max1) - min(max1),
    .groups = "drop"
  ) %>%
  # Create a label for each root (plate + root)
  mutate(
    root_label = paste0(root),
    # Order plates: mock1 top-left, mock2 top-right,
    # tor1 bottom-left, tor2 bottom-right
    plate = factor(plate,
                   levels = c("mock1", "mock2", "tor1", "tor2"))
  )

# For side-by-side placement: cumulative x-position per root
# Each day segment sits next to the previous one
daily_segments <- daily_growth %>%
  arrange(plate, root, cycle) %>%
  group_by(plate, root) %>%
  mutate(
    # Cumulative growth = where this segment starts vertically
    cum_start = lag(cumsum(growth), default = 0),
    cum_end   = cumsum(growth)
  ) %>%
  ungroup()

# Plot as vertical bars (each bar = one day's growth)
p_daily <- ggplot(daily_segments,
                  aes(x = factor(cycle),
                      y = growth,
                      fill = factor(cycle))) +
  geom_col(width = 0.75, color = "white", linewidth = 0.2) +
  # Add growth value on each bar
  geom_text(aes(label = round(growth, 1)),
            position = position_stack(vjust = 0.5),
            size = 2, color = "white", fontface = "bold") +
  facet_grid(root ~ plate,
             labeller = labeller(
               plate = c(mock1 = "Mock Plate 1",
                         mock2 = "Mock Plate 2",
                         tor1  = "TOR Plate 1",
                         tor2  = "TOR Plate 2")
             )) +
  scale_fill_manual(
    values = c(
      "0" = "#E8A838",
      "1" = "#E06530",
      "2" = "#C23B3B",
      "3" = "#8B3A8B",
      "4" = "#2B7BBB",
      "5" = "#1B3260",
      "6" = "#2B6B5B"
    ),
    name   = "Day",
    labels = c("Day 1", "Day 2", "Day 3", "Day 4",
               "Day 5", "Day 6", "Day 7")
  ) +
  labs(
    title    = "Daily root growth — each bar = one day's elongation",
    subtitle = "Rows = individual roots | Columns = plates (Mock top, TOR bottom)",
    x = "Day", y = "Growth per day (mm)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold"),
    plot.subtitle    = element_text(size = 9, color = "grey40"),
    strip.text.y     = element_text(angle = 0, hjust = 0, size = 8),
    strip.text.x     = element_text(face = "bold", size = 10),
    panel.grid.major.x = element_blank(),
    legend.position  = "right"
  )

print(p_daily)
ggsave("figures/root_length_growth/daily_growth_per_root_comparison.png",
       plot = p_daily,
       width = 14,
       height = 2 + 1.2 * n_distinct(daily_segments$root),
       dpi = 150)


# ── Alternative: stacked segments (total length build-up) ────────
# Shows how each day's growth ADDS to the total root length


p_stacked <- ggplot(daily_segments,
                    aes(x = root_label,
                        y = growth,
                        fill = factor(cycle, levels = 6:0))) +
  geom_col(width = 0.7, color = "white", linewidth = 0.2,
           position = position_stack(reverse = FALSE)) +
  facet_wrap(~ plate, ncol = 2, scales = "free_x",
             labeller = labeller(
               plate = c(mock1 = "Mock Plate 1",
                         mock2 = "Mock Plate 2",
                         tor1  = "TOR Plate 1",
                         tor2  = "TOR Plate 2")
             )) +
  scale_fill_manual(
    values = c(
      "0" = "#E8A838",
      "1" = "#E06530",
      "2" = "#C23B3B",
      "3" = "#8B3A8B",
      "4" = "#2B7BBB",
      "5" = "#1B3260",
      "6" = "#2B6B5B"
    ),
    name   = "Day",
    labels = c("Day 7", "Day 6", "Day 5", "Day 4",
               "Day 3", "Day 2", "Day 1")
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(x = "Root", y = "Total growth (mm)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title         = element_text(face = "bold"),
    plot.subtitle      = element_text(size = 9, color = "grey40"),
    strip.text         = element_text(face = "bold", size = 11),
    axis.text.x        = element_text(angle = 45, hjust = 1, size = 8),
    panel.grid.major.x = element_blank(),
    legend.position    = "right"
  )


p_stacked <- p_stacked +
  scale_x_discrete(
    labels = function(x) gsub("^Label\\s*", "", x)
  )

print(p_stacked)

ggsave("figures/root_length_growth/daily_growth_stacked_comparison.pdf",
       plot = p_stacked, width = 14, height = 8, dpi = 150)










# ── 5. All roots per plate — growth from start ──────────────────────────────

coords_mm %>%
  ggplot(aes(x = timestep, y = y_growth, colour = root, group = root)) +
  geom_line(linewidth = 0.5, alpha = 0.8) +
  facet_wrap(~ plate, ncol = 2, labeller = labeller(plate = plate_labels)) +
  scale_y_continuous(labels = comma) +
  labs(title    = "Root elongation — all roots per plate",
       subtitle = "Growth = Max_1(t) − Max_1(t=0)  |  Each line = one root",
       x = "Timepoint (hours)", y = "Growth from start (px)",
       colour = "Root") +
  theme_classic(base_size = 11) +
  theme(strip.background = element_blank(),
        strip.text = element_text(face = "bold", size = 11),
        legend.position = "right")

ggsave("figures/root_length_growth/root_elongation_all_roots_per_plate.png", 
       width = 12,
       height = 10, dpi= 150)



# Average Root length colored

CYCLE_ORIGIN <- 0

# Average Y growth across all roots per group per timepoint
avg_growth <- coords_mm %>%
  group_by(plate, root) %>%
  mutate(y_aligned = max1 - first(max1)) %>%
  ungroup() %>%
  mutate(cycle = (timestep - CYCLE_ORIGIN) %/% 24) %>%
  group_by(plate_group, timestep, cycle) %>%
  summarise(
    mean_y = mean(y_aligned),
    sem_y  = sd(y_aligned) / sqrt(n()),
    .groups = "drop"
  ) %>%
  # give each group a fixed X position (0 for both, faceted)
  mutate(fixed_x = 0)

avg_growth %>%
  ggplot(aes(x = fixed_x,
             y = mean_y,
             colour = factor(cycle),
             group = plate_group)) +
  geom_path(linewidth = 0.5, alpha = 0.3, colour = "grey70") +
  geom_point(size = 2.2, alpha = 0.9) +
  # error bars for SEM
  geom_errorbarh(aes(xmin = fixed_x - sem_y,
                     xmax = fixed_x + sem_y),
                 height = 0, linewidth = 0.3, alpha = 0.4) +
  scale_y_reverse() +
  scale_colour_manual(
    values = c(
      "0" = "#E8A838",
      "1" = "#E06530",
      "2" = "#C23B3B",
      "3" = "#8B3A8B",
      "4" = "#2B7BBB",
      "5" = "#1B3260",
      "6" = "#2B6B5B"
    ),
    name   = "Day",
    labels = c(
      "0" = "Day 1", "1" = "Day 2", "2" = "Day 3",
      "3" = "Day 4", "4" = "Day 5", "5" = "Day 6",
      "6" = "Day 7"
    )
  ) +
  facet_wrap(~ plate_group,
             ncol = 2,
             labeller = labeller(
               plate_group = c(tor = "TOR (avg Plates 1+2)",
                               mock = "MOCK (avg Plates 3+4)")
             )) +
  labs(
    title    = "Average root elongation — TOR vs MOCK",
    subtitle = "Mean across all roots per group  |  Horizontal bars = ±SEM",
    x = NULL,
    y = "Mean ΔY from start (px) — growth direction ↓"
  ) +
  theme_classic(base_size = 13) +
  theme(
    strip.background = element_blank(),
    strip.text = element_text(face = "bold", size = 13),
    legend.position = "right",
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank()
  )


ggsave("figures/root_length_growth/average_root_length_TOR_vs_MOCK.png", 
       width = 12,
       height = 10, dpi= 150)






# ── 6. Per-root hourly growth rate — all plates ─────────────────────────────

coords_mm %>%
  filter(!is.na(dy)) %>%
  ggplot(aes(x = timestep, y = dy, colour = root, group = root)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_line(linewidth = 0.4, alpha = 0.7) +
  facet_wrap(~ plate, ncol = 2, labeller = labeller(plate = plate_labels)) +
  labs(title    = "Hourly growth rate (ΔY) — per root",
       x = "Timepoint (hours)", y = "ΔY (px/hr)", colour = "Root") +
  theme_classic(base_size = 11) +
  theme(strip.background = element_blank(),
        strip.text = element_text(face = "bold", size = 11),
        legend.position = "right")


ggsave("figures/root_length_growth/Hourly_growth_rate_all_roots.png", 
       width = 12,
       height = 10, dpi= 150)


# ── 7. Compare mock1 Label 1 vs tor1 Label 1 ────────────────────────────────

compare_roots <- coords_mm %>%
  filter((plate == "mock1" & root == "Label 1") |
         (plate == "tor1"  & root == "Label 1"))

compare_roots %>%
  ggplot(aes(x = timestep, y = y_growth, colour = plate)) +
  geom_line(linewidth = 0.9) +
  scale_colour_manual(values = c(tor1 = "#378ADD", mock1 = "#1D9E75"),
                      labels = c(tor1 = "tor1 — Label 1",
                                 mock1 = "mock1 — Label 1")) +
  labs(title    = "Root elongation — tor1 vs mock1, Label 1",
       subtitle = "Both start at 0  |  Y = how far the root tip moved downward",
       x = "Timepoint (hours)", y = "Growth from start (px)",
       colour = NULL) +
  theme_classic(base_size = 13) +
  theme(legend.position = "top")

ggsave(file.path(output_dir, "fig_compare_label1.pdf"),
       width = 10, height = 5)


# ── 8. Mean growth — all four plates ────────────────────────────────────────

plate_mean <- coords_mm %>%
  group_by(plate, plate_group, timestep) %>%
  summarise(mean_growth = mean(y_growth),
            sem_growth  = sd(y_growth) / sqrt(n()),
            .groups     = "drop")

plate_mean %>%
  ggplot(aes(x = timestep, y = mean_growth,
             colour = plate, fill = plate)) +
  geom_ribbon(aes(ymin = mean_growth - sem_growth,
                  ymax = mean_growth + sem_growth),
              alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.9) +
  scale_colour_manual(values = plate_colours, labels = plate_labels) +
  scale_fill_manual(values = plate_colours, guide = "none") +
  scale_y_continuous(labels = comma) +
  labs(title    = "Mean root elongation — all four plates",
       subtitle = "Ribbon = ±SEM across roots within plate",
       x = "Timepoint (hours)", y = "Mean growth from start (px)",
       colour = NULL) +
  theme_classic(base_size = 13) +
  theme(legend.position = "top")


ggsave("figures/root_length_growth/mean_root_elongation_all_plates.pdf", 
       width = 12,
       height = 10, dpi= 150)

# ── 9. Mean growth — tor vs mock grouped ────────────────────────────────────

group_mean <- coords_mm %>%
  group_by(plate_group, timestep) %>%
  summarise(mean_growth = mean(y_growth),
            sem_growth  = sd(y_growth) / sqrt(n()),
            .groups     = "drop")

group_mean %>%
  ggplot(aes(x = timestep, y = mean_growth,
             colour = plate_group, fill = plate_group)) +
  geom_ribbon(aes(ymin = mean_growth - sem_growth,
                  ymax = mean_growth + sem_growth),
              alpha = 0.18, colour = NA) +
  geom_line(linewidth = 1.2) +
  scale_colour_manual(values = c(tor = "#EF4444", mock = "#3B82F6"),
                      labels = c(tor = "tor (Plates 1+2)",
                                 mock = "mock (Plates 3+4)")) +
  scale_fill_manual(values = c(tor = "#F87171", mock = "#60A5FA"),
                    guide = "none") +
  scale_y_continuous(labels = comma) +
  labs(x = "Timepoint (hours)", y = "Mean growth from start (mm)",
       colour = NULL) +
  theme_classic(base_size = 13) +
  theme(legend.position = "top", legend.text = element_text(size = 12))


ggsave("figures/root_length_growth/mean_root_elongation_TOR_vs_MOCK.pdf", 
       width = 12, height = 10, dpi= 150)

# ==============================================================================
# 10. BOXPLOT — total growth tor vs mock with p-value
# ==============================================================================

total_growth <- coords_mm %>%
  group_by(plate, plate_group, root) %>%
  summarise(
    total_dy = max(max1) - min(max1),
    .groups  = "drop"
  )

cat("\n=== Total root elongation per root ===\n")
total_growth %>%
  arrange(plate_group, plate, root) %>%
  print(n = 40)

# Wilcoxon test
p_test <- wilcox.test(total_dy ~ plate_group, data = total_growth)

cat("\nWilcoxon test (total elongation, tor vs mock):\n")
cat("  p-value =", format.pval(p_test$p.value, digits = 3), "\n")

# Boxplot
total_growth %>%
  ggplot(aes(x = plate_group, y = total_dy, fill = plate_group)) +
  geom_boxplot(width = 0.5, alpha = 0.7, outlier.shape = NA) +
  geom_jitter(width = 0.15, size = 2.5, alpha = 0.7,
              aes(colour = plate)) +
  scale_fill_manual(values = c(tor = "#EF4444", mock = "#3B82F6"),
                    guide  = "none") +
  scale_colour_manual(values = plate_colours, labels = plate_labels) +
  annotate("segment",
           x = 1, xend = 2,
           y = max(total_growth$total_dy) * 1.05,
           yend = max(total_growth$total_dy) * 1.05,
           linewidth = 0.5) +
  annotate("text",
           x = 1.5,
           y = max(total_growth$total_dy) * 1.08,
           label = paste0("p = ",
                          format.pval(p_test$p.value, digits = 3)),
           size = 4.5) +
  scale_y_continuous(labels = comma,
                     expand = expansion(mult = c(0.05, 0.15))) +
  labs(,
       x = NULL, y = "Total elongation ΔY (mm)", colour = NULL) +
  theme_classic(base_size = 14) +
  theme(legend.position = "top",legend.text = element_text(size = 12))

ggsave("figures/root_length_growth/boxplot_TOR_vs_MOCK.pdf", 
       width = 12, height = 10, dpi= 150)

# ==============================================================================
# 11. Mean hourly growth rate — tor vs mock
# ==============================================================================

hourly_grouped <- coords_mm %>%
  filter(!is.na(dy)) %>%
  group_by(plate_group, timestep) %>%
  summarise(mean_dy = mean(dy, na.rm = TRUE),
            sem_dy  = sd(dy, na.rm = TRUE) / sqrt(n()),
            .groups = "drop")

hourly_grouped %>%
  ggplot(aes(x = timestep, y = mean_dy,
             colour = plate_group, fill = plate_group)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_ribbon(aes(ymin = mean_dy - sem_dy, ymax = mean_dy + sem_dy),
              alpha = 0.18, colour = NA) +
  geom_line(linewidth = 1.0) +
  scale_colour_manual(values = c(tor = "#378ADD", mock = "#1D9E75"),
                      labels = c(tor = "tor (Plates 1+2)",
                                 mock = "mock (Plates 3+4)")) +
  scale_fill_manual(values = c(tor = "#378ADD", mock = "#1D9E75"),
                    guide = "none") +
  labs(title    = "Mean hourly growth rate — tor vs mock",
       subtitle = "ΔY per hour across all roots  |  Ribbon = ±SEM",
       x = "Timepoint (hours)", y = "Mean ΔY (px/hr)",
       colour = NULL) +
  theme_classic(base_size = 13) +
  theme(legend.position = "top")

ggsave("figures/root_length_growth/mean_hourly_growth_rate_TOR_vs_MOCK.png", 
       width = 12, height = 10, dpi= 150)




#bar chart after recovery phase

CYCLE_ORIGIN <- 46   # align to proper day/night cycle

diurnal_hourly <- coords_mm %>%
  group_by(plate, root) %>%
  arrange(timestep) %>%
  mutate(dy = max1 - lag(max1)) %>%
  ungroup() %>%
  filter(!is.na(dy)) %>%
  mutate(
    phase = (timestep - CYCLE_ORIGIN) %% 24
  ) %>%
  group_by(plate_group, phase) %>%
  summarise(
    mean_dy = mean(dy, na.rm = TRUE),
    sem_dy  = sd(dy, na.rm = TRUE) / sqrt(n()),
    n_obs   = n(),
    .groups = "drop"
  )

diurnal_hourly %>%
  ggplot(aes(x = factor(phase), y = mean_dy, fill = plate_group)) +
  annotate("rect",
           xmin = 12.5, xmax = 24.5,
           ymin = -Inf, ymax = Inf,
           fill = "steelblue", alpha = 0.07) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_col(position = position_dodge(width = 0.7),
           width = 0.6, alpha = 0.8) +
  geom_errorbar(aes(ymin = mean_dy - sem_dy,
                    ymax = mean_dy + sem_dy),
                position = position_dodge(width = 0.7),
                width = 0.2, linewidth = 0.4) +
  scale_fill_manual(values = c(tor = "#378ADD", mock = "#1D9E75"),
                    labels = c(tor = "TOR", mock = "MOCK")) +
  scale_x_discrete(
    labels = paste0("h", sprintf("%02d", 0:23))
  ) +
  labs(
    title    = "Diurnal growth pattern — TOR vs MOCK (hourly)",
    subtitle = "All days pooled  |  Blue shading = night (h12–23)  |  Bars = mean ΔY ± SEM",
    x = "Hour of day (relative to T46)",
    y = "Mean growth per hour (ΔY px/hr)",
    fill = NULL
  ) +
  theme_classic(base_size = 13) +
  theme(
    legend.position = "top",
    axis.text.x     = element_text(angle = 45, hjust = 1, size = 9)
  )


ggsave("figures/root_length_growth/diurnal_growth_hourly.png", 
       width = 12, height = 10, dpi= 150)




#barchart plot with trend line

CYCLE_ORIGIN <- 46

diurnal_hourly <- coords_mm %>%
  group_by(plate, root) %>%
  arrange(timestep) %>%
  mutate(dy = max1 - lag(max1)) %>%
  ungroup() %>%
  filter(!is.na(dy)) %>%
  mutate(
    phase = (timestep - CYCLE_ORIGIN) %% 24
  ) %>%
  group_by(plate_group, phase) %>%
  summarise(
    mean_dy = mean(dy, na.rm = TRUE),
    sem_dy  = sd(dy, na.rm = TRUE) / sqrt(n()),
    n_obs   = n(),
    .groups = "drop"
  )

diurnal_hourly %>%
  ggplot(aes(x = phase, y = mean_dy, fill = plate_group)) +
  annotate("rect",
           xmin = 11.5, xmax = 23.5,
           ymin = -Inf, ymax = Inf,
           fill = "steelblue", alpha = 0.07) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_col(position = position_dodge(width = 0.7),
           width = 0.6, alpha = 0.6) +
  geom_errorbar(aes(ymin = mean_dy - sem_dy,
                    ymax = mean_dy + sem_dy,
                    group = plate_group),
                position = position_dodge(width = 0.7),
                width = 0.2, linewidth = 0.4) +
  # smooth trend lines on top
  geom_smooth(aes(colour = plate_group),
              method = "loess", span = 0.8,
              se = FALSE, linewidth = 1.2) +
  scale_fill_manual(values = c(tor = "#378ADD", mock = "#1D9E75"),
                    labels = c(tor = "TOR", mock = "MOCK")) +
  scale_colour_manual(values = c(tor = "#1B4F8A", mock = "#0D5E3A"),
                      labels = c(tor = "TOR trend", mock = "MOCK trend")) +
  scale_x_continuous(
    breaks = 0:23,
    labels = paste0("h", sprintf("%02d", 0:23))
  ) +
  labs(
    x = "Hour of day",
    y = "Mean growth per hour (ΔY mm/hr)",
    fill = NULL, colour = NULL
  ) +
  theme_classic(base_size = 13) +
  theme(
    legend.position = "top",
    axis.text.x     = element_text(angle = 45, hjust = 1, size = 9)
  )


ggsave("figures/root_length_growth/diurnal_growth_hourly_trendline.pdf", 
       width = 12, height = 10, dpi= 150)








#Growth for all hours individually
library(ggplot2)


hourly_all <- coords_mm %>%
  filter(timestep >= 0) %>%
  group_by(plate, root) %>%
  arrange(timestep) %>%
  mutate(dy = max1 - lag(max1)) %>%
  ungroup() %>%
  filter(!is.na(dy)) %>%
  group_by(plate_group, timestep) %>%
  summarise(
    mean_dy = mean(dy, na.rm = TRUE),
    sem_dy  = sd(dy, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

# Night shading rectangles
CYCLE_ORIGIN <- 0


# Night shading rectangles
# Build night blocks across the actual data range
light_blocks <- data.frame(
  xmin = seq(-2, 165, by = 24)
) %>%
  mutate(xmax = pmin(xmin + 12, 165))

# Dark blocks (ZT12-24 each day)
dark_blocks <- data.frame(
  xmin = seq(-2 + 12, 165, by = 24)
) %>%
  mutate(xmax = pmin(xmin + 12, 165))




hourly_all %>%
  ggplot(aes(x = timestep, y = mean_dy, fill = plate_group)) +
  geom_rect(data = light_blocks,
             aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = Inf),
             inherit.aes = FALSE,
             fill = "yellow", alpha = 0.3) +
  geom_rect(data = dark_blocks,
            aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = Inf),
            inherit.aes = FALSE,
            fill = "gray70", alpha = 0.3)  +
  ylim(0,2.5) + 
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.5) +
  geom_col(position = position_dodge(width = 0.7),
           width = 0.8, alpha = 0.5) +
  geom_errorbar(aes(ymin = mean_dy - sem_dy,
                    ymax = mean_dy + sem_dy,
                    group = plate_group),
                position = position_dodge(width = 0.7),
                width = 0.2, linewidth = 0.3, alpha= 0.5) +
  geom_smooth(aes(colour = plate_group),
              method = "loess", span = 0.2,
              se = FALSE, linewidth = 1.5) +
  geom_vline(xintercept = 22,
             linetype = "dashed",
             colour = "grey30",
             linewidth = 1.0) +
  geom_vline(xintercept = 94,
             linetype = "dashed",
             colour = "grey30",
             linewidth = 1.0) +
  annotate("text",
           x = 0, y = 0.14,            # adjust y if needed
           label = "Acclimation\nperiod",
           hjust = 0, size = 5,
           colour = "black",alpha = 1,
           fontface = "italic") + 
  annotate("text",
           x = 48, y = 0.14,            # adjust y if needed
           label = "Early\ninterval",
           hjust = 0, size = 5, alpha= 1,
           colour = "black",
           fontface = "italic") +
  annotate("text",
           x = 120, y = 0.14,            # adjust y if needed
           label = "Late\ninterval",
           hjust = 0, size = 5, alpha = 1,
           colour = "black",
           fontface = "italic") +
  scale_fill_manual(values = c(tor = "#EF4444", mock = "#3B82F6"),
                    labels = c(tor = "TOR", mock = "MOCK")) +
  scale_colour_manual(values = c(tor = "#F87171", mock = "#60A5FA"),
                      labels = c(tor = "TOR trend", mock = "MOCK trend")) +
  scale_x_continuous(breaks = seq(-2, 165, 12), expand = c(0, 0),
                     labels = function(x) paste0("T", x+2)) +
  scale_y_continuous(limits = c(0, 0.15),expand = c(0, 0)) +
  labs(
    x = "Timepoint (hours)",
    y = "Mean growth per hour (ΔY mm/hr)",
    fill = NULL, colour = NULL
  ) +
  theme_classic(base_size = 13) +
  theme(
    legend.position = "top",
    axis.text.x     = element_text(angle = 45, hjust = 1)
  )






ggsave("figures/root_length_growth/hourly_rate_full_timecourse_smooth.pdf", 
       width = 15, height = 10, dpi= 300)



####################Cosinus fit - Circa Compare


############################################################
# CIRCACOMPARE ON ROOT GROWTH RATE
# Mock vs TOR (DEX) — phenotypic parallel to transcriptomics
#
# Uses the same circaCompare framework as the per-gene
# transcriptomic analysis, applied to hourly root growth
# rate. Tests whether phase, amplitude, and mesor of the
# growth oscillation differ between Mock and TOR.
#
# If mesor is significant but phase is not, this is the
# phenotypic mirror of the transcriptomic finding:
# TOR changes HOW MUCH roots grow, not WHEN they grow.
#
# INPUT:
#   CSV with columns: plate_group, timestep, mean_dy, sem_dy
#   plate_group = "mock" or "tor" (or similar)
#   timestep    = hours (continuous, e.g. 47, 48, ..., 150)
#   mean_dy     = mean growth rate per hour (px/hr)
#   sem_dy      = standard error of the mean
#
# OUTPUT:
#   results/root_growth/circacompare_growth.csv
#   figures/root_growth/growth_circacompare_fit.png
#   figures/root_growth/growth_raw_with_fit.png
############################################################


  library(dplyr)
  library(ggplot2)
  library(circacompare)


dir.create("results/root_growth",
           showWarnings = FALSE, recursive = TRUE)
dir.create("figures/root_growth",
           showWarnings = FALSE, recursive = TRUE)

############################################################
# 1. LOAD DATA
############################################################

# UPDATE THIS PATH to your actual data file
growth <- hourly_all


# Standardize column names and group labels
growth <- growth %>%
  mutate(
    group = case_when(
      tolower(plate_group) %in% c("mock", "mock_control") ~ "1_Mock",
      tolower(plate_group) %in% c("tor", "dex", "tor_ko")  ~ "2_TOR",
      TRUE ~ plate_group
    ),
    time = as.numeric(timestep),
    measure = as.numeric(mean_dy)
  ) %>%
  filter(!is.na(measure), !is.na(time))

time_seq <- seq(min(growth$time), max(growth$time), by = 0.5)

cat("=== DATA OVERVIEW ===\n")
cat("Timepoints per group:\n")
growth %>% count(group) %>% print()
cat("Time range:", min(growth$time), "to", max(growth$time), "hours\n")
cat("Groups:", paste(unique(growth$group), collapse = ", "), "\n\n")

############################################################
# 2. RUN CIRCACOMPARE
#
# Same method as the transcriptomic per-gene analysis:
# Joint cosinor model, period = 24h, tests whether
# mesor, amplitude, and phase differ between groups.
############################################################

cat("=== RUNNING CIRCACOMPARE ===\n\n")


# Split by group
mock_data <- growth %>% filter(group == "1_Mock")
tor_data  <- growth %>% filter(group == "2_TOR")

# Fit Mock
mock_fit <- circa_single(
  x           = mock_data,
  col_time    = "time",
  col_outcome = "measure",
  period      = 24
)
cat("=== MOCK ===\n")
print(mock_fit$summary)

# Fit TOR
tor_fit <- circa_single(
  x           = tor_data,
  col_time    = "time",
  col_outcome = "measure",
  period      = 24
)
cat("\n=== TOR ===\n")
print(tor_fit$summary)



cat("\n=== TOR ===\n")
print(tor_fit$summary)

# EXTRACT PARAMETERS (this was missing!)
mock_mesor <- mock_fit$summary$value[mock_fit$summary$parameter == "mesor"]
mock_amp   <- mock_fit$summary$value[mock_fit$summary$parameter == "amplitude"]
mock_peak  <- mock_fit$summary$value[mock_fit$summary$parameter == "peak_time_hours"]

tor_mesor <- tor_fit$summary$value[tor_fit$summary$parameter == "mesor"]
tor_amp   <- tor_fit$summary$value[tor_fit$summary$parameter == "amplitude"]
tor_peak  <- tor_fit$summary$value[tor_fit$summary$parameter == "peak_time_hours"]




fit_df <- bind_rows(
  data.frame(
    timestep    = time_seq,
    fit         = mock_mesor + mock_amp * cos(2 * pi / 24 * (time_seq - mock_peak)),
    plate_group = "mock"
  ),
  data.frame(
    timestep    = time_seq,
    fit         = tor_mesor + tor_amp * cos(2 * pi / 24 * (time_seq - tor_peak)),
    plate_group = "tor"
  )
)




# Night shading rectangles
# Build night blocks across the actual data range
light_blocks <- data.frame(
  xmin = seq(-2, 165, by = 24)
) %>%
  mutate(xmax = pmin(xmin + 12, 165))

# Dark blocks (ZT12-24 each day)
dark_blocks <- data.frame(
  xmin = seq(-2 + 12, 165, by = 24)
) %>%
  mutate(xmax = pmin(xmin + 12, 165))

hourly_all %>%
  ggplot(aes(x = timestep, y = mean_dy, fill = plate_group)) +
  # Night shading via annotate — doesn't use fill aesthetic
  geom_rect(data = light_blocks,
            aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = Inf),
            inherit.aes = FALSE,
            fill = "#FFF9C4", alpha = 0.3) +
  geom_rect(data = dark_blocks,
            aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = Inf),
            inherit.aes = FALSE,
            fill = "#9FA8DA", alpha = 0.3) +
  geom_line(data = fit_df,
            aes(x = timestep, y = fit, colour = plate_group),
            linewidth = 1.4, linetype = "dashed") +
  geom_col(position = position_dodge(width = 0.7),
           width = 0.6, alpha = 0.5) +
  geom_errorbar(aes(ymin = mean_dy - sem_dy,
                    ymax = mean_dy + sem_dy,
                    group = plate_group),
                position = position_dodge(width = 0.7),
                width = 0.2, linewidth = 0.3) +
  scale_fill_manual(values = c(tor = "#EF4444", mock = "#1D9E75"),
                    labels = c(tor = "TOR", mock = "MOCK")) +
  scale_colour_manual(values = c(tor = "#EF4444", mock = "#0D5E3A"),
                      labels = c(tor = "TOR trend", mock = "MOCK trend")) +
  scale_x_continuous(breaks = seq(-2, 165, 12),
                     labels = function(x) paste0("T", x+2),
                     expand = c(0, 0)) +
  scale_y_continuous(limits = c(0, 0.15),expand = c(0, 0)) +
  labs(
    title    = "Hourly growth rate — TOR vs MOCK (T46–T165)",
    subtitle = "Shading = night | Bars = mean ΔY ± SEM | Dashed = cosinor fit (24h)",
    x = "Timepoint (hours)",
    y = "Mean growth per hour (ΔY px/hr)",
    fill = NULL, colour = NULL
  ) +
  theme_classic(base_size = 13) +
  theme(
    legend.position = "top",
    axis.text.x     = element_text(angle = 45, hjust = 1)
  )


ggsave("figures/root_length_growth/hourly_rate_full_timecourse_cosinus.png", 
       width = 12, height = 10, dpi= 150)












growth_early <- hourly_all %>%
  filter(timestep >= 22, timestep < 94) %>%
  mutate(
    group = case_when(
      plate_group == "mock" ~ "1_Mock",
      plate_group == "tor"  ~ "2_TOR"
    ),
    time = as.numeric(timestep),
    measure = as.numeric(mean_dy)
  )

growth_late <- hourly_all %>%
  filter(timestep >= 94, timestep <= 165) %>%
  mutate(
    group = case_when(
      plate_group == "mock" ~ "1_Mock",
      plate_group == "tor"  ~ "2_TOR"
    ),
    time = as.numeric(timestep),
    measure = as.numeric(mean_dy)
  )


mock_early <- circa_single(
  x = filter(growth_early, group == "1_Mock"),
  col_time = "time",
  col_outcome = "measure",
  period = 24
)

tor_early <- circa_single(
  x = filter(growth_early, group == "2_TOR"),
  col_time = "time",
  col_outcome = "measure",
  period = 24
)

mock_late <- circa_single(
  x = filter(growth_late, group == "1_Mock"),
  col_time = "time",
  col_outcome = "measure",
  period = 24
)

tor_late <- circa_single(
  x = filter(growth_late, group == "2_TOR"),
  col_time = "time",
  col_outcome = "measure",
  period = 24
)

mock_early$summary
tor_early$summary
mock_late$summary
tor_late$summary